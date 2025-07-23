ardour {
  ["type"] = "EditorAction",
  name = "Rhythm and Beat Analyzer",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Analyze selected audio regions to identify rhythm patterns, beats, and their precise timeseries placements.

This script uses multiple VAMP plugins to perform comprehensive rhythm analysis:
- Beat detection and tempo estimation
- Onset detection for rhythmic events
- Bar/measure detection
- Detailed timing analysis with sample-accurate positions

Results are printed to the console and can be used for further processing.
]]
}

function factory() return function()
  
  -- Get Editor selection
  local sel = Editor:get_selection()
  
  if sel.regions:regionlist():size() == 0 then
    print("ERROR: No regions selected. Please select one or more audio regions to analyze.")
    return
  end
  
  print("=== RHYTHM AND BEAT ANALYSIS ===")
  print("Analyzing " .. sel.regions:regionlist():size() .. " selected region(s)...")
  print("")
  
  -- Sample rate for calculations
  local sample_rate = Session:nominal_sample_rate()
  
  -- Initialize VAMP plugins for different types of analysis
  local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
  local onset_detector = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sample_rate)
  
  -- Configure onset detector for better rhythm detection
  onset_detector:plugin():setParameter("dftype", 3)      -- Complex Domain
  onset_detector:plugin():setParameter("sensitivity", 50) -- Medium sensitivity
  onset_detector:plugin():setParameter("whiten", 0)       -- No whitening
  
  -- Configure beat tracker
  beat_tracker:plugin():setParameter("Beats Per Bar", 4) -- Assume 4/4 time initially
  
  -- Storage for analysis results
  local analysis_results = {}
  
  -- Process each selected region
  for r in sel.regions:regionlist():iter() do
    local ar = r:to_audioregion()
    if ar:isnil() then
      print("Skipping non-audio region: " .. r:name())
      goto next_region
    end
    
    print("Analyzing region: " .. r:name())
    print("  Position: " .. r:position():samples() .. " samples (" .. 
          string.format("%.3f", r:position():samples() / sample_rate) .. " seconds)")
    print("  Length: " .. r:length():samples() .. " samples (" .. 
          string.format("%.3f", r:length():samples() / sample_rate) .. " seconds)")
    
    -- Initialize result storage for this region
    local region_results = {
      name = r:name(),
      position_samples = r:position():samples(),
      position_seconds = r:position():samples() / sample_rate,
      length_samples = r:length():samples(),
      length_seconds = r:length():samples() / sample_rate,
      beats = {},
      bars = {},
      onsets = {},
      tempo_estimates = {},
      rhythm_analysis = {}
    }
    
    -- === BEAT AND BAR ANALYSIS ===
    print("  Performing beat and bar analysis...")
    
    local beat_callback = function(feats)
      -- Get beat locations (output 0)
      local beat_list = feats:table()[0]
      if beat_list then
        for f in beat_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            local absolute_time = region_results.position_seconds + time_seconds
            
            table.insert(region_results.beats, {
              relative_frame = frame_pos,
              relative_time = time_seconds,
              absolute_time = absolute_time,
              beat_number = f.label or "unknown"
            })
          end
        end
      end
      
      -- Get bar locations (output 1)
      local bar_list = feats:table()[1]
      if bar_list then
        for f in bar_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            local absolute_time = region_results.position_seconds + time_seconds
            
            table.insert(region_results.bars, {
              relative_frame = frame_pos,
              relative_time = time_seconds,
              absolute_time = absolute_time
            })
          end
        end
      end
      
      return false -- continue analysis
    end
    
    -- Run beat analysis
    beat_tracker:analyze(ar:to_readable(), 0, beat_callback)
    beat_callback(beat_tracker:plugin():getRemainingFeatures())
    beat_tracker:reset()
    
    -- === ONSET ANALYSIS ===
    print("  Performing onset analysis...")
    
    local onset_callback = function(feats)
      local onset_list = feats:table()[0]
      if onset_list then
        for f in onset_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            local absolute_time = region_results.position_seconds + time_seconds
            
            table.insert(region_results.onsets, {
              relative_frame = frame_pos,
              relative_time = time_seconds,
              absolute_time = absolute_time
            })
          end
        end
      end
      return false
    end
    
    -- Run onset analysis
    onset_detector:analyze(ar:to_readable(), 0, onset_callback)
    onset_callback(onset_detector:plugin():getRemainingFeatures())
    onset_detector:reset()
    
    -- === RHYTHM PATTERN ANALYSIS ===
    print("  Analyzing rhythm patterns...")
    
    -- Calculate tempo from beats
    if #region_results.beats > 1 then
      local beat_intervals = {}
      for i = 2, #region_results.beats do
        local interval = region_results.beats[i].relative_time - region_results.beats[i-1].relative_time
        table.insert(beat_intervals, interval)
      end
      
      -- Calculate average tempo
      if #beat_intervals > 0 then
        local avg_interval = 0
        for _, interval in ipairs(beat_intervals) do
          avg_interval = avg_interval + interval
        end
        avg_interval = avg_interval / #beat_intervals
        
        local bpm = 60.0 / avg_interval
        region_results.estimated_tempo = bpm
        
        print("  Estimated tempo: " .. string.format("%.2f", bpm) .. " BPM")
      end
    end
    
    -- Analyze onset density and patterns
    if #region_results.onsets > 0 then
      local onset_density = #region_results.onsets / region_results.length_seconds
      region_results.onset_density = onset_density
      print("  Onset density: " .. string.format("%.2f", onset_density) .. " onsets per second")
      
      -- Calculate inter-onset intervals for rhythm pattern analysis
      local onset_intervals = {}
      for i = 2, #region_results.onsets do
        local interval = region_results.onsets[i].relative_time - region_results.onsets[i-1].relative_time
        table.insert(onset_intervals, interval)
      end
      
      region_results.onset_intervals = onset_intervals
    end
    
    -- Store results
    analysis_results[r:name()] = region_results
    
    print("  Analysis complete!")
    print("")
    
    ::next_region::
  end
  
  -- === DETAILED RESULTS OUTPUT ===
  print("=== DETAILED ANALYSIS RESULTS ===")
  print("")
  
  for region_name, results in pairs(analysis_results) do
    print("REGION: " .. region_name)
    print("----------------------------------------")
    
    -- Beat information
    print("BEATS DETECTED: " .. #results.beats)
    if #results.beats > 0 then
      print("Beat positions (time in seconds):")
      for i, beat in ipairs(results.beats) do
        print(string.format("  Beat %d: %.3f sec (absolute: %.3f sec) - %s", 
              i, beat.relative_time, beat.absolute_time, beat.beat_number))
      end
    end
    print("")
    
    -- Bar information
    print("BARS DETECTED: " .. #results.bars)
    if #results.bars > 0 then
      print("Bar positions (time in seconds):")
      for i, bar in ipairs(results.bars) do
        print(string.format("  Bar %d: %.3f sec (absolute: %.3f sec)", 
              i, bar.relative_time, bar.absolute_time))
      end
    end
    print("")
    
    -- Onset information
    print("ONSETS DETECTED: " .. #results.onsets)
    if #results.onsets > 0 then
      print("First 10 onset positions (time in seconds):")
      for i = 1, math.min(10, #results.onsets) do
        local onset = results.onsets[i]
        print(string.format("  Onset %d: %.3f sec (absolute: %.3f sec)", 
              i, onset.relative_time, onset.absolute_time))
      end
      if #results.onsets > 10 then
        print("  ... and " .. (#results.onsets - 10) .. " more onsets")
      end
    end
    print("")
    
    -- Tempo and rhythm analysis
    if results.estimated_tempo then
      print("ESTIMATED TEMPO: " .. string.format("%.2f", results.estimated_tempo) .. " BPM")
    end
    
    if results.onset_density then
      print("ONSET DENSITY: " .. string.format("%.2f", results.onset_density) .. " onsets/second")
    end
    
    -- Rhythm pattern suggestions
    if results.onset_intervals and #results.onset_intervals > 0 then
      print("RHYTHM PATTERN ANALYSIS:")
      
      -- Find most common interval ranges
      local interval_histogram = {}
      for _, interval in ipairs(results.onset_intervals) do
        local bucket = math.floor(interval * 10) / 10 -- Round to 0.1 second buckets
        interval_histogram[bucket] = (interval_histogram[bucket] or 0) + 1
      end
      
      -- Find dominant intervals
      local sorted_intervals = {}
      for interval, count in pairs(interval_histogram) do
        table.insert(sorted_intervals, {interval = interval, count = count})
      end
      
      table.sort(sorted_intervals, function(a, b) return a.count > b.count end)
      
      print("  Most common inter-onset intervals:")
      for i = 1, math.min(5, #sorted_intervals) do
        local item = sorted_intervals[i]
        print(string.format("    %.1f sec: %d occurrences", item.interval, item.count))
      end
    end
    
    print("")
    print("----------------------------------------")
    print("")
  end
  
  print("=== ANALYSIS COMPLETE ===")
  print("Results can be used for:")
  print("- Tempo mapping")
  print("- Rhythm quantization")
  print("- Beat-synchronized effects")
  print("- Automatic region slicing")
  print("- Groove template creation")
  
end end

-- Optional: Add an icon for the script
function icon(params) return function(ctx, width, height, fg)
  local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(width * .6) .. "px")
  txt:set_text("♪♫")
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to(.5 * (width - tw), .5 * (height - th))
  txt:show_in_cairo_context(ctx)
end end 