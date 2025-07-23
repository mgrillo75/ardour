ardour {
  ["type"] = "EditorAction",
  name = "Loop Phrase From Intro",
  author = "AI Assistant",
  license = "MIT",
  description = [[
Detects a musically coherent phrase (bar) inside the region named "intro" (around 7–10 s),
then clones that phrase three times and appends the copies to the end of the region,
applying short cross-fades so the result sounds natural.
]]
}

function factory () return function ()

  ---------------------------------------------------------------------------
  -- USER CONFIGURATION
  ---------------------------------------------------------------------------
  local cfg = {
    region_name          = "intro", -- name of the source region
    approx_start_sec     = 7.19,     -- visual guess – used as seed only
    approx_end_sec       = 9.29,     -- visual guess – used as seed only
    clones               = 3,        -- number of extra repetitions to add
    fade_time_sec        = 0.03,     -- fade/cross-fade duration (seconds)
    beat_window_tolerance= 0.25      -- search ± this time around guess (seconds)
  }

  ---------------------------------------------------------------------------
  -- 1) Locate region "intro"
  ---------------------------------------------------------------------------
  local target_region = nil
  local target_playlist = nil
  local track_route = nil
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track:isnil() then
      local pl = track:playlist()
      for r in pl:region_list():iter() do
        if r:name() == cfg.region_name then
          target_region = r
          target_playlist = pl
          track_route = track
          break
        end
      end
    end
    if target_region then break end
  end
  if not target_region then
    print("ERROR: Region '" .. cfg.region_name .. "' not found!")
    return
  end

  local sr = Session:nominal_sample_rate()
  local region_start_samp = target_region:position():samples()
  local region_start_sec  = region_start_samp / sr

  ---------------------------------------------------------------------------
  -- 2) Beat analysis to find musically aligned phrase boundaries
  ---------------------------------------------------------------------------
  local approx_start = cfg.approx_start_sec
  local approx_end   = cfg.approx_end_sec

  -- Safety: ensure guesses fall inside region
  if approx_start < 0 then approx_start = 0 end
  if approx_end   > target_region:length():samples()/sr then
    approx_end = target_region:length():samples()/sr - 0.01
  end

  -- --- Beat analysis: convert to AudioRegion for readable
  local audio_reg = target_region:to_audioregion()
  if audio_reg:isnil() then
    print("ERROR: Target region is not an audio region; cannot analyze beats.")
    return
  end

  local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sr)
  beat_tracker:plugin():setParameter("Beats Per Bar", 4)

  local beat_times = {}
  local function beat_cb(feats)
    local fl = feats:table()[0]
    if fl then
      for f in fl:iter() do
        if f.hasTimestamp then
          local tm = Vamp.RealTime.realTime2Frame(f.timestamp, sr) / sr
          table.insert(beat_times, tm)
        end
      end
    end
    return false
  end

  beat_tracker:analyze(audio_reg:to_readable(), 0, beat_cb)
  beat_cb(beat_tracker:plugin():getRemainingFeatures())
  beat_tracker:reset()

  if #beat_times == 0 then
    print("ERROR: No beats detected in region. Aborting.")
    return
  end

  -- Find nearest beat >= approx_start and >= approx_end
  local phrase_start = nil
  local phrase_end   = nil
  for _, bt in ipairs(beat_times) do
    if not phrase_start and bt >= approx_start - cfg.beat_window_tolerance then
      phrase_start = bt
    end
    if bt >= approx_end - cfg.beat_window_tolerance then
      phrase_end = bt
      break
    end
  end
  -- Fallbacks if not found
  if not phrase_start then phrase_start = approx_start end
  if not phrase_end   then phrase_end   = approx_end   end
  if phrase_end <= phrase_start then
    phrase_end = phrase_start + (approx_end - approx_start)
  end

  local phrase_start_samples = region_start_samp + math.floor(phrase_start * sr)
  local phrase_end_samples   = region_start_samp + math.floor(phrase_end   * sr)

  local phrase_len_samples = phrase_end_samples - phrase_start_samples
  if phrase_len_samples <= 0 then
    print("ERROR: Phrase length invalid.")
    return
  end

  print(string.format("Phrase detected: %.3fs – %.3fs (%.3fs)", phrase_start, phrase_end, phrase_end-phrase_start))

  ---------------------------------------------------------------------------
  -- 3) Prepare undo and split to isolate phrase region
  ---------------------------------------------------------------------------
  Session:begin_reversible_command("Loop phrase from intro")
  target_playlist:to_stateful():clear_changes()

  -- Split at phrase boundaries
  local start_pos = Temporal.timepos_t(phrase_start_samples)
  local end_pos   = Temporal.timepos_t(phrase_end_samples)

  -- Split start
  target_playlist:split_region(target_region, start_pos)
  -- Obtain the region that now covers start_pos (topmost at that point)
  local phrase_mid_region = target_playlist:top_region_at(start_pos)
  if phrase_mid_region:isnil() then
    print("ERROR: Could not isolate phrase region after first split.")
    Session:abort_reversible_command()
    return
  end
  -- Split end within that region
  target_playlist:split_region(phrase_mid_region, end_pos)

  -- After second split, the phrase region is the one that starts at phrase_start_samples
  local phrase_region = nil
  for r in target_playlist:regions_at(start_pos):iter() do
    if r:position():samples() == phrase_start_samples and r:length():samples() == phrase_len_samples then
      phrase_region = r
      break
    end
  end
  if not phrase_region then
    print("ERROR: Could not identify final phrase region.")
    Session:abort_reversible_command()
    return
  end

  ---------------------------------------------------------------------------
  -- 4) Clone phrase region and append copies
  ---------------------------------------------------------------------------
  local fade_samples = math.floor(cfg.fade_time_sec * sr)
  -- Determine insertion position: after original region end
  local last_region_end = target_region:position():samples() + target_region:length():samples()
  local insert_pos = last_region_end

  for i = 1, cfg.clones do
    local clone = ARDOUR.RegionFactory.clone_region(phrase_region, true, true)
    if clone:isnil() then
      print("Failed to clone phrase region.")
      break
    end
    local pos_tp = Temporal.timepos_t(insert_pos)
    target_playlist:add_region(clone, pos_tp, 1.0, false)

    -- Apply fades for crossfade with previous audio
    clone:set_fade_in_length(Temporal.timecnt_t(fade_samples))
    clone:set_fade_in_shape(ARDOUR.FadeShape.Linear)
    clone:set_fade_out_length(Temporal.timecnt_t(fade_samples))
    clone:set_fade_out_shape(ARDOUR.FadeShape.Linear)

    -- Overlap to create crossfade
    clone:set_position(Temporal.timepos_t(insert_pos - fade_samples))

    insert_pos = insert_pos + phrase_len_samples
  end

  ---------------------------------------------------------------------------
  -- 5) Commit undo
  ---------------------------------------------------------------------------
  Session:add_stateful_diff_command(target_playlist:to_statefuldestructible())
  if not Session:abort_empty_reversible_command() then
    Session:commit_reversible_command(nil)
    print("\nPhrase duplicated and appended successfully!")
  else
    print("No changes made (nothing to undo)")
  end

end end 