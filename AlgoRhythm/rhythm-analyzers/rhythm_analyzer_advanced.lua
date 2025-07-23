ardour {
  ["type"] = "EditorAction",
  name = "Advanced Rhythm Analyzer with Export",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Advanced rhythm and beat analysis with data export capabilities.

Features:
- Comprehensive beat, bar, and onset detection
- Tempo estimation and rhythm pattern analysis
- Sample-accurate timing information
- Export results to JSON file for external processing
- Advanced rhythm classification (straight, swing, complex)
- Inter-onset interval analysis for groove detection

Select audio regions and run this script to get detailed rhythm analysis.
Results are both displayed in console and saved to a timestamped JSON file.
]]
}

function factory() return function()
  
  -- Get Editor selection
  local sel = Editor:get_selection()
  
  if sel.regions:regionlist():size() == 0 then
    print("ERROR: No regions selected. Please select one or more audio regions to analyze.")
    return
  end
  
  print("=== ADVANCED RHYTHM AND BEAT ANALYSIS ===")
  print("Analyzing " .. sel.regions:regionlist():size() .. " selected region(s)...")
  print("")
  
  -- Sample rate for calculations
  local sample_rate = Session:nominal_sample_rate()
  
  -- Initialize VAMP plugins for comprehensive analysis
  local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
  local onset_detector = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sample_rate)
  
  -- Configure onset detector for optimal rhythm detection
  onset_detector:plugin():setParameter("dftype", 3)      -- Complex Domain
  onset_detector:plugin():setParameter("sensitivity", 40) -- Slightly lower sensitivity for cleaner results
  onset_detector:plugin():setParameter("whiten", 0)       -- No whitening
  
  -- Configure beat tracker
  beat_tracker:plugin():setParameter("Beats Per Bar", 4) -- Start with 4/4 time
  
  -- Storage for comprehensive analysis results
  local analysis_results = {
    session_info = {
      sample_rate = sample_rate,
      analysis_timestamp = os.date("%Y-%m-%d %H:%M:%S"),
      ardour_version = "8.x", -- Could be detected if needed
      total_regions = sel.regions:regionlist():size()
    },
    regions = {}
  }
  
  -- Helper function to classify rhythm type
  local function classify_rhythm(onset_intervals, beat_intervals)
    if not onset_intervals or #onset_intervals < 4 then
      return "insufficient_data"
    end
    
    -- Calculate coefficient of variation for onset intervals
    local mean_interval = 0
    for _, interval in ipairs(onset_intervals) do
      mean_interval = mean_interval + interval
    end
    mean_interval = mean_interval / #onset_intervals
    
    local variance = 0
    for _, interval in ipairs(onset_intervals) do
      variance = variance + (interval - mean_interval) ^ 2
    end
    variance = variance / #onset_intervals
    local std_dev = math.sqrt(variance)
    local cv = std_dev / mean_interval
    
    -- Classify based on variability
    if cv < 0.15 then
      return "straight" -- Very regular timing
    elseif cv < 0.35 then
      return "slight_swing" -- Some timing variation
    elseif cv < 0.6 then
      return "swing" -- Clear swing feel
    else
      return "complex" -- Highly irregular or complex rhythm
    end
  end
  
  -- Helper function to detect time signature
  local function detect_time_signature(beats, bars)
    if #bars < 2 or #beats < 4 then
      return "unknown"
    end
    
    -- Calculate average beats per bar
    local total_beats_in_bars = 0
    local complete_bars = 0
    
    for i = 1, #bars - 1 do
      local bar_start = bars[i].relative_time
      local bar_end = bars[i + 1].relative_time
      local beats_in_bar = 0
      
      for _, beat in ipairs(beats) do
        if beat.relative_time >= bar_start and beat.relative_time < bar_end then
          beats_in_bar = beats_in_bar + 1
        end
      end
      
      if beats_in_bar > 0 then
        total_beats_in_bars = total_beats_in_bars + beats_in_bar
        complete_bars = complete_bars + 1
      end
    end
    
    if complete_bars > 0 then
      local avg_beats_per_bar = total_beats_in_bars / complete_bars
      
      if avg_beats_per_bar >= 3.5 and avg_beats_per_bar <= 4.5 then
        return "4/4"
      elseif avg_beats_per_bar >= 2.5 and avg_beats_per_bar <= 3.5 then
        return "3/4"
      elseif avg_beats_per_bar >= 1.5 and avg_beats_per_bar <= 2.5 then
        return "2/4"
      else
        return string.format("%.1f/4", avg_beats_per_bar)
      end
    end
    
    return "unknown"
  end
  
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
    
    -- Initialize comprehensive result storage for this region
    local region_results = {
      name = r:name(),
      position_samples = r:position():samples(),
      position_seconds = r:position():samples() / sample_rate,
      length_samples = r:length():samples(),
      length_seconds = r:length():samples() / sample_rate,
      beats = {},
      bars = {},
      onsets = {},
      analysis = {
        estimated_tempo = nil,
        time_signature = nil,
        rhythm_classification = nil,
        onset_density = nil,
        rhythmic_complexity = nil,
        groove_characteristics = {}
      }
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
    
    -- === ADVANCED RHYTHM ANALYSIS ===
    print("  Performing advanced rhythm analysis...")
    
    -- Calculate tempo from beats
    local beat_intervals = {}
    if #region_results.beats > 1 then
      for i = 2, #region_results.beats do
        local interval = region_results.beats[i].relative_time - region_results.beats[i-1].relative_time
        table.insert(beat_intervals, interval)
      end
      
      if #beat_intervals > 0 then
        local avg_interval = 0
        for _, interval in ipairs(beat_intervals) do
          avg_interval = avg_interval + interval
        end
        avg_interval = avg_interval / #beat_intervals
        
        local bpm = 60.0 / avg_interval
        region_results.analysis.estimated_tempo = bpm
        
        print("  Estimated tempo: " .. string.format("%.2f", bpm) .. " BPM")
      end
    end
    
    -- Detect time signature
    region_results.analysis.time_signature = detect_time_signature(region_results.beats, region_results.bars)
    print("  Detected time signature: " .. region_results.analysis.time_signature)
    
    -- Analyze onset patterns
    local onset_intervals = {}
    if #region_results.onsets > 1 then
      for i = 2, #region_results.onsets do
        local interval = region_results.onsets[i].relative_time - region_results.onsets[i-1].relative_time
        table.insert(onset_intervals, interval)
      end
      
      -- Calculate onset density
      local onset_density = #region_results.onsets / region_results.length_seconds
      region_results.analysis.onset_density = onset_density
      print("  Onset density: " .. string.format("%.2f", onset_density) .. " onsets per second")
      
      -- Classify rhythm type
      region_results.analysis.rhythm_classification = classify_rhythm(onset_intervals, beat_intervals)
      print("  Rhythm classification: " .. region_results.analysis.rhythm_classification)
      
      -- Calculate rhythmic complexity (entropy-like measure)
      local interval_histogram = {}
      for _, interval in ipairs(onset_intervals) do
        local bucket = math.floor(interval * 20) / 20 -- 0.05 second buckets
        interval_histogram[bucket] = (interval_histogram[bucket] or 0) + 1
      end
      
      local complexity = 0
      local total_intervals = #onset_intervals
      for _, count in pairs(interval_histogram) do
        local probability = count / total_intervals
        complexity = complexity - probability * math.log(probability)
      end
      region_results.analysis.rhythmic_complexity = complexity
      
      -- Store interval data for groove analysis
      region_results.analysis.groove_characteristics = {
        onset_intervals = onset_intervals,
        beat_intervals = beat_intervals,
        interval_histogram = interval_histogram
      }
    end
    
    -- Store results
    table.insert(analysis_results.regions, region_results)
    
    print("  Analysis complete!")
    print("")
    
    ::next_region::
  end
  
  -- === EXPORT RESULTS TO JSON ===
  local function table_to_json(t, indent)
    indent = indent or 0
    local spaces = string.rep("  ", indent)
    
    if type(t) ~= "table" then
      if type(t) == "string" then
        return '"' .. t .. '"'
      else
        return tostring(t)
      end
    end
    
    local result = "{\n"
    local first = true
    
    for k, v in pairs(t) do
      if not first then
        result = result .. ",\n"
      end
      first = false
      
      result = result .. spaces .. "  \"" .. tostring(k) .. "\": "
      
      if type(v) == "table" then
        if next(v) == nil then
          result = result .. "[]"
        elseif type(next(v)) == "number" then
          -- Array-like table
          result = result .. "[\n"
          local array_first = true
          for _, item in ipairs(v) do
            if not array_first then
              result = result .. ",\n"
            end
            array_first = false
            result = result .. spaces .. "    " .. table_to_json(item, indent + 2)
          end
          result = result .. "\n" .. spaces .. "  ]"
        else
          result = result .. table_to_json(v, indent + 1)
        end
      else
        result = result .. table_to_json(v, indent + 1)
      end
    end
    
    result = result .. "\n" .. spaces .. "}"
    return result
  end
  
  -- Generate filename with timestamp
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local filename = "rhythm_analysis_" .. timestamp .. ".json"
  
  -- Write JSON file
  local file = io.open(filename, "w")
  if file then
    file:write(table_to_json(analysis_results))
    file:close()
    print("Results exported to: " .. filename)
  else
    print("Warning: Could not write to file " .. filename)
  end
  
  -- === DETAILED CONSOLE OUTPUT ===
  print("\n=== DETAILED ANALYSIS RESULTS ===")
  print("")
  
  for _, results in ipairs(analysis_results.regions) do
    print("REGION: " .. results.name)
    print("----------------------------------------")
    
    -- Basic info
    print(string.format("Duration: %.3f seconds", results.length_seconds))
    print(string.format("Position: %.3f seconds", results.position_seconds))
    
    -- Analysis results
    if results.analysis.estimated_tempo then
      print(string.format("Tempo: %.2f BPM", results.analysis.estimated_tempo))
    end
    
    print("Time Signature: " .. results.analysis.time_signature)
    print("Rhythm Type: " .. (results.analysis.rhythm_classification or "unknown"))
    
    if results.analysis.onset_density then
      print(string.format("Onset Density: %.2f onsets/second", results.analysis.onset_density))
    end
    
    if results.analysis.rhythmic_complexity then
      print(string.format("Rhythmic Complexity: %.2f", results.analysis.rhythmic_complexity))
    end
    
    -- Beat and bar counts
    print(string.format("Beats Detected: %d", #results.beats))
    print(string.format("Bars Detected: %d", #results.bars))
    print(string.format("Onsets Detected: %d", #results.onsets))
    
    -- Sample timing data (first few beats)
    if #results.beats > 0 then
      print("\nFirst 5 beat positions:")
      for i = 1, math.min(5, #results.beats) do
        local beat = results.beats[i]
        print(string.format("  Beat %d: %.3f sec (frame %d)", 
              i, beat.relative_time, beat.relative_frame))
      end
    end
    
    print("")
    print("----------------------------------------")
    print("")
  end
  
  print("=== ANALYSIS COMPLETE ===")
  print("Data exported to JSON file: " .. filename)
  print("\nThis data can be used for:")
  print("- Tempo mapping and beat grid alignment")
  print("- Automatic quantization with groove preservation")
  print("- Beat-synchronized effects and processing")
  print("- Rhythm pattern matching and classification")
  print("- Groove template extraction")
  print("- Machine learning rhythm analysis")
  
end end

-- Icon for the script
function icon(params) return function(ctx, width, height, fg)
  local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(width * .5) .. "px")
  txt:set_text("♪♫♪")
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to(.5 * (width - tw), .5 * (height - th))
  txt:show_in_cairo_context(ctx)
end end 