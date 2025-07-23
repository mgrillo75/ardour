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
  
    -- Helper: K-means clustering (Euclidean, 3D: flux, rms, contrast)
    local function kmeans(features, k, max_iter)
      max_iter = max_iter or 20
      if #features < k then return {} end
      local centroids = {}
      for i = 1, k do
        centroids[i] = {
          flux = features[i].flux,
          rms = features[i].rms,
          contrast = features[i].contrast
        }
      end
      local assignments = {}
      for iter = 1, max_iter do
        for i, f in ipairs(features) do
          local min_dist, min_idx = math.huge, 1
          for j, c in ipairs(centroids) do
            local d = (f.flux - c.flux)^2 + (f.rms - c.rms)^2 + (f.contrast - c.contrast)^2
            if d < min_dist then min_dist, min_idx = d, j end
          end
          assignments[i] = min_idx
        end
        local sums, counts = {}, {}
        for j = 1, k do sums[j] = {flux=0, rms=0, contrast=0}; counts[j]=0 end
        for i, f in ipairs(features) do
          local a = assignments[i]
          sums[a].flux     = sums[a].flux     + f.flux
          sums[a].rms      = sums[a].rms      + f.rms
          sums[a].contrast = sums[a].contrast + f.contrast
          counts[a] = counts[a] + 1
        end
        for j = 1, k do
          if counts[j] > 0 then
            centroids[j].flux     = sums[j].flux     / counts[j]
            centroids[j].rms      = sums[j].rms      / counts[j]
            centroids[j].contrast = sums[j].contrast / counts[j]
          end
        end
      end
      return assignments
    end
  
    -- Helper: Compute spectral flux (bbc-spectral-flux)
    local function compute_spectral_flux(audio_region, sr)
      local ok, flux = pcall(function()
        return ARDOUR.LuaAPI.Vamp("bbc-spectral-flux", sr)
      end)
      if not ok or not flux then
        print("    [Warning] spectral-flux plugin not available, skipping.")
        return 0
      end
      local total, count = 0, 0
      local function flux_cb(feats)
        local fl = feats:table()[0]
        if fl then
          for f in fl:iter() do
            if f.values and f.values:size() > 0 then
              total = total + f.values:at(0)
              count = count + 1
            end
          end
        end
        return false
      end
      flux:analyze(audio_region:to_readable(), 0, flux_cb)
      flux_cb(flux:plugin():getRemainingFeatures())
      flux:reset()
      return (count>0) and (total/count) or 0
    end
  
    -- Helper: Compute mean spectral contrast (bbc-spectral-contrast)
    local function compute_spectral_contrast(audio_region, sr)
      local ok, sc = pcall(function()
        return ARDOUR.LuaAPI.Vamp("bbc-spectral-contrast", sr)
      end)
      if not ok or not sc then
        print("    [Warning] spectral-contrast plugin not available, skipping.")
        return 0
      end
      local mean_c, count = 0, 0
      local function sc_cb(feats)
        local fl = feats:table()[2]
        if fl then
          for f in fl:iter() do
            if f.values and f.values:size() > 0 then
              mean_c = mean_c + f.values:at(0)
              count = count + 1
            end
          end
        end
        return false
      end
      sc:analyze(audio_region:to_readable(), 0, sc_cb)
      sc_cb(sc:plugin():getRemainingFeatures())
      sc:reset()
      return (count>0) and (mean_c/count) or 0
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
        -- Drum hit samples
        for region in playlist:region_list():iter() do
          local audio_region = region:to_audioregion()
          if audio_region and not audio_region:isnil() then
            -- RMS (amplitude follower)
            local rms_vamp = ARDOUR.LuaAPI.Vamp("amplitudefollower", sr)
            rms_vamp:plugin():setParameter("attack", 0.01)
            rms_vamp:plugin():setParameter("release", 0.01)
            local rms_sum, rms_count = 0, 0
            local function rms_cb(feats)
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
            rms_vamp:analyze(audio_region:to_readable(), 0, rms_cb)
            rms_cb(rms_vamp:plugin():getRemainingFeatures())
            rms_vamp:reset()
            local avg_rms = (rms_count>0) and (rms_sum/rms_count) or 0
  
            -- Peak (True Peak)
            local peak_vamp = ARDOUR.LuaAPI.Vamp("dBTP", sr)
            peak_vamp:analyze(audio_region:to_readable(), 0, nil)
            local pf = peak_vamp:plugin():getRemainingFeatures()
            local lvl_list = pf:table()[0]
            local peak_val = (lvl_list and lvl_list:size()>0) and lvl_list:at(0) or 0
            peak_vamp:reset()
  
            -- Spectral features
            local flux     = compute_spectral_flux(audio_region, sr)
            local contrast = compute_spectral_contrast(audio_region, sr)
  
            table.insert(analysis.talking_drum_samples, {
              id = region:name(),
              start_sec    = region:position():samples()/sr,
              duration_sec = region:length():samples()/sr,
              rms      = avg_rms,
              peak     = peak_val,
              flux     = flux,
              contrast = contrast,
              cluster  = 0
            })
          end
        end
  
      else
        -- Regular track analysis
        for region in playlist:region_list():iter() do
          local rstart = region:position():samples()
          local rend   = rstart + region:length():samples()
          if rstart < end_sample and rend > start_sample then
            local audio_region = region:to_audioregion()
            if audio_region and not audio_region:isnil() then
              -- Onsets (Aubio onset)
              local onset_vamp = ARDOUR.LuaAPI.Vamp("aubioonset", sr)
              onset_vamp:plugin():setParameter("onsettype", 3)
              onset_vamp:plugin():setParameter("peakpickthreshold", 0.3)
              onset_vamp:plugin():setParameter("silencethreshold", 0.1)
              local onsets = {}
              local function on_cb(feats)
                local fl = feats:table()[0]
                if fl then
                  for f in fl:iter() do
                    if f.hasTimestamp then
                      local s = Vamp.RealTime.realTime2Frame(f.timestamp, sr) + rstart
                      if s>=start_sample and s<=end_sample then table.insert(onsets, s/sr) end
                    end
                  end
                end
                return false
              end
              onset_vamp:analyze(audio_region:to_readable(), 0, on_cb)
              on_cb(onset_vamp:plugin():getRemainingFeatures())
              onset_vamp:reset()
              table.sort(onsets)
  
              -- IOI histogram
              local ioi_hist = {}
              if #onsets>1 then for i=1,#onsets-1 do
                  local delta = onsets[i+1]-onsets[i]
                  if delta>=0.2 then
                    local ms = math.floor(delta*1000+0.5)
                    ioi_hist[ms] = (ioi_hist[ms] or 0) + 1
                  end
                end end
  
              -- Tempo (bbc-rhythm)
              local tempo = 0
              local rvamp = ARDOUR.LuaAPI.Vamp("bbc-rhythm", sr)
              rvamp:plugin():setParameter("min_bpm", 40)
              rvamp:plugin():setParameter("max_bpm",200)
              rvamp:analyze(audio_region:to_readable(), 0, nil)
              local rf = rvamp:plugin():getRemainingFeatures()
              local tlist = rf:table()[6]
              if tlist and tlist:size()>0 then tempo = tlist:at(0) end
              rvamp:reset()
  
              -- RMS envelope
              local rms_env = {}
              local rms_vamp = ARDOUR.LuaAPI.Vamp("amplitudefollower", sr)
              rms_vamp:plugin():setParameter("attack",0.01)
              rms_vamp:plugin():setParameter("release",0.01)
              local function rms_cb2(feats)
                local fl = feats:table()[0]
                if fl then for f in fl:iter() do
                    if f.hasTimestamp then
                      local s = Vamp.RealTime.realTime2Frame(f.timestamp, sr)+rstart
                      if s>=start_sample and s<=end_sample then
                        local v = (f.values and f.values:size()>0) and f.values:at(0) or 0
                        table.insert(rms_env,{s/sr,v})
                      end
                    end
                  end end
                return false
              end
              rms_vamp:analyze(audio_region:to_readable(),0,rms_cb2)
              rms_cb2(rms_vamp:plugin():getRemainingFeatures())
              rms_vamp:reset()
  
              -- Peak
              local peak_v = ARDOUR.LuaAPI.Vamp("dBTP", sr)
              peak_v:analyze(audio_region:to_readable(),0,nil)
              local pf2 = peak_v:plugin():getRemainingFeatures()
              local lvl2 = pf2:table()[0]
              local peak_val2 = (lvl2 and lvl2:size()>0) and lvl2:at(0) or 0
              peak_v:reset()
  
              table.insert(analysis.tracks,{
                name = track_name,
                onsets = onsets,
                rms_envelope = rms_env,
                ioi_histogram = ioi_hist,
                tempo = tempo,
                peak = peak_val2
              })
            end
          end
        end
      end
      ::continue::
    end
  
    -- Cluster drum samples
    local features = {}
    for i,hit in ipairs(analysis.talking_drum_samples) do
      features[i] = {flux=hit.flux, rms=hit.rms, contrast=hit.contrast}
    end
    local assigns = kmeans(features,2)
    for i,c in ipairs(assigns) do analysis.talking_drum_samples[i].cluster = c or 0 end
  
    -- Print results
    print("\n=== Analysis Results ===")
    print("Range: "..start_sec.."s to "..end_sec.."s")
    for _,t in ipairs(analysis.tracks) do
      print("\nTrack: "..t.name)
      print("  Tempo: "..string.format("%.2f",t.tempo).." BPM")
      print("  Onsets: "..table_to_string(t.onsets,10))
      print("  IOI Histogram: ")
      local iolist={} for ms,c in pairs(t.ioi_histogram) do table.insert(iolist,{ms=ms,c=c}) end
      table.sort(iolist,function(a,b) return a.ms<b.ms end)
      for i=1,math.min(10,#iolist) do print(string.format("    %d ms: %d", iolist[i].ms, iolist[i].c)) end
      print("  RMS Env (first 10): "..table_to_string(t.rms_envelope,10))
      print("  Peak: "..string.format("%.3f",t.peak))
    end
    print("\nDrum Samples:")
    for _,h in ipairs(analysis.talking_drum_samples) do
      print(string.format("  %s: start=%.3fs dur=%.3fs rms=%.3f peak=%.3f flux=%.3f contrast=%.3f cluster=%d",
        h.id,h.start_sec,h.duration_sec,h.rms,h.peak,h.flux,h.contrast,h.cluster))
    end
    print("\n=== Analysis Complete ===")
  end end
  