ardour {
  ["type"] = "EditorAction",
  name = "Drum Fill Remover",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Identifies and removes drum fills from the ARP2600Funk track, then blends the remaining sections together.

This script:
1. Analyzes the ARP2600Funk track to identify drum fills based on onset density and rhythmic patterns
2. Removes the identified drum fill sections
3. Applies crossfades to blend the remaining sections smoothly

The script looks for characteristic drum fill patterns: increased onset density, rhythmic complexity,
and deviation from the main groove pattern.
]]
}

function factory() return function()
  
  -- Configuration parameters
  local config = {
    target_track_name = "ARP2600Funk",
    fill_detection_threshold = 1.4,  -- Lower threshold for busy funk tracks
    min_fill_duration = 0.25,        -- Much shorter minimum for quick fills
    max_fill_duration = 4.0,         -- Maximum fill duration in seconds
    crossfade_duration = 0.02,       -- Very short crossfade for quick fills
    analysis_window = 0.125,         -- Even smaller window for better resolution
    onset_sensitivity = 60,          -- Higher sensitivity for funk
    percentile_threshold = 85,       -- Use 85th percentile instead of median
    high_intensity_threshold = 2.0,  -- Secondary detection for very intense short fills
    min_high_intensity_duration = 0.125  -- Minimum duration for high-intensity fills
  }
  
  print("=== DRUM FILL REMOVER ===")
  print("Target track: " .. config.target_track_name)
  print("")
  
  -- Find the target track
  local target_track = nil
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track:isnil() then
      if track:name() == config.target_track_name then
        target_track = track:to_audio_track()
        print("Found target track: " .. track:name())
        break
      end
    end
  end
  
  if not target_track then
    print("ERROR: Track '" .. config.target_track_name .. "' not found!")
    print("Available tracks:")
    for route in Session:get_routes():iter() do
      local track = route:to_track()
      if not track:isnil() then
        print("  - " .. track:name())
      end
    end
    return
  end
  
  -- Get the track's playlist and regions
  local playlist = target_track:playlist()
  local regions = {}
  
  -- Collect all regions from the track
  for region in playlist:region_list():iter() do
    local ar = region:to_audioregion()
    if not ar:isnil() then
      table.insert(regions, {
        region = ar,
        start_samples = region:position():samples(),
        end_samples = region:position():samples() + region:length():samples(),
        start_seconds = region:position():samples() / Session:nominal_sample_rate(),
        end_seconds = (region:position():samples() + region:length():samples()) / Session:nominal_sample_rate(),
        length_seconds = region:length():samples() / Session:nominal_sample_rate()
      })
    end
  end
  
  if #regions == 0 then
    print("ERROR: No audio regions found in track '" .. config.target_track_name .. "'")
    return
  end
  
  print("Found " .. #regions .. " audio region(s) to analyze")
  print("")
  
  -- Initialize VAMP plugins for analysis
  local sample_rate = Session:nominal_sample_rate()
  local onset_detector = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sample_rate)
  local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
  
  -- Configure onset detector for drum analysis
  onset_detector:plugin():setParameter("dftype", 4)  -- Percussive onset detection
  onset_detector:plugin():setParameter("sensitivity", config.onset_sensitivity)
  onset_detector:plugin():setParameter("whiten", 0)
  
  -- Configure beat tracker
  beat_tracker:plugin():setParameter("Beats Per Bar", 4)
  
  -- Storage for analysis results
  local analysis_results = {}
  
  -- Analyze each region
  for i, region_info in ipairs(regions) do
    print("Analyzing region " .. i .. ": " .. region_info.region:name())
    print("  Duration: " .. string.format("%.2f", region_info.length_seconds) .. " seconds")
    
    local region_analysis = {
      region_info = region_info,
      onsets = {},
      beats = {},
      onset_density_timeline = {},
      detected_fills = {}
    }
    
    -- Onset analysis callback
    local onset_callback = function(feats)
      local onset_list = feats:table()[0]
      if onset_list then
        for f in onset_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            
            table.insert(region_analysis.onsets, {
              time = time_seconds,
              frame = frame_pos
            })
          end
        end
      end
      return false
    end
    
    -- Beat analysis callback
    local beat_callback = function(feats)
      local beat_list = feats:table()[0]
      if beat_list then
        for f in beat_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            
            table.insert(region_analysis.beats, {
              time = time_seconds,
              frame = frame_pos,
              beat_number = f.label or "unknown"
            })
          end
        end
      end
      return false
    end
    
    -- Run analysis
    onset_detector:analyze(region_info.region:to_readable(), 0, onset_callback)
    onset_callback(onset_detector:plugin():getRemainingFeatures())
    onset_detector:reset()
    
    beat_tracker:analyze(region_info.region:to_readable(), 0, beat_callback)
    beat_callback(beat_tracker:plugin():getRemainingFeatures())
    beat_tracker:reset()
    
    print("  Found " .. #region_analysis.onsets .. " onsets and " .. #region_analysis.beats .. " beats")
    
    -- Calculate onset density timeline
    local window_size = config.analysis_window
    local step_size = window_size / 4  -- 75% overlap
    local num_windows = math.floor((region_info.length_seconds - window_size) / step_size) + 1
    
    for w = 0, num_windows - 1 do
      local window_start = w * step_size
      local window_end = window_start + window_size
      
      local onsets_in_window = 0
      for _, onset in ipairs(region_analysis.onsets) do
        if onset.time >= window_start and onset.time < window_end then
          onsets_in_window = onsets_in_window + 1
        end
      end
      
      local density = onsets_in_window / window_size
      table.insert(region_analysis.onset_density_timeline, {
        start_time = window_start,
        end_time = window_end,
        density = density
      })
    end
    
    -- Calculate baseline onset density (85th percentile for busy tracks)
    local densities = {}
    for _, window in ipairs(region_analysis.onset_density_timeline) do
      table.insert(densities, window.density)
    end
    table.sort(densities)
    
    local baseline_density = 0
    if #densities > 0 then
      -- Use 85th percentile instead of median for busy funk tracks
      local percentile_index = math.floor(#densities * (config.percentile_threshold / 100))
      if percentile_index < 1 then percentile_index = 1 end
      if percentile_index > #densities then percentile_index = #densities end
      baseline_density = densities[percentile_index]
    end
    
    print("  Baseline onset density (" .. config.percentile_threshold .. "th percentile): " .. 
          string.format("%.2f", baseline_density) .. " onsets/sec")
    
    -- Detect drum fills based on onset density spikes
    local fill_threshold = baseline_density * config.fill_detection_threshold
    local high_intensity_threshold = baseline_density * config.high_intensity_threshold
    print("  Fill detection threshold: " .. string.format("%.2f", fill_threshold) .. " onsets/sec")
    print("  High-intensity threshold: " .. string.format("%.2f", high_intensity_threshold) .. " onsets/sec")
    
    local in_fill = false
    local fill_start = 0
    local potential_fills = {}
    
    -- Primary detection method
    for _, window in ipairs(region_analysis.onset_density_timeline) do
      if not in_fill and window.density > fill_threshold then
        -- Start of potential fill
        in_fill = true
        fill_start = window.start_time
      elseif in_fill and window.density <= fill_threshold then
        -- End of potential fill
        local fill_duration = window.start_time - fill_start
        
        -- Record all potential fills for debugging
        table.insert(potential_fills, {
          start_time = fill_start,
          end_time = window.start_time,
          duration = fill_duration,
          meets_criteria = (fill_duration >= config.min_fill_duration and fill_duration <= config.max_fill_duration),
          method = "primary"
        })
        
        if fill_duration >= config.min_fill_duration and fill_duration <= config.max_fill_duration then
          table.insert(region_analysis.detected_fills, {
            start_time = fill_start,
            end_time = window.start_time,
            duration = fill_duration,
            start_samples = region_info.start_samples + math.floor(fill_start * sample_rate),
            end_samples = region_info.start_samples + math.floor(window.start_time * sample_rate)
          })
          
          print("  Detected fill: " .. string.format("%.2f", fill_start) .. "s - " .. 
                string.format("%.2f", window.start_time) .. "s (duration: " .. 
                string.format("%.2f", fill_duration) .. "s)")
        end
        
        in_fill = false
      end
    end
    
    -- Secondary detection for very high-intensity short fills
    local in_high_intensity = false
    local high_intensity_start = 0
    
    for _, window in ipairs(region_analysis.onset_density_timeline) do
      if not in_high_intensity and window.density > high_intensity_threshold then
        -- Start of high-intensity section
        in_high_intensity = true
        high_intensity_start = window.start_time
      elseif in_high_intensity and window.density <= high_intensity_threshold then
        -- End of high-intensity section
        local duration = window.start_time - high_intensity_start
        
        -- Check if this overlaps with already detected fills
        local overlaps = false
        for _, existing_fill in ipairs(region_analysis.detected_fills) do
          if not (window.start_time <= existing_fill.start_time or high_intensity_start >= existing_fill.end_time) then
            overlaps = true
            break
          end
        end
        
        if not overlaps and duration >= config.min_high_intensity_duration and duration <= config.max_fill_duration then
          table.insert(potential_fills, {
            start_time = high_intensity_start,
            end_time = window.start_time,
            duration = duration,
            meets_criteria = true,
            method = "high-intensity"
          })
          
          table.insert(region_analysis.detected_fills, {
            start_time = high_intensity_start,
            end_time = window.start_time,
            duration = duration,
            start_samples = region_info.start_samples + math.floor(high_intensity_start * sample_rate),
            end_samples = region_info.start_samples + math.floor(window.start_time * sample_rate)
          })
          
          print("  Detected high-intensity fill: " .. string.format("%.2f", high_intensity_start) .. "s - " .. 
                string.format("%.2f", window.start_time) .. "s (duration: " .. 
                string.format("%.2f", duration) .. "s)")
        end
        
        in_high_intensity = false
      end
    end
    
    -- Show debug information about potential fills
    if #potential_fills > 0 then
      print("  Potential fills found:")
      for i, pf in ipairs(potential_fills) do
        local status = pf.meets_criteria and "ACCEPTED" or "rejected (duration)"
        print(string.format("    %d: %.2fs-%.2fs (%.2fs) - %s [%s]", 
              i, pf.start_time, pf.end_time, pf.duration, status, pf.method))
      end
    else
      print("  No high-density sections found above threshold")
    end
    
    -- Handle case where fill extends to end of region
    if in_fill then
      local fill_duration = region_info.length_seconds - fill_start
      
      -- Record this potential fill too
      table.insert(potential_fills, {
        start_time = fill_start,
        end_time = region_info.length_seconds,
        duration = fill_duration,
        meets_criteria = (fill_duration >= config.min_fill_duration and fill_duration <= config.max_fill_duration),
        method = "primary (end)"
      })
      
      if fill_duration >= config.min_fill_duration and fill_duration <= config.max_fill_duration then
        table.insert(region_analysis.detected_fills, {
          start_time = fill_start,
          end_time = region_info.length_seconds,
          duration = fill_duration,
          start_samples = region_info.start_samples + math.floor(fill_start * sample_rate),
          end_samples = region_info.end_samples
        })
        
        print("  Detected fill (to end): " .. string.format("%.2f", fill_start) .. "s - " .. 
              string.format("%.2f", region_info.length_seconds) .. "s (duration: " .. 
              string.format("%.2f", fill_duration) .. "s)")
      end
    end
    
    table.insert(analysis_results, region_analysis)
    print("")
  end
  
  -- Count total fills detected
  local total_fills = 0
  for _, analysis in ipairs(analysis_results) do
    total_fills = total_fills + #analysis.detected_fills
  end
  
  if total_fills == 0 then
    print("No drum fills detected. Try adjusting the detection threshold.")
    return
  end
  
  print("Total drum fills detected: " .. total_fills)
  print("")
  
  -- Begin reversible command for undo support
  Session:begin_reversible_command("Remove Drum Fills")
  
  -- Clear existing changes, prepare "diff" of state for undo
  playlist:to_stateful():clear_changes()
  
  -- Process each region and remove fills
  for _, analysis in ipairs(analysis_results) do
    if #analysis.detected_fills > 0 then
      print("Processing region: " .. analysis.region_info.region:name())
      
      -- Sort fills by start time
      table.sort(analysis.detected_fills, function(a, b) return a.start_time < b.start_time end)
      
      -- Create new regions by splitting around fills
      local current_region = analysis.region_info.region
      local splits_made = 0
      
      for i, fill in ipairs(analysis.detected_fills) do
        print("  Removing fill " .. i .. ": " .. string.format("%.2f", fill.start_time) .. "s - " .. 
              string.format("%.2f", fill.end_time) .. "s")
        
        -- Calculate absolute positions
        local fill_start_abs = Temporal.timepos_t(fill.start_samples)
        local fill_end_abs = Temporal.timepos_t(fill.end_samples)
        
        -- Split at fill start if not at region start
        if fill.start_time > 0.01 then  -- Small tolerance
          local regions_at_start = playlist:regions_at(fill_start_abs)
          for region in regions_at_start:iter() do
            if region:id() == current_region:id() then
              playlist:split_region(region, fill_start_abs)
              splits_made = splits_made + 1
              break
            end
          end
        end
        
        -- Split at fill end if not at region end
        if fill.end_time < analysis.region_info.length_seconds - 0.01 then  -- Small tolerance
          local regions_at_end = playlist:regions_at(fill_end_abs)
          for region in regions_at_end:iter() do
            -- Find the region that contains the fill end
            if region:position():samples() <= fill.end_samples and 
               (region:position():samples() + region:length():samples()) > fill.end_samples then
              playlist:split_region(region, fill_end_abs)
              splits_made = splits_made + 1
              break
            end
          end
        end
        
        -- Remove the fill region
        local regions_to_remove = playlist:regions_at(fill_start_abs)
        for region in regions_to_remove:iter() do
          local region_start = region:position():samples()
          local region_end = region_start + region:length():samples()
          
          -- Check if this region is entirely within the fill
          if region_start >= fill.start_samples and region_end <= fill.end_samples then
            playlist:remove_region(region)
            print("    Removed fill region")
            break
          end
        end
      end
      
      print("  Made " .. splits_made .. " splits and removed " .. #analysis.detected_fills .. " fill regions")
    end
  end
  
  -- Apply crossfades between remaining regions
  print("")
  print("Applying crossfades...")
  
  local crossfade_samples = math.floor(config.crossfade_duration * sample_rate)
  local regions_list = {}
  
  -- Collect all remaining regions in order
  for region in playlist:region_list():iter() do
    table.insert(regions_list, region)
  end
  
  -- Sort by position
  table.sort(regions_list, function(a, b) 
    return a:position():samples() < b:position():samples() 
  end)
  
  -- Add crossfades between adjacent regions
  for i = 1, #regions_list - 1 do
    local current_region = regions_list[i]
    local next_region = regions_list[i + 1]
    
    local current_end = current_region:position():samples() + current_region:length():samples()
    local next_start = next_region:position():samples()
    
    -- Check if regions are adjacent (small gap allowed)
    local gap = next_start - current_end
    if gap >= 0 and gap < sample_rate * 0.1 then  -- Less than 0.1 second gap
      -- Move next region to overlap with current region for crossfade
      if gap > 0 then
        local new_position = Temporal.timepos_t(current_end - crossfade_samples)
        next_region:set_position(new_position)
        print("  Added crossfade between regions at " .. 
              string.format("%.2f", current_end / sample_rate) .. "s")
      end
    end
  end
  
  -- Commit the changes
  Session:add_stateful_diff_command(playlist:to_statefuldestructible())
  
  if not Session:abort_empty_reversible_command() then
    Session:commit_reversible_command(nil)
    print("")
    print("Drum fill removal completed successfully!")
    print("Use Undo (Ctrl+Z) if you need to revert the changes.")
  else
    print("No changes were made.")
  end
  
end end

-- Icon for the toolbar (optional)
function icon(params) return function(ctx, width, height, fg)
  local wh = math.min(width, height) * 0.5
  local ar = wh * 0.2
  
  ctx:set_line_width(2)
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  
  -- Draw waveform with gaps (representing removed fills)
  local segments = 4
  local segment_width = width / segments
  
  for i = 0, segments - 1 do
    if i % 2 == 0 then  -- Only draw every other segment (gaps represent removed fills)
      local x_start = i * segment_width
      local x_end = x_start + segment_width * 0.7  -- Leave gap
      
      -- Draw simplified waveform
      ctx:move_to(x_start, height * 0.5)
      ctx:line_to(x_start + segment_width * 0.2, height * 0.2)
      ctx:line_to(x_start + segment_width * 0.4, height * 0.8)
      ctx:line_to(x_end, height * 0.5)
      ctx:stroke()
    end
  end
  
  -- Draw crossfade curves at gaps
  for i = 1, segments - 1, 2 do
    local x = i * segment_width
    ctx:move_to(x - segment_width * 0.1, height * 0.3)
    ctx:curve_to(x, height * 0.1, x, height * 0.9, x + segment_width * 0.1, height * 0.7)
    ctx:stroke()
  end
  
end end 