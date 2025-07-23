ardour {
  ["type"]    = "EditorAction",
  name        = "Mecca Track Analysis",
  license     = "MIT",
  author      = "Fixed",
  description = [[Analyzes specified tracks within a time range based on mecca-track-analysis.md]]
}

function factory () return function ()

  print("=== Starting Mecca Track Analysis ===")

  ---------------------------------------------------------------------
  -- Configuration
  ---------------------------------------------------------------------

  local target_track_names = {
    "main-track", "synth1-stem", "drums-stem",
    "bass-stem", "synth2-stem", "tdrum-samples"
  }
  local start_sec = 64.0
  local end_sec   = 96.0

  ---------------------------------------------------------------------
  -- Helper Functions
  ---------------------------------------------------------------------

  function table_to_string(tbl)
    if not tbl or #tbl == 0 then return "[]" end
    local parts = {}
    for i = 1, math.min(#tbl, 5) do
      if type(tbl[i]) == "table" then
        local sub_parts = {}
        for _, v in ipairs(tbl[i]) do
          if type(v) == "number" then 
            table.insert(sub_parts, string.format("%.3f", v))
          else 
            table.insert(sub_parts, tostring(v)) 
          end
        end
        table.insert(parts, "{" .. table.concat(sub_parts, ", ") .. "}")
      else
        table.insert(parts, tostring(tbl[i]))
      end
    end
    local str = "[" .. table.concat(parts, ", ")
    if #tbl > 5 then str = str .. ", ... (" .. #tbl .. " total)" end
    return str .. "]"
  end

  ---------------------------------------------------------------------
  -- Main Logic
  ---------------------------------------------------------------------

  local sr = Session:nominal_sample_rate()
  local start_sample = start_sec * sr
  local end_sample = end_sec * sr
  print(string.format("Time range: %.3fs to %.3fs (%d to %d samples)", start_sec, end_sec, start_sample, end_sample))

  -- Process each target track
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track or track:isnil() then
      goto continue
    end
    
    local track_name = route:name()
    local is_target_track = false
    for _, name in ipairs(target_track_names) do
      if name == track_name then 
        is_target_track = true
        break 
      end
    end

    if is_target_track then
      print(string.format("\n--- Analyzing Track: %s ---", track_name))
      
      local playlist = track:playlist()
      if not playlist or playlist:isnil() then
        print("  WARNING: No playlist found for track")
        goto continue
      end
      
      -- Special handling for tdrum-samples track
      if track_name == "tdrum-samples" then
        print("  [Special handling: Each region is a separate drum hit]")
      end
      
      for region in playlist:region_list():iter() do
        local region_start = region:position():samples()
        local region_end = region_start + region:length():samples()

        -- For tdrum-samples, analyze all regions regardless of time range
        local should_analyze = false
        if track_name == "tdrum-samples" then
          should_analyze = true
        elseif region_start < end_sample and region_end > start_sample then
          should_analyze = true
        end
        
        if should_analyze then
          local audio_region = region:to_audioregion()
          if audio_region and not audio_region:isnil() then
            print(string.format("  - Analyzing Region: %s", region:name()))
            
            -- Special analysis for drum samples
            if track_name == "tdrum-samples" then
              local duration_sec = region:length():samples() / sr
              local start_time_sec = region:position():samples() / sr
              
              -- Get peak and RMS for the entire sample
              local peak_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:dBTP", sr)
              peak_vamp:analyze(audio_region:to_readable(), 0, nil)
              local peak_features = peak_vamp:plugin():getRemainingFeatures()
              
              local peak_value = 0
              local level_list = peak_features:table()[0]
              if level_list and level_list:size() > 0 then
                local level_feature = level_list:at(0)
                if level_feature.values and level_feature.values:size() > 0 then
                  peak_value = level_feature.values:at(0)
                end
              end
              peak_vamp:reset()
              
              -- Get average RMS
              local rms_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:amplitudefollower", sr)
              rms_vamp:plugin():setParameter("attack", 0.001)
              rms_vamp:plugin():setParameter("release", 0.001)
              
              local rms_sum = 0
              local rms_count = 0
              
              local function rms_callback(feats)
                local fl = feats:table()[0]
                if fl then
                  for f in fl:iter() do
                    if f.values and f.values:size() > 0 then
                      rms_sum = rms_sum + f.values:at(0)
                      rms_count = rms_count + 1
                    end
                  end
                end
                return false
              end
              
              rms_vamp:analyze(audio_region:to_readable(), 0, rms_callback)
              local rms_remaining = rms_vamp:plugin():getRemainingFeatures()
              if rms_remaining then
                rms_callback(rms_remaining)
              end
              rms_vamp:reset()
              
              local avg_rms = 0
              if rms_count > 0 then
                avg_rms = rms_sum / rms_count
              end
              
              -- Print drum sample analysis
              print(string.format("    Start: %.3f sec", start_time_sec))
              print(string.format("    Duration: %.3f sec", duration_sec))
              print(string.format("    Peak: %.3f", peak_value))
              print(string.format("    RMS: %.3f", avg_rms))
              print("    [Note: Would calculate spectral centroid and ZCR for clustering]")
              
              goto next_region
            end
            
            -- Results container for regular tracks
            local results = { 
              onsets = {}, 
              tempo_candidates = {},
              tempo = 0, 
              peaks = {}, 
              rms_envelope = {}, 
              spectral_energy = {} 
            }

            -- 1. Onset detection
            local onset_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sr)
            onset_vamp:plugin():setParameter("dftype", 3)
            onset_vamp:plugin():setParameter("sensitivity", 50)
            
            local function onset_callback(feats)
              local fl = feats:table()[0]
              if fl then
                for f in fl:iter() do
                  if f.hasTimestamp then
                    local s = Vamp.RealTime.realTime2Frame(f.timestamp, sr) + region_start
                    if s >= start_sample and s <= end_sample then 
                      table.insert(results.onsets, s) 
                    end
                  end
                end
              end
              return false -- continue processing
            end
            
            onset_vamp:analyze(audio_region:to_readable(), 0, onset_callback)
            onset_callback(onset_vamp:plugin():getRemainingFeatures())
            onset_vamp:reset()
            
            table.sort(results.onsets)
            print("    Onsets: " .. table_to_string(results.onsets))

            -- Calculate IOI Histogram
            if #results.onsets > 1 then
              local ioi_histogram = {}
              for i = 1, #results.onsets - 1 do
                local ioi_ms = math.floor((results.onsets[i+1] - results.onsets[i]) / sr * 1000)
                ioi_histogram[ioi_ms] = (ioi_histogram[ioi_ms] or 0) + 1
              end
              -- Print top IOIs
              local ioi_sorted = {}
              for ioi, count in pairs(ioi_histogram) do
                table.insert(ioi_sorted, {ioi = ioi, count = count})
              end
              table.sort(ioi_sorted, function(a, b) return a.count > b.count end)
              print("    IOI Histogram (top 5):")
              for i = 1, math.min(5, #ioi_sorted) do
                print(string.format("      %d ms: %d occurrences", ioi_sorted[i].ioi, ioi_sorted[i].count))
              end
            end

            -- 2. Tempo detection using tempo tracker
            local tempo_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-tempotracker", sr)
            
            -- Run analysis without callback first
            tempo_vamp:analyze(audio_region:to_readable(), 0, nil)
            
            -- Get remaining features
            local tempo_features = tempo_vamp:plugin():getRemainingFeatures()
            
            -- Tempo is in the 2nd output (index 1)
            local tempo_list = tempo_features:table()[1]
            if tempo_list and tempo_list:size() > 0 then
              local tempo_feature = tempo_list:at(0)
              if tempo_feature.values and tempo_feature.values:size() > 0 then
                -- The tempo tracker returns tempo in seconds per beat, convert to BPM
                local seconds_per_beat = tempo_feature.values:at(0)
                if seconds_per_beat > 0 then
                  results.tempo = 60.0 / seconds_per_beat
                end
              end
            end
            
            tempo_vamp:reset()
            print(string.format("    Tempo: %.2f BPM", results.tempo))

            -- 3. Peak detection using dBTP meter
            local peak_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:dBTP", sr)
            
            -- Run analysis without callback
            peak_vamp:analyze(audio_region:to_readable(), 0, nil)
            
            -- Get remaining features
            local peak_features = peak_vamp:plugin():getRemainingFeatures()
            
            -- dBTP has two outputs: level (0) and peaks (1)
            -- First get the overall true peak level
            local level_list = peak_features:table()[0]
            if level_list and level_list:size() > 0 then
              local level_feature = level_list:at(0)
              if level_feature.values and level_feature.values:size() > 0 then
                local peak_val = level_feature.values:at(0)
                local dbtp = 20 * math.log(peak_val) / math.log(10)
                print(string.format("    True Peak: %.2f dBTP", dbtp))
              end
            end
            
            -- Get peaks above threshold
            local peaks_list = peak_features:table()[1]
            if peaks_list then
              for f in peaks_list:iter() do
                if f.hasTimestamp then
                  local s = Vamp.RealTime.realTime2Frame(f.timestamp, sr) + region_start
                  if s >= start_sample and s <= end_sample then
                    table.insert(results.peaks, s)
                  end
                end
              end
            end
            
            peak_vamp:reset()
            print("    Peak locations: " .. table_to_string(results.peaks))

            -- 4. RMS envelope using amplitude follower
            local rms_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:amplitudefollower", sr)
            rms_vamp:plugin():setParameter("attack", 0.01)
            rms_vamp:plugin():setParameter("release", 0.01)
            
            -- Collect RMS values during analysis
            local rms_values = {}
            
            local function rms_callback(feats)
              local fl = feats:table()[0]
              if fl then
                for f in fl:iter() do
                  if f.hasTimestamp then
                    local s = Vamp.RealTime.realTime2Frame(f.timestamp, sr) + region_start
                    if s >= start_sample and s <= end_sample then
                      local val = 0
                      if f.values and f.values:size() > 0 then
                        val = f.values:at(0)
                      end
                      table.insert(rms_values, {s, val})
                    end
                  end
                end
              end
              return false
            end
            
            rms_vamp:analyze(audio_region:to_readable(), 0, rms_callback)
            
            -- Get any remaining features
            local rms_remaining = rms_vamp:plugin():getRemainingFeatures()
            if rms_remaining then
              rms_callback(rms_remaining)
            end
            
            rms_vamp:reset()
            
            -- Downsample to ~1 value per second for readability
            if #rms_values > 0 then
              local samples_per_second = sr
              local current_pos = start_sample
              while current_pos < end_sample do
                local sum = 0
                local count = 0
                for _, v in ipairs(rms_values) do
                  if v[1] >= current_pos and v[1] < current_pos + samples_per_second then
                    sum = sum + v[2]
                    count = count + 1
                  end
                end
                if count > 0 then
                  table.insert(results.rms_envelope, {current_pos, sum / count})
                end
                current_pos = current_pos + samples_per_second
              end
            end
            
            print("    RMS Envelope (1 sec avg): " .. table_to_string(results.rms_envelope))

            -- 5. Spectral analysis - Try to use chromagram or skip if it fails
            local spectral_ok, spectral_vamp = pcall(function()
              return ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-chromagram", sr)
            end)
            
            if spectral_ok and spectral_vamp then
              local spectral_values = {}
              
              local function spectral_callback(feats)
                if not feats then return false end
                local fl = feats:table()[0]
                if fl then
                  for f in fl:iter() do
                    if f.hasTimestamp then
                      local s = Vamp.RealTime.realTime2Frame(f.timestamp, sr) + region_start
                      if s >= start_sample and s <= end_sample then
                        local values = {}
                        if f.values then
                          for i = 0, f.values:size() - 1 do
                            table.insert(values, f.values:at(i))
                          end
                        end
                        if #values > 0 then
                          table.insert(spectral_values, {s, values})
                        end
                      end
                    end
                  end
                end
                return false
              end
              
              local analyze_ok = pcall(function()
                spectral_vamp:analyze(audio_region:to_readable(), 0, spectral_callback)
              end)
              
              if analyze_ok then
                -- Get remaining features safely
                local remaining_ok, remaining_feats = pcall(function()
                  return spectral_vamp:plugin():getRemainingFeatures()
                end)
                
                if remaining_ok and remaining_feats then
                  spectral_callback(remaining_feats)
                end
                
                -- Downsample spectral data for readability (1 per second)
                if #spectral_values > 0 then
                  local samples_per_second = sr
                  local current_pos = start_sample
                  while current_pos < end_sample do
                    for _, v in ipairs(spectral_values) do
                      if v[1] >= current_pos and v[1] < current_pos + samples_per_second then
                        -- Just take the first chromagram in each second
                        table.insert(results.spectral_energy, {current_pos, v[2]})
                        break
                      end
                    end
                    current_pos = current_pos + samples_per_second
                  end
                end
              end
              
              pcall(function() spectral_vamp:reset() end)
              print("    Spectral (Chromagram): " .. table_to_string(results.spectral_energy))
            else
              print("    WARNING: Spectral analysis (chromagram) not available")
            end
                      end
          end
          ::next_region::
        end
      end
      ::continue::
    end

  print("\n=== Analysis Complete ===")
  print("\nNote: This analysis is designed for the time range 1:04 to 1:36 (64-96 seconds)")
  print("as specified in mecca-track-analysis.md")
  print("\nTo generate a Lua script for placing drum hits, copy the output above")
  print("and provide it to an LLM along with the mecca-track-analysis.md specification.")
end end 