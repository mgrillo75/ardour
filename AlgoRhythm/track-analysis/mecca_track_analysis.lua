ardour {
  ["type"]    = "EditorAction",
  name        = "Mecca Track Analysis",
  license     = "MIT",
  author      = "AI/You",
  description = [[Analyze tracks and drum samples as specified in mecca-track-analysis.md]]
}

function factory () return function ()
  print("=== Mecca Track Analysis (from scratch) ===")

  -- Configuration
  local target_track_names = {
    "main-track", "synth1-stem", "drums-stem",
    "bass-stem", "synth2-stem", "tdrum-samples"
  }
  local start_sec = 64.0
  local end_sec   = 96.0
  local sr = Session:nominal_sample_rate()
  local start_sample = start_sec * sr
  local end_sample = end_sec * sr

  -- Helper: Table pretty print
  local function table_to_string(tbl, max_items)
    if not tbl or #tbl == 0 then return "[]" end
    local parts = {}
    for i = 1, math.min(#tbl, max_items or 5) do
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
    if #tbl > (max_items or 5) then str = str .. ", ... (" .. #tbl .. " total)" end
    return str .. "]"
  end

  -- Helper: K-means clustering (Euclidean, 3D: centroid, rms, zcr)
  local function kmeans(features, k, max_iter)
    max_iter = max_iter or 20
    if #features < k then return {} end
    local centroids = {}
    for i = 1, k do
      centroids[i] = {
        centroid = features[i].centroid,
        rms = features[i].rms,
        zcr = features[i].zcr
      }
    end
    local assignments = {}
    for iter = 1, max_iter do
      for i, f in ipairs(features) do
        local min_dist, min_idx = math.huge, 1
        for j, c in ipairs(centroids) do
          local d = (f.centroid-c.centroid)^2 + (f.rms-c.rms)^2 + (f.zcr-c.zcr)^2
          if d < min_dist then min_dist, min_idx = d, j end
        end
        assignments[i] = min_idx
      end
      local sums, counts = {}, {}
      for j = 1, k do sums[j] = {centroid=0, rms=0, zcr=0}; counts[j]=0 end
      for i, f in ipairs(features) do
        local a = assignments[i]
        sums[a].centroid = sums[a].centroid + f.centroid
        sums[a].rms = sums[a].rms + f.rms
        sums[a].zcr = sums[a].zcr + f.zcr
        counts[a] = counts[a] + 1
      end
      for j = 1, k do
        if counts[j] > 0 then
          centroids[j].centroid = sums[j].centroid / counts[j]
          centroids[j].rms = sums[j].rms / counts[j]
          centroids[j].zcr = sums[j].zcr / counts[j]
        end
      end
    end
    return assignments
  end

  -- Helper: Compute ZCR from Vamp plugin (if available)
  local function compute_zcr_vamp(audio_region, sr)
    local zcr_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-zcr", sr)
    local zcr = 0
    local count = 0
    local function zcr_callback(feats)
      local fl = feats:table()[0]
      if fl then
        for f in fl:iter() do
          if f.values and f.values:size() > 0 then
            zcr = zcr + f.values:at(0)
            count = count + 1
          end
        end
      end
      return false
    end
    zcr_vamp:analyze(audio_region:to_readable(), 0, zcr_callback)
    zcr_callback(zcr_vamp:plugin():getRemainingFeatures())
    zcr_vamp:reset()
    if count > 0 then return zcr / count else return 0 end
  end

  -- Helper: Compute spectral centroid from Vamp plugin (if available)
  local function compute_spectral_centroid_vamp(audio_region, sr)
    local ok, sc_vamp = pcall(function()
      return ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-spectralcentroid", sr)
    end)
    if not ok or not sc_vamp then
      print("    [Warning] Spectral centroid plugin not available, skipping.")
      return 0
    end
    local centroid = 0
    local count = 0
    local function sc_callback(feats)
      local fl = feats:table()[0]
      if fl then
        for f in fl:iter() do
          if f.values and f.values:size() > 0 then
            centroid = centroid + f.values:at(0)
            count = count + 1
          end
        end
      end
      return false
    end
    sc_vamp:analyze(audio_region:to_readable(), 0, sc_callback)
    sc_callback(sc_vamp:plugin():getRemainingFeatures())
    sc_vamp:reset()
    if count > 0 then return centroid / count else return 0 end
  end

  -- Main analysis result table
  local analysis = {
    analysis_range = { start_sec = start_sec, end_sec = end_sec },
    tracks = {},
    talking_drum_samples = {}
  }

  -- Iterate tracks
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track or track:isnil() then goto continue end
    local track_name = route:name()
    local is_target = false
    for _, name in ipairs(target_track_names) do
      if name == track_name then is_target = true; break end
    end
    if not is_target then goto continue end
    print("\n--- Analyzing Track: " .. track_name .. " ---")
    local playlist = track:playlist()
    if not playlist or playlist:isnil() then print("  No playlist"); goto continue end
    if track_name == "tdrum-samples" then
      -- Each region is a drum hit
      for region in playlist:region_list():iter() do
        local audio_region = region:to_audioregion()
        if audio_region and not audio_region:isnil() then
          -- RMS (Vamp amplitude follower)
          local rms_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:amplitudefollower", sr)
          rms_vamp:plugin():setParameter("attack", 0.01)
          rms_vamp:plugin():setParameter("release", 0.01)
          local rms_sum, rms_count = 0, 0
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
          rms_callback(rms_vamp:plugin():getRemainingFeatures())
          rms_vamp:reset()
          local avg_rms = (rms_count > 0) and (rms_sum / rms_count) or 0
          -- Peak (Vamp dBTP)
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
          -- Spectral centroid (Vamp)
          local centroid = compute_spectral_centroid_vamp(audio_region, sr)
          -- ZCR (Vamp)
          local zcr = compute_zcr_vamp(audio_region, sr)
          table.insert(analysis.talking_drum_samples, {
            id = region:name(),
            start_sec = region:position():samples() / sr,
            duration_sec = region:length():samples() / sr,
            rms = avg_rms,
            peak = peak_value,
            spectral_centroid = centroid,
            zcr = zcr,
            cluster = 0 -- to be set by kmeans
          })
        end
      end
    else
      -- Regular track analysis
      for region in playlist:region_list():iter() do
        local region_start = region:position():samples()
        local region_end = region_start + region:length():samples()
        if region_start < end_sample and region_end > start_sample then
          local audio_region = region:to_audioregion()
          if audio_region and not audio_region:isnil() then
            -- Onset detection (Vamp plugin)
            local onset_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sr)
            onset_vamp:plugin():setParameter("dftype", 3)
            onset_vamp:plugin():setParameter("sensitivity", 50)
            local onsets = {}
            local function onset_callback(feats)
              local fl = feats:table()[0]
              if fl then
                for f in fl:iter() do
                  if f.hasTimestamp then
                    local s = Vamp.RealTime.realTime2Frame(f.timestamp, sr) + region_start
                    if s >= start_sample and s <= end_sample then 
                      table.insert(onsets, (s/sr))
                    end
                  end
                end
              end
              return false
            end
            onset_vamp:analyze(audio_region:to_readable(), 0, onset_callback)
            onset_callback(onset_vamp:plugin():getRemainingFeatures())
            onset_vamp:reset()
            table.sort(onsets)
            -- IOI histogram (filter IOIs < 0.2s)
            local ioi_histogram = {}
            local filtered_iois = {}
            if #onsets > 1 then
              for i = 1, #onsets-1 do
                local ioi = (onsets[i+1] - onsets[i])
                if ioi >= 0.2 then
                  local ioi_ms = math.floor(ioi*1000+0.5)
                  ioi_histogram[ioi_ms] = (ioi_histogram[ioi_ms] or 0) + 1
                  table.insert(filtered_iois, ioi)
                end
              end
            end
            -- Tempo estimation (Vamp beat tracker)
            local tempo = 0
            local beat_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-tempotracker", sr)
            beat_vamp:analyze(audio_region:to_readable(), 0, nil)
            local tempo_features = beat_vamp:plugin():getRemainingFeatures()
            local tempo_list = tempo_features:table()[1]
            if tempo_list and tempo_list:size() > 0 then
              local tempo_feature = tempo_list:at(0)
              if tempo_feature.values and tempo_feature.values:size() > 0 then
                local seconds_per_beat = tempo_feature.values:at(0)
                if seconds_per_beat > 0 then
                  tempo = 60.0 / seconds_per_beat
                end
              end
            end
            beat_vamp:reset()
            -- RMS envelope (Vamp amplitude follower)
            local rms_vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:amplitudefollower", sr)
            rms_vamp:plugin():setParameter("attack", 0.01)
            rms_vamp:plugin():setParameter("release", 0.01)
            local rms_env = {}
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
                      table.insert(rms_env, {s/sr, val})
                    end
                  end
                end
              end
              return false
            end
            rms_vamp:analyze(audio_region:to_readable(), 0, rms_callback)
            rms_callback(rms_vamp:plugin():getRemainingFeatures())
            rms_vamp:reset()
            -- Spectral centroid (Vamp)
            local centroid = compute_spectral_centroid_vamp(audio_region, sr)
            -- Peak (Vamp dBTP)
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
            -- Beat division (not implemented, set to 0)
            local beat_division = 0
            table.insert(analysis.tracks, {
              name = track_name,
              onsets = onsets,
              rms_envelope = rms_env,
              spectral_centroid = centroid,
              ioi_histogram = ioi_histogram,
              tempo = tempo,
              beat_division = beat_division,
              peak = peak_value
            })
          end
        end
      end
    end
    ::continue::
  end

  -- K-means clustering for talking drum samples
  local features = {}
  for i, hit in ipairs(analysis.talking_drum_samples) do
    features[i] = {centroid=hit.spectral_centroid, rms=hit.rms, zcr=hit.zcr}
  end
  local k = 2 -- or 3, as needed
  local assignments = kmeans(features, k)
  for i, cluster in ipairs(assignments) do
    analysis.talking_drum_samples[i].cluster = cluster or 0
  end

  -- Print results
  print("\n=== Analysis Results ===")
  print("Analysis range: " .. start_sec .. "s to " .. end_sec .. "s")
  for _, t in ipairs(analysis.tracks) do
    print("\nTrack: " .. t.name)
    print("  Tempo: " .. string.format("%.2f", t.tempo) .. " BPM")
    print("  Onsets (s): " .. table_to_string(t.onsets, 10))
    print("  IOI Histogram (ms): ")
    local ioi_list = {}
    for ioi, count in pairs(t.ioi_histogram) do table.insert(ioi_list, {ioi=ioi, count=count}) end
    table.sort(ioi_list, function(a,b) return a.ioi < b.ioi end)
    for i = 1, math.min(10, #ioi_list) do
      print(string.format("    %d ms: %d", ioi_list[i].ioi, ioi_list[i].count))
    end
    print("  RMS Envelope (first 10): " .. table_to_string(t.rms_envelope, 10))
    print("  Spectral Centroid: " .. string.format("%.1f Hz", t.spectral_centroid))
    print("  Peak: " .. string.format("%.3f", t.peak))
  end
  print("\nTalking Drum Samples:")
  for _, hit in ipairs(analysis.talking_drum_samples) do
    print(string.format("  %s: start=%.3fs dur=%.3fs rms=%.3f peak=%.3f centroid=%.1fHz zcr=%.3f cluster=%d",
      hit.id, hit.start_sec, hit.duration_sec, hit.rms, hit.peak, hit.spectral_centroid, hit.zcr, hit.cluster))
  end
  print("\n=== Analysis Complete ===")
end end 