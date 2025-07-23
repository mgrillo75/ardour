ardour {
  ["type"] = "EditorAction",
  name = "Advanced Drum Fill Remover",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Identifies and removes drum fills from a track using advanced audio analysis.

This script:
1. Analyzes onset density, beat patterns, and syncopation
2. Uses dynamic thresholds based on track characteristics
3. Combines multiple factors for robust fill detection
4. Removes fills and applies crossfades

Designed for complex drum patterns like funk.
]]
}

function factory() return function()
  
  -- Configuration parameters
  local config = {
    target_track_name = "ARP2600Funk",
    min_fill_duration = 0.2,         -- Minimum fill duration in seconds
    max_fill_duration = 4.0,         -- Maximum fill duration in seconds
    crossfade_duration = 0.02,       -- Crossfade duration in seconds
    analysis_window = 0.1,           -- Analysis window size in seconds
    onset_sensitivity = 65,          -- Onset detection sensitivity
    
    -- Advanced detection parameters
    density_percentile = 90,         -- Percentile for onset density threshold
    density_boost_factor = 1.2,      -- Multiplier for density threshold
    beat_deviation_threshold = 0.4,  -- Max deviation from main beat (0-1)
    syncopation_threshold = 0.6,     -- Syncopation level for fills (0-1)
    
    -- Weights for combined scoring (sum to 1.0)
    density_weight = 0.4,
    beat_deviation_weight = 0.3,
    syncopation_weight = 0.3,
    combined_score_threshold = 0.7   -- Min score to be considered a fill
  }
  
  print("=== ADVANCED DRUM FILL REMOVER ===")
  print("Target track: " .. config.target_track_name)
  print("")
  
  -- Find the target track (same as before)
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
    return
  end
  
  local playlist = target_track:playlist()
  local regions = {}
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
  
  local sample_rate = Session:nominal_sample_rate()
  local onset_detector = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sample_rate)
  local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
  
  onset_detector:plugin():setParameter("dftype", 4) 
  onset_detector:plugin():setParameter("sensitivity", config.onset_sensitivity)
  onset_detector:plugin():setParameter("whiten", 0)
  beat_tracker:plugin():setParameter("Beats Per Bar", 4)
  
  local analysis_results = {}
  
  for i, region_info in ipairs(regions) do
    print("Analyzing region " .. i .. ": " .. region_info.region:name())
    
    local region_analysis = {
      region_info = region_info,
      onsets = {},
      beats = {},
      analysis_windows = {},
      detected_fills = {}
    }
    
    -- Onset and Beat detection (same as before)
    local onset_callback = function(feats)
      local list = feats:table()[0]
      if list then for f in list:iter() do if f.hasTimestamp then 
        table.insert(region_analysis.onsets, {time = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate) / sample_rate})
      end end end
      return false
    end
    local beat_callback = function(feats)
      local list = feats:table()[0]
      if list then for f in list:iter() do if f.hasTimestamp then
        table.insert(region_analysis.beats, {time = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate) / sample_rate, label = f.label or ""})
      end end end
      return false
    end
    
    onset_detector:analyze(region_info.region:to_readable(), 0, onset_callback)
    onset_callback(onset_detector:plugin():getRemainingFeatures()); onset_detector:reset()
    beat_tracker:analyze(region_info.region:to_readable(), 0, beat_callback)
    beat_callback(beat_tracker:plugin():getRemainingFeatures()); beat_tracker:reset()
    
    print(string.format("  Found %d onsets and %d beats", #region_analysis.onsets, #region_analysis.beats))
    
    -- Advanced analysis in windows
    local window_size = config.analysis_window
    local step_size = window_size / 2 
    local num_windows = math.floor((region_info.length_seconds - window_size) / step_size) + 1
    
    local all_densities = {}
    for w = 0, num_windows - 1 do
      local win_start = w * step_size
      local win_end = win_start + window_size
      local data = { start_time = win_start, end_time = win_end, density = 0, beat_dev = 0, syncopation = 0, score = 0 }
      
      -- Onset density
      local onsets_in_window = 0
      for _, onset in ipairs(region_analysis.onsets) do
        if onset.time >= win_start and onset.time < win_end then onsets_in_window = onsets_in_window + 1 end
      end
      data.density = onsets_in_window / window_size
      table.insert(all_densities, data.density)
      
      -- Beat deviation and Syncopation
      local beats_in_window = {}
      for _, beat in ipairs(region_analysis.beats) do
        if beat.time >= win_start and beat.time < win_end then table.insert(beats_in_window, beat) end
      end
      
      if #beats_in_window > 1 then
        local intervals = {}
        for k = 1, #beats_in_window - 1 do table.insert(intervals, beats_in_window[k+1].time - beats_in_window[k].time) end
        
        -- Beat deviation (variance of intervals)
        local mean_interval = 0; for _, val in ipairs(intervals) do mean_interval = mean_interval + val end; mean_interval = mean_interval / #intervals
        local variance = 0; for _, val in ipairs(intervals) do variance = variance + (val - mean_interval)^2 end; variance = variance / #intervals
        data.beat_dev = math.sqrt(variance) / mean_interval -- Coefficient of variation
        
        -- Syncopation (count off-beats or complex beat labels)
        local syncopated_hits = 0
        for _, beat in ipairs(beats_in_window) do
          if string.find(beat.label, "off-beat") or string.find(beat.label, "syncopated") then syncopated_hits = syncopated_hits + 1 end
        end
        data.syncopation = syncopated_hits / #beats_in_window
      end
      table.insert(region_analysis.analysis_windows, data)
    end
    
    -- Calculate dynamic density threshold
    table.sort(all_densities)
    local density_thresh_val = 0
    if #all_densities > 0 then
      local idx = math.floor(#all_densities * (config.density_percentile / 100))
      if idx < 1 then idx = 1 elseif idx > #all_densities then idx = #all_densities end
      density_thresh_val = all_densities[idx] * config.density_boost_factor
    end
    print(string.format("  Dynamic density threshold: %.2f onsets/sec", density_thresh_val))
    
    -- Combine scores and detect fills
    local in_fill = false; local fill_start_time = 0
    local potential_fills_debug = {}
    
    for _, win_data in ipairs(region_analysis.analysis_windows) do
      -- Normalize scores (0-1 range)
      local density_score = math.min(1, win_data.density / (density_thresh_val * 1.5)) -- Cap at 1.5x threshold
      local beat_dev_score = math.min(1, win_data.beat_dev / (config.beat_deviation_threshold * 1.5))
      local sync_score = math.min(1, win_data.syncopation / (config.syncopation_threshold * 1.5))
      
      win_data.score = (density_score * config.density_weight) +
                       (beat_dev_score * config.beat_deviation_weight) +
                       (sync_score * config.syncopation_weight)
      
      if not in_fill and win_data.score >= config.combined_score_threshold then
        in_fill = true; fill_start_time = win_data.start_time
      elseif in_fill and win_data.score < config.combined_score_threshold then
        local duration = win_data.start_time - fill_start_time
        table.insert(potential_fills_debug, {s=fill_start_time, e=win_data.start_time, d=duration, sc=win_data.score})
        if duration >= config.min_fill_duration and duration <= config.max_fill_duration then
          table.insert(region_analysis.detected_fills, {
            start_time = fill_start_time, end_time = win_data.start_time, duration = duration,
            start_samples = region_info.start_samples + math.floor(fill_start_time * sample_rate),
            end_samples = region_info.start_samples + math.floor(win_data.start_time * sample_rate)
          })
          print(string.format("  Detected fill: %.2fs-%.2fs (%.2fs)", fill_start_time, win_data.start_time, duration))
        end
        in_fill = false
      end
    end
    
    -- Handle fill at end of region
    if in_fill then
      local duration = region_info.length_seconds - fill_start_time
      table.insert(potential_fills_debug, {s=fill_start_time, e=region_info.length_seconds, d=duration, sc=region_analysis.analysis_windows[#region_analysis.analysis_windows].score})
      if duration >= config.min_fill_duration and duration <= config.max_fill_duration then
        table.insert(region_analysis.detected_fills, {
          start_time = fill_start_time, end_time = region_info.length_seconds, duration = duration,
          start_samples = region_info.start_samples + math.floor(fill_start_time * sample_rate),
          end_samples = region_info.end_samples
        })
        print(string.format("  Detected fill (to end): %.2fs-%.2fs (%.2fs)", fill_start_time, region_info.length_seconds, duration))
      end
    end
    
    if #potential_fills_debug > 0 then
      print("  Potential fills (debug):")
      for _, pf in ipairs(potential_fills_debug) do
        print(string.format("    %.2fs-%.2fs (%.2fs) Score: %.2f %s", 
          pf.s, pf.e, pf.d, pf.sc, (pf.d >= config.min_fill_duration and pf.d <= config.max_fill_duration) and "" or "(rejected)"))
      end
    else
      print("  No sections met combined score threshold.")
    end
    
    table.insert(analysis_results, region_analysis)
    print("")
  end
  
  -- Removal and crossfading (similar to previous version, adapted for new structure)
  local total_fills = 0; for _, r_analysis in ipairs(analysis_results) do total_fills = total_fills + #r_analysis.detected_fills end
  if total_fills == 0 then print("No drum fills detected by advanced algorithm."); return end
  
  print("Total drum fills detected: " .. total_fills .. "\n")
  Session:begin_reversible_command("Remove Drum Fills (Advanced)")
  playlist:to_stateful():clear_changes()
  
  for _, r_analysis in ipairs(analysis_results) do
    if #r_analysis.detected_fills > 0 then
      print("Processing region: " .. r_analysis.region_info.region:name())
      table.sort(r_analysis.detected_fills, function(a,b) return a.start_time < b.start_time end)
      
      local last_split_end_samples = r_analysis.region_info.start_samples
      local new_playlist_regions = {}
      
      for i, fill in ipairs(r_analysis.detected_fills) do
        -- Add segment before the fill
        if fill.start_samples > last_split_end_samples then
          local pre_fill_region = ARDOUR.RegionFactory.create_audio_region(
            playlist, 
            r_analysis.region_info.region:sources():front(), 
            Temporal.timepos_t(last_split_end_samples),
            Temporal.timecnt_t(fill.start_samples - last_split_end_samples),
            Temporal.timepos_t(0) -- offset in source
          )
          if not pre_fill_region:isnil() then table.insert(new_playlist_regions, pre_fill_region) end
        end
        last_split_end_samples = fill.end_samples
      end
      
      -- Add segment after the last fill
      if last_split_end_samples < r_analysis.region_info.end_samples then
         local post_fill_region = ARDOUR.RegionFactory.create_audio_region(
            playlist, 
            r_analysis.region_info.region:sources():front(), 
            Temporal.timepos_t(last_split_end_samples),
            Temporal.timecnt_t(r_analysis.region_info.end_samples - last_split_end_samples),
            Temporal.timepos_t(0) -- offset in source
          )
        if not post_fill_region:isnil() then table.insert(new_playlist_regions, post_fill_region) end
      end
      
      -- Remove original region and add new ones
      playlist:remove_region(r_analysis.region_info.region)
      for _, new_rgn in ipairs(new_playlist_regions) do
        playlist:add_region(new_rgn, new_rgn:position(), 1, false, 0, 0, false)
      end
      print(string.format("  Replaced original region with %d segment(s)", #new_playlist_regions))
    end
  end
  
  -- Apply crossfades
  print("\nApplying crossfades...")
  local crossfade_samples = math.floor(config.crossfade_duration * sample_rate)
  local final_regions_list = {}
  for region in playlist:region_list():iter() do table.insert(final_regions_list, region) end
  table.sort(final_regions_list, function(a,b) return a:position():samples() < b:position():samples() end)
  
  for i = 1, #final_regions_list - 1 do
    local current_r = final_regions_list[i]
    local next_r = final_regions_list[i+1]
    local current_end_s = current_r:position():samples() + current_r:length():samples()
    local next_start_s = next_r:position():samples()
    local gap_s = next_start_s - current_end_s
    
    if gap_s == 0 then -- Only apply if regions are perfectly adjacent (after fill removal)
      current_r:set_fade_out_length(Temporal.timecnt_t(crossfade_samples))
      current_r:set_fade_out_shape(ARDOUR.FadeShape.Linear)
      next_r:set_fade_in_length(Temporal.timecnt_t(crossfade_samples))
      next_r:set_fade_in_shape(ARDOUR.FadeShape.Linear)
      
      -- Overlap the regions for the crossfade
      local overlap_pos = Temporal.timepos_t(current_end_s - crossfade_samples)
      next_r:set_position(overlap_pos)
      print(string.format("  Crossfaded regions around %.2fs", current_end_s / sample_rate))
    end
  end
  
  Session:add_stateful_diff_command(playlist:to_statefuldestructible())
  if not Session:abort_empty_reversible_command() then
    Session:commit_reversible_command(nil)
    print("\nAdvanced drum fill removal completed successfully!")
  else
    print("No changes made by advanced algorithm.")
  end
end end

function icon(params) return function(ctx, width, height, fg)
  ctx:set_line_width(2); ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  -- Icon representing complex analysis (e.g., a waveform with multiple highlighted sections)
  local s = width / 5
  ctx:move_to(0, height*0.5); ctx:line_to(s, height*0.2); ctx:line_to(s*2, height*0.8); ctx:line_to(s*3, height*0.3); ctx:line_to(s*4, height*0.7); ctx.line_to(s*5, height*0.5); ctx:stroke()
  ctx:set_source_rgba(1,0,0,0.5) -- Red for fills
  ctx:rectangle(s*1.2, height*0.1, s*0.6, height*0.8); ctx:fill()
  ctx:rectangle(s*3.5, height*0.1, s*0.5, height*0.8); ctx:fill()
end end 