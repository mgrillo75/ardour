ardour {
    ["type"] = "EditorAction",
    name     = "Insert Granite Block Arrangement",
  }
  
  function factory()
    return function()
      local session = Session
      if session == nil then
        print("ERROR: Ardour's global 'Session' object was not found (is Lua nil).")
        print("Ensure the script is run from Ardour's designated script environment.")
        return
      end
  
      local session_is_usable_by_script = true -- Assume true initially
  
      print("--- BEGIN DEBUG INFO for 'session' object ---")
      print(string.format("Type of 'session' global: %s", type(Session)))
      print(string.format("Type of local 'session' variable: %s", type(session)))
  
      if type(session) == "table" then
        print("'session' is a Lua table. This is unexpected for the Ardour Session object.")
        print("Keys and value types in 'session' table:")
        for k, v in pairs(session) do
          print(string.format("  Key: %-25s Value Type: %s", tostring(k), type(v)))
        end
        session_is_usable_by_script = false
      elseif type(session) == "userdata" then
        print("'session' is userdata. This is expected for an Ardour C++ object.")
        -- Do not check metatable, just try to call methods with pcall
      else
        print(string.format("CRITICAL: 'session' is of an unexpected Lua type: %s", type(session)))
        session_is_usable_by_script = false
      end
      print("--- END DEBUG INFO for 'session' object ---")
  
      if not session_is_usable_by_script then
          print("FATAL SCRIPT ERROR: The 'Session' object provided by Ardour is not structured as expected by this script (see CRITICAL messages above). Cannot proceed.")
          return -- Stop script execution
      end
  
      -- This call is now only attempted if session_is_usable_by_script is true
      -- In the Scripting window, Session is usually always valid, so skip isnil check
      -- If you want, you can check for another method, e.g. nominal_sample_rate
      local ok, sr = pcall(function() return session:nominal_sample_rate() end)
      if not ok then
        print("ERROR: Failed to call session:nominal_sample_rate(). The Session object may not be valid in this context.")
        return
      end
      -- Now sr is your sample rate, and you can proceed
  
      --------------------------------------------------------------------------------
      -- 1) Locate hit‐tracks and prototype regions
      --------------------------------------------------------------------------------
      local track_C5, proto_C5
      local track_D_Sharp4, proto_D_Sharp4
      local track_F4, proto_F4
      local track_Fsharp4, proto_Fsharp4
      local track_Fsharp5, proto_Fsharp5
  
      local required_track_names = {
        "C5_1_hit", "D_Sharp4_1_hit", "F4_1_hit", "Fsharp_4_1_hit", "Fsharp5_1_hit"
      }
      local tracks = {
        C5_1_hit = {}, D_Sharp4_1_hit = {}, F4_1_hit = {},
        Fsharp_4_1_hit = {}, Fsharp5_1_hit = {}
      }
  
      for route in session:get_routes():iter() do
        local tr = route:to_track()
        if not tr:isnil() then
          local nm = tr:name()
          if tracks[nm] then
            local at = tr:to_audio_track()
            if not at:isnil() then
              tracks[nm].track = at
              for r in at:playlist():region_list():iter() do
                if r:name() == nm then -- Assuming prototype region has same name as track
                  tracks[nm].proto = r
                  break
                end
              end
            end
          end
        end
      end
  
      track_C5 = tracks["C5_1_hit"].track
      proto_C5 = tracks["C5_1_hit"].proto
      track_D_Sharp4 = tracks["D_Sharp4_1_hit"].track
      proto_D_Sharp4 = tracks["D_Sharp4_1_hit"].proto
      track_F4 = tracks["F4_1_hit"].track
      proto_F4 = tracks["F4_1_hit"].proto
      track_Fsharp4 = tracks["Fsharp_4_1_hit"].track
      proto_Fsharp4 = tracks["Fsharp_4_1_hit"].proto
      track_Fsharp5 = tracks["Fsharp5_1_hit"].track
      proto_Fsharp5 = tracks["Fsharp5_1_hit"].proto
  
      local missing_assets = false
      for _, name in ipairs(required_track_names) do
        if not tracks[name].track or not tracks[name].proto then
          print("ERROR: Missing track or prototype region for: " .. name)
          missing_assets = true
        end
      end
      if missing_assets then return end
  
      --------------------------------------------------------------------------------
      -- 2) Define the intricate arrangement for one measure and repetition logic
      --------------------------------------------------------------------------------
      local beat_times_for_measure_definition = {
        7.783,  -- M1, Beat 1
        8.267,  -- M1, Beat 2
        8.750,  -- M1, Beat 3
        9.236,  -- M1, Beat 4
        9.718   -- Start of M2 (defines end of M1)
      }
  
      local measure_start_abs = beat_times_for_measure_definition[1]
      local one_measure_duration = beat_times_for_measure_definition[5] - beat_times_for_measure_definition[1]
  
      -- Relative beat start times within the measure
      local rel_b = {}
      for i = 1, 4 do
        rel_b[i] = beat_times_for_measure_definition[i] - measure_start_abs
      end
  
      -- Durations of each of the 4 beats in the measure
      local d = {}
      d[1] = beat_times_for_measure_definition[2] - beat_times_for_measure_definition[1]
      d[2] = beat_times_for_measure_definition[3] - beat_times_for_measure_definition[2]
      d[3] = beat_times_for_measure_definition[4] - beat_times_for_measure_definition[3]
      d[4] = beat_times_for_measure_definition[5] - beat_times_for_measure_definition[4]
  
      -- Pattern definitions (relative times within the one measure)
      local c5_hits_rel = {
        rel_b[1],           -- Beat 1
        rel_b[2] + d[2] * 0.5, -- Beat 2&
        rel_b[4]            -- Beat 4
      }
      local dsharp4_hits_rel = {
        rel_b[1] + d[1] * 0.75, -- Beat 1a
        rel_b[3],           -- Beat 3
        rel_b[4] + d[4] * 0.5  -- Beat 4&
      }
      local f4_hits_rel = {
        rel_b[1] + d[1] * 0.5,  -- Beat 1+
        rel_b[2] + d[2] * 0.75, -- Beat 2a
        rel_b[3] + d[3] * 0.5,  -- Beat 3+
        rel_b[4] + d[4] * 0.75  -- Beat 4a
      }
      local fsharp4_hits_rel = {
        rel_b[2],           -- Beat 2
        rel_b[3] + d[3] * 0.75 -- Beat 3a
      }
      local fsharp5_hits_rel = {
        rel_b[1] + d[1] * 0.25, -- Beat 1e
        rel_b[3] + d[3] * 0.25, -- Beat 3e
        rel_b[4] + d[4] * 0.25  -- Beat 4e
      }
  
      local all_c5_times = {}
      local all_dsharp4_times = {}
      local all_f4_times = {}
      local all_fsharp4_times = {}
      local all_fsharp5_times = {}
  
      local num_repetitions = 4 -- How many times the one-measure pattern repeats
  
      for i = 0, num_repetitions - 1 do
        local current_measure_actual_start_time = measure_start_abs + (i * one_measure_duration)
        for _, rel_time in ipairs(c5_hits_rel) do table.insert(all_c5_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(dsharp4_hits_rel) do table.insert(all_dsharp4_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(f4_hits_rel) do table.insert(all_f4_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(fsharp4_hits_rel) do table.insert(all_fsharp4_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(fsharp5_hits_rel) do table.insert(all_fsharp5_times, current_measure_actual_start_time + rel_time) end
      end
        
      --------------------------------------------------------------------------------
      -- 3) Generic function to place hits
      --------------------------------------------------------------------------------
      local function place_hits(track, prototype, hit_times, track_name_for_error)
        if not track or not prototype then
          print("ERROR: Track or prototype nil for " .. track_name_for_error .. " in place_hits.")
          return
        end
        local pl = track:playlist()
        if pl:isnil() then
          print("ERROR: Playlist not found for " .. track_name_for_error)
          return
        end
        for _, t in ipairs(hit_times) do
          local pos = Temporal.timepos_t(math.floor(t * sr))
          local clone = ARDOUR.RegionFactory.clone_region(prototype, true, true)
          if clone:isnil() then
            print("ERROR: Failed to clone prototype for " .. track_name_for_error .. " at time " .. t)
          else
            pl:add_region(clone, pos, 1.0, false)
          end
        end
      end
  
      --------------------------------------------------------------------------------
      -- 4) Place all hits
      --------------------------------------------------------------------------------
      place_hits(track_C5, proto_C5, all_c5_times, "C5_1_hit")
      place_hits(track_D_Sharp4, proto_D_Sharp4, all_dsharp4_times, "D_Sharp4_1_hit")
      place_hits(track_F4, proto_F4, all_f4_times, "F4_1_hit")
      place_hits(track_Fsharp4, proto_Fsharp4, all_fsharp4_times, "Fsharp_4_1_hit")
      place_hits(track_Fsharp5, proto_Fsharp5, all_fsharp5_times, "Fsharp5_1_hit")
  
      print(num_repetitions .. " measure(s) of intricate granite block arrangement inserted.")
    end
  end