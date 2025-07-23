ardour {
  ["type"] = "EditorAction",
  name = "Dundun Auto Rhythm Generator",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Automatically extract percussive hits from a solo dundun performance and generate a structured looping motif.

Pipeline (see dundun-specs.md):
1. Onset detection → slice extraction
2. Feature calc (RMS + ZCR) & k-means clustering
3. Pattern construction using two tone groups (A/B)
4. Region cloning & quantised placement on a dedicated track
  ]]
}

function factory() return function()
  ---------------------------------------------------------------------
  -- CONFIGURATION -----------------------------------------------------
  ---------------------------------------------------------------------
  local cfg = {
    slice_duration       = 0.20,   -- seconds
    group_count          = 4,      -- tone clusters
    pattern_tokens       = {"A","B","B","B","A","B","B","B","A"},
    quantisation_beats   = 0.5,    -- ½-beat grid
    repeat_count         = 4,      -- loop repetitions
    default_bpm          = 120,    -- fallback tempo
    humanise_timing_ms   = 20,     -- ± jitter
    humanise_gain_db     = 2,      -- ± gain variation
    output_track_name    = "generated-drum-track"
  }

  ---------------------------------------------------------------------
  -- Locate source track/region (exactly one region expected) ----------
  ---------------------------------------------------------------------
  local source_track, source_region
  for route in Session:get_routes():iter() do
    local tr = route:to_track()
    if not tr:isnil() then
      local at = tr:to_audio_track()
      if not at:isnil() then
        local pl = at:playlist()
        local rl = pl:region_list()
        if rl:size() == 1 then
          -- Get the single region via iterator (more portable than :front())
          for reg in rl:iter() do
            source_track = at
            source_region = reg
            break
          end
          if source_region then break end
        end
      end
    end
  end

  if not source_track or not source_region then
    print("ERROR: No eligible single-region audio track found.")
    return
  end

  print("Source: " .. source_track:name() .. " / " .. source_region:name())

  -- Ensure we have an AudioRegion
  local audio_src = source_region:to_audioregion()
  if audio_src:isnil() then
    print("ERROR: The single region on the track is not an audio region (likely MIDI).")
    return
  end

  local sr = Session:nominal_sample_rate()
  local slice_samp = math.floor(cfg.slice_duration * sr)

  ---------------------------------------------------------------------
  -- Onset Detection ---------------------------------------------------
  ---------------------------------------------------------------------
  local onset = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-onsetdetector", sr)
  onset:plugin():setParameter("dftype", 3)
  onset:plugin():setParameter("sensitivity", 50)
  onset:plugin():setParameter("whiten", 0)

  local onsets = {}
  local function cb(feats)
    local fl = feats:table()[0]
    if fl then
      for f in fl:iter() do
        if f.hasTimestamp then
          local frame = Vamp.RealTime.realTime2Frame(f.timestamp, sr)
          table.insert(onsets, frame)
          print(string.format("Onset @ %.3fs", frame / sr))
        end
      end
    end
    return false
  end
  onset:analyze(audio_src:to_readable(), 0, cb)
  cb(onset:plugin():getRemainingFeatures())
  onset:reset()
  if #onsets == 0 then print("No onsets detected.") return end

  ---------------------------------------------------------------------
  -- Slice feature extraction (RMS & ZCR) ------------------------------
  ---------------------------------------------------------------------
  local rd = audio_src:to_readable()
  local shm = ARDOUR.DSP.DspShm(slice_samp)
  local buf = shm:to_float(0)

  local hits = {}
  for _, frame in ipairs(onsets) do
    if frame + slice_samp <= rd:readable_length() then
      rd:read(buf, frame, slice_samp, 0)
      local arr = buf:array()
      local sum, zc, prev = 0, 0, arr[1]
      for i = 1, slice_samp do
        local v = arr[i]
        sum = sum + v * v
        if (v <= 0 and prev > 0) or (v > 0 and prev <= 0) then zc = zc + 1 end
        prev = v
      end
      local rms = math.sqrt(sum / slice_samp)
      local zcr = zc / cfg.slice_duration
      table.insert(hits, {frame = frame, rms = rms, zcr = zcr})
    end
  end

  if #hits < cfg.group_count then cfg.group_count = #hits end
  if #hits == 0 then print("No valid slices.") return end

  ---------------------------------------------------------------------
  -- Normalise features & K-means clustering --------------------------
  ---------------------------------------------------------------------
  local min_rms, max_rms = math.huge, 0
  local min_z,   max_z   = math.huge, 0
  for _,h in ipairs(hits) do
    if h.rms < min_rms then min_rms = h.rms end
    if h.rms > max_rms then max_rms = h.rms end
    if h.zcr < min_z   then min_z   = h.zcr end
    if h.zcr > max_z   then max_z   = h.zcr end
  end
  local rng_rms = max_rms - min_rms + 1e-9
  local rng_z   = max_z   - min_z   + 1e-9

  local feats = {}
  for _,h in ipairs(hits) do
    h.nrms = (h.rms - min_rms) / rng_rms
    h.nz   = (h.zcr - min_z) / rng_z
    table.insert(feats, {h.nrms, h.nz})
  end

  local K = cfg.group_count
  local cent = {}
  for k=1,K do cent[k] = {feats[k][1], feats[k][2]} end
  local assign = {}
  local function d2(a,b) local dx=a[1]-b[1]; local dy=a[2]-b[2]; return dx*dx+dy*dy end
  for iter=1,10 do
    local changed=false
    -- assign
    for i,f in ipairs(feats) do
      local best,bd=1,d2(f,cent[1])
      for k=2,K do local dd=d2(f,cent[k]); if dd<bd then best,bd=k,dd end end
      if assign[i]~=best then assign[i]=best; changed=true end
    end
    -- recompute
    local sum,count={},{}
    for k=1,K do sum[k]={0,0}; count[k]=0 end
    for i,f in ipairs(feats) do local k=assign[i]; sum[k][1]=sum[k][1]+f[1]; sum[k][2]=sum[k][2]+f[2]; count[k]=count[k]+1 end
    for k=1,K do if count[k]>0 then cent[k][1]=sum[k][1]/count[k]; cent[k][2]=sum[k][2]/count[k] end end
    if not changed then break end
  end
  local groups={} for k=1,K do groups[k]={} end
  for i,h in ipairs(hits) do table.insert(groups[assign[i]], h) end

  ---------------------------------------------------------------------
  -- Select motif tones A & B -----------------------------------------
  ---------------------------------------------------------------------
  local order={} for k=1,K do table.insert(order,{k=k,r=cent[k][1]}) end
  table.sort(order,function(a,b) return a.r<b.r end)
  local toneA = order[1].k
  local toneB = order[ math.min(2,#order) ].k
  print(string.format("Tone A=cluster %d, B=cluster %d", toneA, toneB))

  ---------------------------------------------------------------------
  -- Build sequence ----------------------------------------------------
  ---------------------------------------------------------------------
  local seq={} math.randomseed(os.time())
  local step_beats = cfg.quantisation_beats
  local beat_dur = 60/cfg.default_bpm
  -- tempo estimate
  if #onsets>1 then local sum=0 for i=2,#onsets do sum=sum+((onsets[i]-onsets[i-1])/sr) end; beat_dur = (sum/(#onsets-1)) end
  local step_sec = beat_dur*step_beats

  local total_steps = #cfg.pattern_tokens*cfg.repeat_count
  for i=1,total_steps do
    local token = cfg.pattern_tokens[((i-1)%#cfg.pattern_tokens)+1]
    local grp = (token=="A") and toneA or toneB
    local pool=groups[grp]
    if #pool==0 then pool=hits end
    seq[i]=pool[ math.random(1,#pool) ]
  end

  ---------------------------------------------------------------------
  -- Prepare output track ---------------------------------------------
  ---------------------------------------------------------------------
  local out_tr
  for route in Session:get_routes():iter() do
    local t=route:to_track(); if not t:isnil() and t:name()==cfg.output_track_name then out_tr=t:to_audio_track() end
  end
  if not out_tr then
    local tl = Session:new_audio_track(1, 2, nil, 1, cfg.output_track_name,
                                       ARDOUR.PresentationInfo.max_order,
                                       ARDOUR.TrackMode.Normal, true)

    if tl == nil then
      print("ERROR: Session:new_audio_track returned nil — cannot create output track.")
      return
    end

    if tl:empty() then
      print("ERROR: Failed to create output track (RouteList empty).")
      return
    end

    -- Take the first route from the returned RouteList
    local first_route = tl:front()
    if first_route:isnil() then
      print("ERROR: Newly created RouteList does not contain a valid route.")
      return
    end

    out_tr = first_route:to_audio_track()
    if out_tr:isnil() then
      print("ERROR: Newly created route is not an audio track.")
      return
    end
  end
  local pl=out_tr:playlist()
  for r in pl:region_list():iter() do pl:remove_region(r) end

  ---------------------------------------------------------------------
  -- Placement ---------------------------------------------------------
  ---------------------------------------------------------------------
  local function lin(db) return 10^(db/20) end
  Session:begin_reversible_command("Generate Dundun Motif")
  pl:to_stateful():clear_changes()
  local t=0.0
  
  -- Get the source region's start offset into its audio file
  local src_start_offset = audio_src:start():samples()
  
  for i,hit in ipairs(seq) do
    local jitter=((cfg.humanise_timing_ms/1000)*(math.random()-0.5)*2)
    local pos_sec=math.max(0,t+jitter)
    local frm=math.floor(pos_sec*sr)
    local reg=ARDOUR.RegionFactory.clone_region(audio_src,true,true)
    if not reg:isnil() then
      -- Set the start position relative to the source audio file
      -- by adding the source region's offset to the hit frame
      reg:set_start(Temporal.timepos_t(src_start_offset + hit.frame))
      reg:set_length(Temporal.timecnt_t(slice_samp))
      local gdb=(cfg.humanise_gain_db*(math.random()-0.5)*2)
      pl:add_region(reg,Temporal.timepos_t(frm),lin(gdb),false)
      reg:set_name(string.format("hit_%03d",i))
    end
    t=t+step_sec
  end
  Session:add_stateful_diff_command(pl:to_statefuldestructible())
  Session:commit_reversible_command(nil)
  print("Placed " .. #seq .. " regions on '" .. cfg.output_track_name .. "'.")
end end

function icon(params) return function(ctx,w,h,fg)
  local txt=Cairo.PangoLayout(ctx,"ArdourMono "..math.ceil(w*.6).."px")
  txt:set_text("♪🥁♪")
  local tw,th=txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to(.5*(w-tw), .5*(h-th))
  txt:show_in_cairo_context(ctx)
end end 