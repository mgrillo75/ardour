ardour {
    ["type"] = "EditorAction",
    name = "Insert 2-3 Clave (Auto-Stretched)",
    author = "Miguel + Assistant",
    description = [[
      Extracts beats from 'main-track', computes average beat spacing,
      time-stretches 'rider-mambo-single' cowbell hit to match tempo,
      then inserts repeated 2–3 clave patterns.
    ]]
  }
  
  function factory() return function ()
    Session:begin_reversible_command("Insert 2-3 Clave")
  
    local MAIN_TRACK_NAME = "main-track"
    local COWBELL_TRACK_NAME = "rider-mambo-single"
    local CLAVE_TRACK_NAME = "clave-inserted"
    local START_TIME_S = 0.0
    local END_TIME_S   = 9.0
  
    local sample_rate = Session:nominal_sample_rate()
    local start_frame = math.floor(START_TIME_S * sample_rate)
    local end_frame   = math.floor(END_TIME_S * sample_rate)
  
    -- === Locate tracks ===
    local main_track, cowbell_track = nil, nil
    for route in Session:get_routes():iter() do
      local track = route:to_track()
      if not track:isnil() then
        if track:name() == MAIN_TRACK_NAME then
          main_track = track:to_audio_track()
        elseif track:name() == COWBELL_TRACK_NAME then
          cowbell_track = track:to_audio_track()
        end
      end
    end
    if not main_track or not cowbell_track then
      print("ERROR: Required tracks not found.")
      Session:abort_reversible_command()
      return
    end
  
    -- === Locate cowbell region ===
    local cowbell_region = nil
    for region in cowbell_track:playlist():region_list():iter() do
      local ar = region:to_audioregion()
      if not ar:isnil() then
        cowbell_region = ar
        break
      end
    end
    if not cowbell_region then
      print("ERROR: No region found in 'rider-mambo-single'")
      Session:abort_reversible_command()
      return
    end
  
    -- === Extract beats from main track ===
    local beat_frames = {}
    local vamp = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sample_rate)
    vamp:plugin():setParameter("Beats Per Bar", 4)
  
    for region in main_track:playlist():region_list():iter() do
      local ar = region:to_audioregion()
      if not ar:isnil() then
        local region_start = ar:position():samples()
        local function process(fs)
          if not fs then return end
          for _, fl in ipairs(fs:table()) do
            for f in fl:iter() do
              if f.hasTimestamp then
                local rel = Vamp.RealTime.realTime2Frame(f.timestamp, sample_rate)
                local abs = rel + region_start
                if abs >= start_frame and abs < end_frame then
                  table.insert(beat_frames, abs)
                end
              end
            end
          end
        end
        vamp:analyze(ar:to_readable(), 0, process)
        process(vamp:plugin():getRemainingFeatures())
        vamp:reset()
      end
    end
  
    local total_beats = #beat_frames
    if total_beats < 15 then
      print("ERROR: Not enough beats to place full clave pattern.")
      Session:abort_reversible_command()
      return
    end
  
    -- === Compute average inter-beat duration and stretch ratio ===
    local total_duration = beat_frames[#beat_frames] - beat_frames[1]
    local avg_beat_duration = total_duration / (total_beats - 1)
    
    -- Calculate the stretch ratio needed
    -- Assuming the cowbell hit is roughly one beat long at its original tempo
    local cowbell_length = cowbell_region:length():samples()
    local stretch_ratio = avg_beat_duration / cowbell_length
    
    print(string.format("Average beat duration: %.0f frames (~%.2f ms)", avg_beat_duration, avg_beat_duration / sample_rate * 1000))
    print(string.format("Cowbell region length: %d frames", cowbell_length))
    print(string.format("Stretch ratio: %.3f", stretch_ratio))
    
    -- === Time-stretch the cowbell region if needed ===
    local stretched_cowbell = cowbell_region
    
    -- Only stretch if the ratio is significantly different from 1.0
    if math.abs(stretch_ratio - 1.0) > 0.05 then
      print("Applying time-stretch to cowbell region...")
      
      -- Create Rubberband stretcher
      local rb = ARDOUR.LuaAPI.Rubberband(cowbell_region, true) -- true for percussive mode
      
      -- Set stretch parameters
      rb:set_strech_and_pitch(stretch_ratio, 1.0) -- stretch time, keep pitch
      
      -- Process the stretch
      local progress_dialog = LuaDialog.ProgressWindow("Time-stretching cowbell", true)
      function rb_progress(_, pos)
        return progress_dialog:progress(pos / cowbell_region:length():samples(), "Stretching")
      end
      
      stretched_cowbell = rb:process(rb_progress)
      progress_dialog:done()
      
      if stretched_cowbell:isnil() then
        print("ERROR: Failed to stretch cowbell region")
        Session:abort_reversible_command()
        return
      end
      
      print(string.format("Stretched cowbell length: %d frames", stretched_cowbell:length():samples()))
    else
      print("Stretch ratio close to 1.0, using original cowbell region")
    end
  
    -- === Create new clave track ===
    local new_tracks = Session:new_audio_track(
      2, 2, nil, 1, CLAVE_TRACK_NAME,
      ARDOUR.PresentationInfo.max_order,
      ARDOUR.TrackMode.Normal, true
    )
    local clave_track = new_tracks:front():to_audio_track()
    if clave_track:isnil() then
      print("ERROR: Failed to create clave track.")
      Session:abort_reversible_command()
      return
    end
  
    -----------------------------------------------------------------
    -- Place 2–3 son clave patterns derived from analysed beat grid --
    -----------------------------------------------------------------
    -- A single 2–3 clave spans two bars of 4/4 (8 quarter-note beats)
    -- with five strikes occurring at:
    --   • the ‘&’ of beat 2 (bar 1)
    --   • beat 4          (bar 1)
    --   • beat 1          (bar 2)
    --   • the ‘&’ of beat 2 (bar 2)
    --   • beat 3          (bar 2)
    -- Using the detected beat frames we compute these positions on-the-fly

    local function place_clave_pattern(start_idx)
      -- Ensure there are enough subsequent beats for a full pattern
      if (start_idx + 7) > total_beats then
        return false
      end

      local b = start_idx -- shorthand

      -- Helper to clone and place a region at a given frame position
      local function add_hit(frame_pos)
        local cloned = ARDOUR.RegionFactory.clone_region(stretched_cowbell, true, true)
        if cloned:isnil() then return end
        -- Ensure frame_pos is an integer
        local int_frame_pos = math.floor(frame_pos + 0.5) -- Round to nearest integer
        clave_track:playlist():add_region(cloned, Temporal.timepos_t(int_frame_pos), 1.0, false)
      end

      -------------------------------------------------------------
      -- Calculate the five hit positions (see diagram above)    --
      -------------------------------------------------------------
      -- 1) ‘&’ of beat 2 (mid-point between beats 2 and 3)
      add_hit((beat_frames[b+1] + beat_frames[b+2]) / 2)

      -- 2) Beat 4 (index b+3)
      add_hit(beat_frames[b+3])

      -- 3) Beat 1 of second bar (index b+4)
      add_hit(beat_frames[b+4])

      -- 4) ‘&’ of beat 2 (second bar) – mid-point between beats 6 and 7 overall
      add_hit((beat_frames[b+5] + beat_frames[b+6]) / 2)

      -- 5) Beat 3 (second bar) – index b+6
      add_hit(beat_frames[b+6])

      return true
    end

    local idx = 1
    local patterns_placed = 0
    while place_clave_pattern(idx) do
      idx = idx + 8 -- move ahead two bars (8 beats)
      patterns_placed = patterns_placed + 1
    end

    print(string.format("Inserted %d 2–3 clave pattern(s)", patterns_placed))

    Session:commit_reversible_command(nil)
    print("Clave pattern inserted successfully!")
  end end
