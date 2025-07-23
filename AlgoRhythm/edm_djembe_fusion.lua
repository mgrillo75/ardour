ardour {
  ["type"] = "EditorAction",
  name = "EDM-Djembe Fusion Analyzer",
  author = "Assistant",
  description = [[
    Analyzes EDM track structure and finds compatible djembe clips.
    Outputs recommendations for manual placement.
  ]]
}

function factory() return function()
  -- Configuration
  local config = {
    edm_track_pattern = "vallehouse",
    djembe_track_pattern = "djembe",
    clip_duration_min = 10.0,  -- seconds
    clip_duration_max = 20.0,  -- seconds
    num_clips_to_find = 3,
    tempo_tolerance = 5.0      -- BPM tolerance
  }
  
  -- Find tracks
  local edm_track = nil
  local djembe_tracks = {}
  
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track:isnil() then
      local audio_track = track:to_audio_track()
      if not audio_track:isnil() then
        local track_name = track:name():lower()
        
        if track_name:find(config.edm_track_pattern) then
          edm_track = {
            track = audio_track,
            name = track:name()
          }
        elseif track_name:find(config.djembe_track_pattern) and not track_name:find("fusion") then
          -- Exclude any fusion tracks from previous runs
          table.insert(djembe_tracks, {
            track = audio_track,
            name = track:name()
          })
        end
      end
    end
  end
  
  -- Validate we have the necessary tracks
  if not edm_track then
    print("ERROR: No EDM track found matching pattern: " .. config.edm_track_pattern)
    return
  end
  
  if #djembe_tracks == 0 then
    print("ERROR: No djembe tracks found matching pattern: " .. config.djembe_track_pattern)
    return
  end
  
  print("=== EDM-DJEMBE FUSION ANALYZER ===")
  print("Analyzing EDM structure and finding compatible djembe patterns...")
  print("")
  print("EDM Track: " .. edm_track.name)
  print("Djembe Tracks: " .. #djembe_tracks .. " found")
  for _, dt in ipairs(djembe_tracks) do
    print("  - " .. dt.name)
  end
  print("")
  
  -- Initialize analysis tools
  local sample_rate = Session:nominal_sample_rate()
  local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
  local onset_detector = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sample_rate)
  
  -- Configure for EDM and percussion analysis
  onset_detector:plugin():setParameter("dftype", 3)      -- Complex Domain
  onset_detector:plugin():setParameter("sensitivity", 40) -- Good for percussion
  onset_detector:plugin():setParameter("whiten", 0)       -- No whitening
  beat_tracker:plugin():setParameter("Beats Per Bar", 4)  -- 4/4 time for house music
  
  -- Helper function to analyze audio region
  local function analyze_region(region, region_name)
    local analysis = {
      beats = {},
      bars = {},
      onsets = {},
      tempo = nil,
      energy_profile = {},
      rhythmic_density = 0,
      start_time = region:position():samples() / sample_rate,
      end_time = (region:position():samples() + region:length():samples()) / sample_rate,
      length = region:length():samples() / sample_rate
    }
    
    print("  Analyzing: " .. region_name)
    
    -- Beat and bar detection
    local beat_callback = function(feats)
      local beat_list = feats:table()[0]
      if beat_list then
        for f in beat_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            table.insert(analysis.beats, {
              time = time_seconds,
              absolute_time = analysis.start_time + time_seconds
            })
          end
        end
      end
      
      local bar_list = feats:table()[1]
      if bar_list then
        for f in bar_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            table.insert(analysis.bars, {
              time = time_seconds,
              absolute_time = analysis.start_time + time_seconds
            })
          end
        end
      end
      return false
    end
    
    -- Onset detection for energy analysis
    local onset_callback = function(feats)
      local onset_list = feats:table()[0]
      if onset_list then
        for f in onset_list:iter() do
          if f.hasTimestamp then
            local frame_pos = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
            local time_seconds = frame_pos / sample_rate
            table.insert(analysis.onsets, {
              time = time_seconds,
              absolute_time = analysis.start_time + time_seconds
            })
          end
        end
      end
      return false
    end
    
    -- Run analysis
    local ar = region:to_audioregion()
    if not ar:isnil() then
      beat_tracker:analyze(ar:to_readable(), 0, beat_callback)
      beat_callback(beat_tracker:plugin():getRemainingFeatures())
      beat_tracker:reset()
      
      onset_detector:analyze(ar:to_readable(), 0, onset_callback)
      onset_callback(onset_detector:plugin():getRemainingFeatures())
      onset_detector:reset()
    end
    
    -- Calculate tempo
    if #analysis.beats > 1 then
      local intervals = {}
      for i = 2, #analysis.beats do
        table.insert(intervals, analysis.beats[i].time - analysis.beats[i-1].time)
      end
      if #intervals > 0 then
        local avg_interval = 0
        for _, interval in ipairs(intervals) do
          avg_interval = avg_interval + interval
        end
        avg_interval = avg_interval / #intervals
        analysis.tempo = 60.0 / avg_interval
      end
    end
    
    -- Calculate rhythmic density
    if analysis.length > 0 then
      analysis.rhythmic_density = #analysis.onsets / analysis.length
    end
    
    -- Calculate energy profile (onset density over time windows)
    local window_size = 4.0 -- 4 second windows
    local num_windows = math.ceil(analysis.length / window_size)
    
    for w = 1, num_windows do
      local window_start = (w - 1) * window_size
      local window_end = math.min(w * window_size, analysis.length)
      local onsets_in_window = 0
      
      for _, onset in ipairs(analysis.onsets) do
        if onset.time >= window_start and onset.time < window_end then
          onsets_in_window = onsets_in_window + 1
        end
      end
      
      local window_density = onsets_in_window / (window_end - window_start)
      table.insert(analysis.energy_profile, {
        start = window_start,
        end_time = window_end,
        density = window_density,
        normalized_energy = 0 -- Will be calculated later
      })
    end
    
    -- Normalize energy profile
    local max_density = 0
    for _, window in ipairs(analysis.energy_profile) do
      if window.density > max_density then
        max_density = window.density
      end
    end
    
    if max_density > 0 then
      for _, window in ipairs(analysis.energy_profile) do
        window.normalized_energy = window.density / max_density
      end
    end
    
    return analysis
  end
  
  -- STEP 1: Analyze EDM track structure
  print("=== ANALYZING EDM TRACK STRUCTURE ===")
  
  local edm_analysis = {
    regions = {},
    sections = {},
    global_tempo = nil
  }
  
  -- Analyze all regions in EDM track
  local playlist = edm_track.track:playlist()
  if not playlist then
    print("ERROR: Could not access playlist for EDM track")
    return
  end
  
  for region in playlist:region_list():iter() do
    local region_analysis = analyze_region(region, region:name())
    region_analysis.region = region
    table.insert(edm_analysis.regions, region_analysis)
    
    -- Update global tempo (use most common)
    if region_analysis.tempo then
      edm_analysis.global_tempo = region_analysis.tempo -- Simple approach, could be improved
    end
  end
  
  -- Identify sections based on energy patterns
  print("\n=== IDENTIFYING EDM SECTIONS ===")
  
  local function identify_sections(regions)
    local sections = {}
    
    for _, region in ipairs(regions) do
      -- Analyze energy pattern to guess section type
      local avg_energy = 0
      local energy_variance = 0
      
      for _, window in ipairs(region.energy_profile) do
        avg_energy = avg_energy + window.normalized_energy
      end
      avg_energy = avg_energy / #region.energy_profile
      
      for _, window in ipairs(region.energy_profile) do
        energy_variance = energy_variance + (window.normalized_energy - avg_energy) ^ 2
      end
      energy_variance = energy_variance / #region.energy_profile
      
      -- Classify section based on energy characteristics
      local section_type = "unknown"
      if avg_energy < 0.3 then
        section_type = "intro/outro"
      elseif avg_energy < 0.6 and energy_variance < 0.1 then
        section_type = "verse"
      elseif avg_energy > 0.7 then
        section_type = "drop/chorus"
      elseif energy_variance > 0.2 then
        section_type = "buildup/bridge"
      else
        section_type = "breakdown"
      end
      
      table.insert(sections, {
        region = region,
        type = section_type,
        avg_energy = avg_energy,
        energy_variance = energy_variance,
        start_time = region.start_time,
        end_time = region.end_time,
        tempo = region.tempo
      })
      
      print(string.format("  Section: %s - Type: %s (energy: %.2f, variance: %.2f)",
            region.region:name(), section_type, avg_energy, energy_variance))
    end
    
    return sections
  end
  
  edm_analysis.sections = identify_sections(edm_analysis.regions)
  
  -- Find best section for djembe (prefer verse or breakdown)
  local target_section = nil
  local section_priority = {
    ["verse"] = 1,
    ["breakdown"] = 2,
    ["intro/outro"] = 3,
    ["buildup/bridge"] = 4,
    ["drop/chorus"] = 5
  }
  
  local best_priority = 999
  for _, section in ipairs(edm_analysis.sections) do
    local priority = section_priority[section.type] or 999
    if priority < best_priority then
      best_priority = priority
      target_section = section
    end
  end
  
  if not target_section then
    print("ERROR: Could not identify suitable EDM section")
    return
  end
  
  print(string.format("\nSelected target section: %s (%s) at %.1f-%.1f seconds",
        target_section.region.region:name(), target_section.type,
        target_section.start_time, target_section.end_time))
  print(string.format("Target tempo: %.1f BPM", target_section.tempo or edm_analysis.global_tempo or 120))
  
  -- STEP 2: Analyze djembe tracks
  print("\n=== ANALYZING DJEMBE TRACKS ===")
  
  local djembe_clips = {}
  
  for _, djembe_track_info in ipairs(djembe_tracks) do
    print("\nAnalyzing djembe track: " .. djembe_track_info.name)
    
    local playlist = djembe_track_info.track:playlist()
    if playlist then
      for region in playlist:region_list():iter() do
        local region_analysis = analyze_region(region, region:name())
        
        -- Find suitable clips within this region
        local region_length = region_analysis.length
        
        -- If region is already in the target duration range, consider the whole thing
        if region_length >= config.clip_duration_min and region_length <= config.clip_duration_max then
          table.insert(djembe_clips, {
            track = djembe_track_info,
            region = region,
            analysis = region_analysis,
            start_offset = 0,
            duration = region_length,
            compatibility_score = 0 -- Will be calculated
          })
        else
          -- Look for good segments within longer regions
          local segment_start = 0
          while segment_start + config.clip_duration_min <= region_length do
            local segment_duration = math.min(config.clip_duration_max, region_length - segment_start)
            
            -- Analyze segment energy
            local segment_energy = 0
            local onset_count = 0
            
            for _, onset in ipairs(region_analysis.onsets) do
              if onset.time >= segment_start and onset.time < segment_start + segment_duration then
                onset_count = onset_count + 1
              end
            end
            
            segment_energy = onset_count / segment_duration
            
            -- Only consider segments with reasonable energy
            if segment_energy > 2.0 then -- At least 2 onsets per second
              table.insert(djembe_clips, {
                track = djembe_track_info,
                region = region,
                analysis = region_analysis,
                start_offset = segment_start,
                duration = math.min(segment_duration, config.clip_duration_max),
                segment_energy = segment_energy,
                compatibility_score = 0
              })
            end
            
            segment_start = segment_start + 5.0 -- Move in 5 second increments
          end
        end
      end
    else
      print("  WARNING: Could not access playlist for track: " .. djembe_track_info.name)
    end
  end
  
  print(string.format("\nFound %d potential djembe clips", #djembe_clips))
  
  -- STEP 3: Calculate compatibility scores
  print("\n=== CALCULATING COMPATIBILITY SCORES ===")
  
  local target_tempo = target_section.tempo or edm_analysis.global_tempo or 120
  
  for _, clip in ipairs(djembe_clips) do
    local score = 0
    
    -- Tempo compatibility (most important)
    if clip.analysis.tempo then
      local tempo_diff = math.abs(clip.analysis.tempo - target_tempo)
      if tempo_diff <= config.tempo_tolerance then
        score = score + 40 * (1 - tempo_diff / config.tempo_tolerance)
      elseif tempo_diff <= config.tempo_tolerance * 2 then
        -- Check for half/double time compatibility
        local half_diff = math.abs(clip.analysis.tempo / 2 - target_tempo)
        local double_diff = math.abs(clip.analysis.tempo * 2 - target_tempo)
        
        if half_diff <= config.tempo_tolerance then
          score = score + 30 * (1 - half_diff / config.tempo_tolerance)
        elseif double_diff <= config.tempo_tolerance then
          score = score + 30 * (1 - double_diff / config.tempo_tolerance)
        end
      end
    end
    
    -- Energy compatibility
    local target_energy = target_section.avg_energy
    local clip_energy = clip.segment_energy or (clip.analysis.rhythmic_density / 10) -- Normalize
    local energy_diff = math.abs(clip_energy - target_energy)
    score = score + 30 * math.max(0, 1 - energy_diff)
    
    -- Rhythmic complexity bonus
    if clip.analysis.rhythmic_density > 5 and clip.analysis.rhythmic_density < 15 then
      score = score + 20 -- Good density range for djembe
    end
    
    -- Duration preference (prefer longer clips)
    score = score + 10 * (clip.duration / config.clip_duration_max)
    
    clip.compatibility_score = score
    
    print(string.format("  Clip: %s [%.1f-%.1f s] Score: %.1f",
          clip.region:name(), clip.start_offset, clip.start_offset + clip.duration, score))
  end
  
  -- Sort by compatibility score
  table.sort(djembe_clips, function(a, b) return a.compatibility_score > b.compatibility_score end)
  
  -- Select top clips
  local selected_clips = {}
  for i = 1, math.min(config.num_clips_to_find, #djembe_clips) do
    if djembe_clips[i].compatibility_score > 20 then -- Minimum score threshold
      table.insert(selected_clips, djembe_clips[i])
    end
  end
  
  if #selected_clips == 0 then
    print("\nERROR: No compatible djembe clips found")
    return
  end
  
  print(string.format("\n=== SELECTED %d DJEMBE CLIPS ===", #selected_clips))
  for i, clip in ipairs(selected_clips) do
    print(string.format("%d. %s (score: %.1f, tempo: %.1f)",
          i, clip.region:name(), clip.compatibility_score, clip.analysis.tempo or 0))
  end
  
  -- Output recommendations
  print("\n=== MANUAL PLACEMENT RECOMMENDATIONS ===")
  print("To manually place the djembe clips in your project:")
  print("")
  
  local placement_time = target_section.start_time
  
  for i, clip in ipairs(selected_clips) do
    print(string.format("CLIP %d:", i))
    print(string.format("  Track/Region: %s / %s", clip.track.name, clip.region:name()))
    print(string.format("  Extract from: %.1f to %.1f seconds", 
          clip.start_offset, clip.start_offset + clip.duration))
    print(string.format("  Place at: %.1f seconds in the EDM track", placement_time))
    print(string.format("  Duration: %.1f seconds", clip.duration))
    print("")
    
    -- Space out clips slightly
    placement_time = placement_time + 2.0
  end
  
  print("STEPS TO APPLY:")
  print("1. Create a new audio track for the djembe fusion")
  print("2. For each clip above:")
  print("   - Navigate to the specified track and region")
  print("   - Use the Range tool to select the specified time range")
  print("   - Copy the selection")
  print("   - Paste at the specified placement time in the new track")
  print("3. Adjust levels and apply effects as needed")
  print("")
  print("MIXING TIPS:")
  print("- Apply EQ to carve out space for the djembe (boost 2-4kHz for presence)")
  print("- Use sidechain compression triggered by the EDM kick")
  print("- Add reverb to place the djembe in the mix")
  print("- Consider panning djembe slightly off-center")
  
end end

-- Icon for the script
function icon(params) return function(ctx, width, height, fg)
  local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(width * .3) .. "px")
  txt:set_text("🎵🥁🎵")
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to(.5 * (width - tw), .5 * (height - th))
  txt:show_in_cairo_context(ctx)
end end 