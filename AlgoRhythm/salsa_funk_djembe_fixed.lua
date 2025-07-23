-- Salsa-Funk Djembe Fill Inserter (Fixed Version)
ardour {
  ["type"] = "EditorAction",
  name = "SalsaFunk Djembe Auto Inserter (40–50s)",
  author = "Human Assistant",
  description = [[
    Analyzes beats in 'salsa-funk' (40–50s), selects the 2 longest djembe regions,
    and inserts them at beat-aligned positions on a new stereo track.
  ]]
}

function factory() return function ()
  Session:begin_reversible_command("Auto-place Djembe Fills")

  -- SETUP
  local sample_rate = Session:nominal_sample_rate()
  local ANALYSIS_START_S, ANALYSIS_END_S = 5.0, 120.0
  local start_frame = math.floor(ANALYSIS_START_S * sample_rate)
  local end_frame   = math.floor(ANALYSIS_END_S * sample_rate)
  
  -- FILL PLACEMENT CONFIGURATION
  local MIN_SPACING_BEATS = 8  -- Minimum beats between fills (4 = every bar)
  local MIN_REGION_DURATION = 0.5  -- Minimum duration for djembe regions (seconds)
  local MAX_CANDIDATES_TO_USE = 10  -- Maximum number of different djembe regions to use

  local MAIN_TRACK_NAME = "salsa-funk"
  local main_track = nil
  local fill_tracks = {}

  -- TRACK IDENTIFICATION
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track:isnil() then
      local track_name = track:name()
      if track_name == MAIN_TRACK_NAME then
        main_track = track:to_audio_track()
      else
        local audio_track = track:to_audio_track()
        if not audio_track:isnil() then
          table.insert(fill_tracks, audio_track)
        end
      end
    end
  end

  if not main_track then
    print("ERROR: Main track '" .. MAIN_TRACK_NAME .. "' not found.")
    Session:abort_reversible_command()
    return
  end
  if #fill_tracks == 0 then
    print("ERROR: No other audio tracks found to use as fill sources.")
    Session:abort_reversible_command()
    return
  end

  -- BEAT DETECTION
  print("Analyzing beats in '" .. MAIN_TRACK_NAME .. "'...")

  local vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
  vamp:plugin():setParameter("Beats Per Bar", 4)

  local beat_times = {}

  for region in main_track:playlist():region_list():iter() do
    local audio_region = region:to_audioregion()
    if not audio_region:isnil() then
      local region_start_frames = audio_region:position():samples()

      local function process_features(featureset)
        if not featureset then return false end
        local features_table = featureset:table()
        if features_table then
          for _, beatlist in ipairs(features_table) do
            for beat in beatlist:iter() do
              if beat.hasTimestamp then
                local relative_frames = Vamp.RealTime.realTime2Frame(beat.timestamp, sample_rate)
                local absolute_frames = relative_frames + region_start_frames
                if absolute_frames >= start_frame and absolute_frames < end_frame then
                  table.insert(beat_times, absolute_frames / sample_rate)
                end
              end
            end
          end
        end
        return false
      end

      vamp:analyze(audio_region:to_readable(), 0, process_features)
      local remaining_features = vamp:plugin():getRemainingFeatures()
      process_features(remaining_features)
      vamp:reset()
    end
  end

  if #beat_times == 0 then
    print("No beats were detected in the 40s–50s range.")
    Session:abort_reversible_command()
    return
  end

  print(string.format("Success! Detected %d beats between %.2fs and %.2fs.", #beat_times, ANALYSIS_START_S, ANALYSIS_END_S))

  -- SELECT INSERTION POINTS & FILL CLIPS
  table.sort(beat_times)
  local insert_points = {}
  
  -- Use configuration from top of script
  
  if #beat_times > 0 then
    -- Place fills at regular intervals based on musical bars
    local beat_index = 1
    while beat_index <= #beat_times do
      table.insert(insert_points, beat_times[beat_index])
      beat_index = beat_index + MIN_SPACING_BEATS
    end
  end
  
  print(string.format("Created %d insertion points for fills.", #insert_points))

  local candidates = {}
  for _, track in ipairs(fill_tracks) do
    for region in track:playlist():region_list():iter() do
      local ar = region:to_audioregion()
      if not ar:isnil() then
        local duration = ar:length():samples() / sample_rate
        if duration > MIN_REGION_DURATION then
          table.insert(candidates, {region = ar, duration = duration})
        end
      end
    end
  end

  if #candidates == 0 then
    print("No usable djembe regions (longer than 0.5s) were found.")
    Session:abort_reversible_command()
    return
  end

  table.sort(candidates, function(a, b) return a.duration > b.duration end)
  
  -- Limit the number of candidates to use for variety
  if #candidates > MAX_CANDIDATES_TO_USE then
    local limited_candidates = {}
    for i = 1, MAX_CANDIDATES_TO_USE do
      table.insert(limited_candidates, candidates[i])
    end
    candidates = limited_candidates
  end
  
  print(string.format("Using %d different djembe regions for fills.", #candidates))

  -- CREATE NEW TRACK AND PLACE FILLS
  
  -- Create one new stereo audio track named "Djembe_Fills"
  local new_tracks = Session:new_audio_track(
    2,                                -- num input channels
    2,                                -- num output channels
    nil,                              -- parent (nil = master)
    1,                                -- how many tracks to create
    "Djembe_Fills",                   -- base name
    ARDOUR.PresentationInfo.max_order,-- presentation order constant
    ARDOUR.TrackMode.Normal,          -- track mode
    true                              -- active (not muted)
  )
  
  -- Get the first (and only) new track using front()
  local new_track = new_tracks:front():to_audio_track()
  
  if new_track:isnil() then
    print("ERROR: Failed to create the new track.")
    Session:abort_reversible_command()
    return
  end

  -- Insert the selected fill regions
  -- Cycle through candidates if we have more insertion points than candidates
  for i = 1, #insert_points do
    local insertion_time_sec = insert_points[i]
    local insertion_pos_frames = math.floor(insertion_time_sec * sample_rate)
    
    -- Select candidate using modulo to cycle through available regions
    local candidate_index = ((i - 1) % #candidates) + 1
    local region_to_clone = candidates[candidate_index].region
    
    -- Clone the region using RegionFactory
    local cloned_region = ARDOUR.RegionFactory.clone_region(region_to_clone, true, true)
    if not cloned_region:isnil() then
      new_track:playlist():add_region(cloned_region, Temporal.timepos_t(insertion_pos_frames), 1.0, false)
      print(string.format("Inserted fill clip #%d at %.2f sec (using candidate %d).", i, insertion_time_sec, candidate_index))
    else
      print(string.format("Failed to clone region for insertion at %.2f sec.", insertion_time_sec))
    end
  end

  Session:commit_reversible_command(nil)

end end

function icon(params) return function(ctx, width, height, fg)
  local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(width * 0.3) .. "px")
  txt:set_text("🥁SF🥁")
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to((width - tw) * 0.5, (height - th) * 0.5)
  txt:show_in_cairo_context(ctx)
end end 