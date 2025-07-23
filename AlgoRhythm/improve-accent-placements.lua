ardour {
  ["type"] = "EditorAction",
  name = "Improve Accent Placements",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Analyzes the rhythmic structure of main and stem tracks to intelligently align the timing of accent tracks.
]]
}

function factory() return function()

  --[[
  =====================================================================
  USER CONFIGURATION
  =====================================================================
  ]]
  local config = {
    -- This parameter defines how many accent tracks to process.
    -- The script will adjust this number of tracks immediately
    -- following the last track with a '-stem' suffix.
    number_of_accent_tracks_to_process = 1,

    -- Suffix to identify stem tracks (case-insensitive).
    stem_track_suffix = "-stem",

    -- Name of the main track for primary analysis.
    main_track_name = "main-track",

    -- VAMP plugin sensitivity for onset detection (0-100).
    -- Higher values detect more subtle rhythmic events.
    onset_sensitivity = 50,

    -- Choose alignment mode: "beats" (uses QM BarBeatTracker) or "onsets" (uses onset detector)
    align_mode = "beats",

    -- Only move a region if the distance to the target event exceeds this many seconds
    min_move_threshold_seconds = 0.01, -- 10 ms, prevents unnecessary tiny shifts

    -- How close an accent must be to a rhythmic event (in seconds)
    -- to be snapped to it.
    snap_threshold_seconds = 0.2,

    -- Set to true to print detailed logs to the console.
    debug_mode = true
  }
  --[[
  =====================================================================
  ]]

  local function log(message)
    if config.debug_mode then
      print(message)
    end
  end

  -- Find all main, stem, and accent tracks based on the session layout
  local function find_tracks(session)
    local main_track = nil
    local stem_tracks = {}
    local accent_tracks = {}
    local all_tracks = {}

    for route in session:get_tracks():iter() do
      table.insert(all_tracks, route)
    end

    local last_stem_index = -1
    for i, route in ipairs(all_tracks) do
      local track = route:to_track()
      if not track:isnil() then
        local track_name = track:name()
        if string.lower(track_name) == string.lower(config.main_track_name) then
          main_track = track
          log("Found Main Track: " .. track_name)
        end
        if string.sub(string.lower(track_name), -string.len(config.stem_track_suffix)) == string.lower(config.stem_track_suffix) then
          table.insert(stem_tracks, track)
          last_stem_index = i
          log("Found Stem Track: " .. track_name)
        end
      end
    end

    if last_stem_index > 0 and config.number_of_accent_tracks_to_process > 0 then
      local track_count = #all_tracks
      local limit = math.min(last_stem_index + config.number_of_accent_tracks_to_process, track_count)
      for i = last_stem_index + 1, limit do
        local track = all_tracks[i]:to_track()
        if not track:isnil() then
          table.insert(accent_tracks, track)
          log("Found Accent Track: " .. track:name())
        end
      end
    end
    
    return main_track, stem_tracks, accent_tracks
  end

  -- Analyze regions using VAMP to get beat and onset information
  local function analyze_rhythmic_events(tracks_to_analyze)
    log("\n=== Phase 1: Analyzing Rhythmic Events (" .. config.align_mode .. ") ===")
    local events = {}
    local sample_rate = Session:nominal_sample_rate()
    
    if not tracks_to_analyze or #tracks_to_analyze == 0 then
      print("Warning: No tracks found for analysis.")
      return events
    end

    local vamp_plugin
    if config.align_mode == "beats" then
      vamp_plugin = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
    else -- default to onsets
      vamp_plugin = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sample_rate)
      vamp_plugin:plugin():setParameter("sensitivity", config.onset_sensitivity)
    end

    -- Output index for events depends on plugin
    local output_index = 0 -- beats and onsets both first output

    for _, track in ipairs(tracks_to_analyze) do
      log("Analyzing track: " .. track:name())
      local playlist = track:playlist()
      for region in playlist:region_list():iter() do
        local ar = region:to_audioregion()
        if not ar:isnil() then
          local region_start_samples = region:position():samples()

          local callback = function(feats)
            local list = feats:table()[output_index]
            if list then
              for f in list:iter() do
                if f.hasTimestamp then
                  local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
                  local abs_pos = region_start_samples + frame_pos
                  table.insert(events, abs_pos)
                end
              end
            end
            return false
          end

          vamp_plugin:analyze(ar:to_readable(), 0, callback)
          callback(vamp_plugin:plugin():getRemainingFeatures())
          vamp_plugin:reset()
        end
      end
    end

    -- Deduplicate & sort
    local uniq, seen = {}, {}
    for _, p in ipairs(events) do
      if not seen[p] then uniq[#uniq+1] = p; seen[p] = true end
    end
    table.sort(uniq)
    log("Analysis complete. Found " .. #uniq .. " unique events.")
    return uniq
  end
  
  -- Find the closest rhythmic event to a given position
  local function find_closest_event(position_samples, event_list)
    if #event_list == 0 then return nil end
    
    local min_dist = math.huge
    local closest_event = nil
    
    -- This can be optimized with binary search since event_list is sorted
    for _, event_pos in ipairs(event_list) do
      local dist = math.abs(position_samples - event_pos)
      if dist < min_dist then
        min_dist = dist
        closest_event = event_pos
      end
    end
    
    return closest_event, min_dist
  end

  -- Reposition regions in accent tracks to align with rhythmic events
  local function align_accent_tracks(accent_tracks, rhythmic_events)
    log("\n=== Phase 2: Aligning Accent Tracks ===")
    if #accent_tracks == 0 then
      print("No accent tracks to process.")
      return
    end
    if #rhythmic_events == 0 then
      print("No rhythmic events found for alignment. Aborting.")
      return
    end

    local sample_rate = Session:nominal_sample_rate()
    local snap_threshold_samples = config.snap_threshold_seconds * sample_rate
    local min_move_samples = config.min_move_threshold_seconds * sample_rate
    local regions_moved = 0
    local add_undo = false

    Session:begin_reversible_command("Improve Accent Placements")

    for _, track in ipairs(accent_tracks) do
      log("Processing accent track: " .. track:name())
      local playlist = track:playlist()
      for region in playlist:region_list():iter() do
        region:to_stateful():clear_changes()
        
        local region_pos = region:position():samples()
        local closest_event, distance = find_closest_event(region_pos, rhythmic_events)
        
        if closest_event and distance < snap_threshold_samples and distance > min_move_samples then
          log(string.format("  Aligning region '%s' by %.3f ms", region:name(), (distance/sample_rate)*1000))
          region:set_position(Temporal.timepos_t(closest_event))
          regions_moved = regions_moved + 1
        else
          log(string.format("  Region '%s' is either already aligned (dist: %.1f) or too far. Skipping.", region:name(), distance))
        end
        
        if not Session:add_stateful_diff_command(region:to_statefuldestructible()):empty() then
          add_undo = true
        end
      end
    end

    if add_undo then
      Session:commit_reversible_command(nil)
      print(string.format("\nSUCCESS: Alignment complete. Moved %d regions across %d tracks.", regions_moved, #accent_tracks))
    else
      Session:abort_reversible_command()
      print("\nNo changes were needed.")
    end
  end


  ---------------------------------------------------------------------
  -- Script Execution
  ---------------------------------------------------------------------
  
  print("=== Improve Accent Placements Script Started ===")

  -- 1. Find the relevant tracks
  local main_track, stem_tracks, accent_tracks = find_tracks(Session)
  
  local tracks_for_analysis = {}
  if main_track then table.insert(tracks_for_analysis, main_track) end
  for _, t in ipairs(stem_tracks) do table.insert(tracks_for_analysis, t) end

  -- 2. Analyze rhythm from main and stem tracks
  local rhythmic_events = analyze_rhythmic_events(tracks_for_analysis)
  
  -- 3. Align accent tracks to the detected rhythm
  align_accent_tracks(accent_tracks, rhythmic_events)

  print("=== Script Finished ===")
  collectgarbage()

end end

function icon(params) return function(ctx, width, height, fg)
  local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(width * .6) .. "px")
  txt:set_text("✓♪")
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to(.5 * (width - tw), .5 * (height - th))
  txt:show_in_cairo_context(ctx)
end end
