ardour {
  ["type"] = "EditorAction",
  name = "Rhythm-Based Triangle Alignment",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Analyze the rhythm of a main track and automatically align triangle tracks to complement the beats.

This script:
1. Analyzes the selected main track for beats and rhythm patterns
2. Finds triangle-400 and triangle-500 tracks
3. Intelligently repositions their regions to complement the main rhythm
4. Creates musically appropriate placement (on-beats, off-beats, syncopation)
5. Preserves original region content while optimizing timing

Select the main rhythmic track (like drums) and run this script to automatically
align your triangle tracks for optimal musical interaction.
]]
}

function factory() return function()
  
  -- Get Editor selection
  local sel = Editor:get_selection()
  
  if sel.regions:regionlist():size() == 0 then
    print("ERROR: No regions selected. Please select the main rhythmic track to analyze.")
    return
  end
  
  print("=== RHYTHM-BASED TRIANGLE ALIGNMENT ===")
  print("Analyzing main track rhythm and aligning triangle tracks...")
  print("")
  
  -- Sample rate for calculations
  local sample_rate = Session:nominal_sample_rate()
  
  -- Initialize VAMP plugins for rhythm analysis
  local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
  local onset_detector = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sample_rate)
  
  -- Configure plugins for optimal rhythm detection
  onset_detector:plugin():setParameter("dftype", 3)      -- Complex Domain
  onset_detector:plugin():setParameter("sensitivity", 45) -- Medium-high sensitivity
  onset_detector:plugin():setParameter("whiten", 0)       -- No whitening
  beat_tracker:plugin():setParameter("Beats Per Bar", 4)  -- Assume 4/4 time
  
  -- Find triangle tracks
  local triangle_400_track = nil
  local triangle_500_track = nil
  
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track:isnil() then
      local name = track:name():lower()
      if name:find("triangle%-400") or name:find("triangle_400") then
        triangle_400_track = track:to_audio_track()
        print("Found Triangle-400 track: " .. track:name())
      elseif name:find("triangle%-500") or name:find("triangle_500") then
        triangle_500_track = track:to_audio_track()
        print("Found Triangle-500 track: " .. track:name())
      end
    end
  end
  
  if not triangle_400_track and not triangle_500_track then
    print("ERROR: No triangle tracks found. Looking for tracks named 'triangle-400' or 'triangle-500'")
    return
  end
  
  -- Analyze the main track rhythm
  print("\n=== ANALYZING MAIN TRACK RHYTHM ===")
  
  local main_analysis = {
    beats = {},
    bars = {},
    onsets = {},
    tempo = nil,
    time_signature = nil,
    analysis_start = nil,
    analysis_end = nil
  }
  
  -- Process selected regions for rhythm analysis
  for r in sel.regions:regionlist():iter() do
    local ar = r:to_audioregion()
    if ar:isnil() then
      print("Skipping non-audio region: " .. r:name())
      goto next_region
    end
    
    print("Analyzing main track region: " .. r:name())
    
    -- Track analysis bounds
    local region_start = r:position():samples() / sample_rate
    local region_end = (r:position():samples() + r:length():samples()) / sample_rate
    
    if not main_analysis.analysis_start or region_start < main_analysis.analysis_start then
      main_analysis.analysis_start = region_start
    end
    if not main_analysis.analysis_end or region_end > main_analysis.analysis_end then
      main_analysis.analysis_end = region_end
    end
    
    -- Beat and bar analysis
    local beat_callback = function(feats)
      local beat_list = feats:table()[0]
      if beat_list then
        for f in beat_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate + region_start
            
            table.insert(main_analysis.beats, {
              time = time_seconds,
              frame = math.floor(time_seconds * sample_rate),
              beat_number = f.label or "unknown"
            })
          end
        end
      end
      
      local bar_list = feats:table()[1]
      if bar_list then
        for f in bar_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate + region_start
            
            table.insert(main_analysis.bars, {
              time = time_seconds,
              frame = math.floor(time_seconds * sample_rate)
            })
          end
        end
      end
      
      return false
    end
    
    -- Onset analysis
    local onset_callback = function(feats)
      local onset_list = feats:table()[0]
      if onset_list then
        for f in onset_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate + region_start
            
            table.insert(main_analysis.onsets, {
              time = time_seconds,
              frame = math.floor(time_seconds * sample_rate)
            })
          end
        end
      end
      return false
    end
    
    -- Run analysis
    beat_tracker:analyze(ar:to_readable(), 0, beat_callback)
    beat_callback(beat_tracker:plugin():getRemainingFeatures())
    beat_tracker:reset()
    
    onset_detector:analyze(ar:to_readable(), 0, onset_callback)
    onset_callback(onset_detector:plugin():getRemainingFeatures())
    onset_detector:reset()
    
    ::next_region::
  end
  
  -- Calculate tempo and rhythm characteristics
  if #main_analysis.beats > 1 then
    local beat_intervals = {}
    for i = 2, #main_analysis.beats do
      local interval = main_analysis.beats[i].time - main_analysis.beats[i-1].time
      table.insert(beat_intervals, interval)
    end
    
    if #beat_intervals > 0 then
      local avg_interval = 0
      for _, interval in ipairs(beat_intervals) do
        avg_interval = avg_interval + interval
      end
      avg_interval = avg_interval / #beat_intervals
      main_analysis.tempo = 60.0 / avg_interval
    end
  end
  
  print(string.format("Detected %d beats, %d bars, %d onsets", 
        #main_analysis.beats, #main_analysis.bars, #main_analysis.onsets))
  if main_analysis.tempo then
    print(string.format("Estimated tempo: %.2f BPM", main_analysis.tempo))
  end
  
  -- Helper function to find optimal triangle placement
  local function calculate_triangle_positions(beats, bars, track_name)
    local positions = {}
    
    if #beats < 2 then
      print("Warning: Not enough beats detected for " .. track_name)
      return positions
    end
    
    -- Different placement strategies for each triangle
    if track_name:find("400") then
      -- Triangle-400: Place on strong beats and syncopated positions
      print("Calculating Triangle-400 positions (strong beats + syncopation)...")
      
      for i, beat in ipairs(beats) do
        local beat_num = tonumber(beat.beat_number) or ((i - 1) % 4 + 1)
        
        -- Place on beats 1 and 3 (strong beats)
        if beat_num == 1 or beat_num == 3 then
          table.insert(positions, {
            time = beat.time,
            frame = beat.frame,
            type = "strong_beat",
            beat_number = beat_num
          })
        end
        
        -- Add syncopated positions (slightly before beat 2 and 4)
        if beat_num == 2 or beat_num == 4 then
          local syncopated_time = beat.time - 0.1 -- 100ms before beat
          if syncopated_time > (main_analysis.analysis_start or 0) then
            table.insert(positions, {
              time = syncopated_time,
              frame = math.floor(syncopated_time * sample_rate),
              type = "syncopation",
              beat_number = beat_num
            })
          end
        end
      end
      
    elseif track_name:find("500") then
      -- Triangle-500: Place on off-beats and complementary positions
      print("Calculating Triangle-500 positions (off-beats + complementary)...")
      
      for i = 1, #beats - 1 do
        local current_beat = beats[i]
        local next_beat = beats[i + 1]
        local beat_num = tonumber(current_beat.beat_number) or ((i - 1) % 4 + 1)
        
        -- Place on off-beats (between main beats)
        local off_beat_time = current_beat.time + (next_beat.time - current_beat.time) * 0.5
        table.insert(positions, {
          time = off_beat_time,
          frame = math.floor(off_beat_time * sample_rate),
          type = "off_beat",
          beat_number = beat_num
        })
        
        -- Add some positions on weak beats (2 and 4) for variety
        if beat_num == 2 or beat_num == 4 then
          table.insert(positions, {
            time = current_beat.time + 0.05, -- Slightly after the beat
            frame = math.floor((current_beat.time + 0.05) * sample_rate),
            type = "weak_beat",
            beat_number = beat_num
          })
        end
      end
    end
    
    -- Sort positions by time
    table.sort(positions, function(a, b) return a.time < b.time end)
    
    return positions
  end
  
  -- Helper function to move regions to new positions
  local function align_triangle_track(track, positions, track_name)
    if not track or #positions == 0 then
      return
    end
    
    print(string.format("\n=== ALIGNING %s ===", track_name:upper()))
    
    -- Begin reversible command for undo
    Session:begin_reversible_command("Align " .. track_name)
    
    local playlist = track:playlist()
    playlist:to_stateful():clear_changes()
    
    -- Get existing regions
    local existing_regions = {}
    for r in playlist:region_list():iter() do
      table.insert(existing_regions, r)
    end
    
    print(string.format("Found %d existing regions, creating %d new positions", 
          #existing_regions, #positions))
    
    -- Remove existing regions
    for _, region in ipairs(existing_regions) do
      playlist:remove_region(region)
    end
    
    -- Create new regions at calculated positions
    local region_index = 1
    for i, pos in ipairs(positions) do
      -- Cycle through available source regions
      local source_region = existing_regions[((region_index - 1) % #existing_regions) + 1]
      
      if source_region then
        -- Create a copy of the region
        local new_region = ARDOUR.RegionFactory.clone_region(source_region, true, true)
        
        if not new_region:isnil() then
          -- Position the region at the calculated time
          local new_position = Temporal.timepos_t(pos.frame)
          
          -- Add some velocity/gain variation based on position type
          local gain_factor = 1.0
          if pos.type == "strong_beat" then
            gain_factor = 1.0 -- Full volume for strong beats
          elseif pos.type == "syncopation" then
            gain_factor = 0.8 -- Slightly quieter for syncopation
          elseif pos.type == "off_beat" then
            gain_factor = 0.7 -- Quieter for off-beats
          elseif pos.type == "weak_beat" then
            gain_factor = 0.6 -- Quietest for weak beats
          end
          
          -- Add the region to the playlist
          playlist:add_region(new_region, new_position, gain_factor, false)
          
          print(string.format("  Placed region %d at %.3f sec (%s, gain %.1f)", 
                i, pos.time, pos.type, gain_factor))
          
          region_index = region_index + 1
        end
      end
      
      -- Limit total number of regions to prevent overcrowding
      if i >= 32 then -- Maximum 32 triangle hits
        print("  Limiting to 32 regions to prevent overcrowding")
        break
      end
    end
    
    -- Commit changes
    Session:add_stateful_diff_command(playlist:to_statefuldestructible())
    Session:commit_reversible_command(nil)
    
    print(string.format("Successfully aligned %s with %d regions", track_name, 
          math.min(#positions, 32)))
  end
  
  -- Calculate and apply triangle alignments
  if triangle_400_track then
    local triangle_400_positions = calculate_triangle_positions(main_analysis.beats, 
                                                               main_analysis.bars, 
                                                               "triangle-400")
    align_triangle_track(triangle_400_track, triangle_400_positions, "Triangle-400")
  end
  
  if triangle_500_track then
    local triangle_500_positions = calculate_triangle_positions(main_analysis.beats, 
                                                               main_analysis.bars, 
                                                               "triangle-500")
    align_triangle_track(triangle_500_track, triangle_500_positions, "Triangle-500")
  end
  
  -- Summary
  print("\n=== ALIGNMENT COMPLETE ===")
  print("Triangle tracks have been automatically aligned to complement the main rhythm:")
  
  if triangle_400_track then
    print("• Triangle-400: Positioned on strong beats (1, 3) with syncopated accents")
  end
  
  if triangle_500_track then
    print("• Triangle-500: Positioned on off-beats and weak beats for rhythmic interest")
  end
  
  print("\nThe alignment preserves the musical groove while adding complementary rhythmic elements.")
  print("You can further adjust individual regions manually if needed.")
  
  if main_analysis.tempo then
    print(string.format("\nMain track tempo: %.2f BPM", main_analysis.tempo))
  end
  
end end

-- Icon for the script
function icon(params) return function(ctx, width, height, fg)
  local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(width * .4) .. "px")
  txt:set_text("♪△♪")
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to(.5 * (width - tw), .5 * (height - th))
  txt:show_in_cairo_context(ctx)
end end 