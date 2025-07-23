ardour {
  ["type"] = "EditorAction",
  name     = "Insert Woodblock Arrangement",
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
      local ok, sr = pcall(function() return session:nominal_sample_rate() end)
      if not ok then
        print("ERROR: Failed to call session:nominal_sample_rate(). The Session object may not be valid in this context.")
        return
      end

    --------------------------------------------------------------------------------
      -- 1) Locate hit‐tracks and prototype regions
    --------------------------------------------------------------------------------
      local track_wb_lo, proto_wb_lo
      local track_wb_mid, proto_wb_mid
      local track_wb_hi, proto_wb_hi
  
      local required_track_names = {
        "woodblocksingle-LO", "woodblocksingle-MID", "woodblocksingle-HI"
      }
      local tracks = {
        ["woodblocksingle-LO"] = {},
        ["woodblocksingle-MID"] = {},
        ["woodblocksingle-HI"] = {}
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
  
      track_wb_lo = tracks["woodblocksingle-LO"].track
      proto_wb_lo = tracks["woodblocksingle-LO"].proto
      track_wb_mid = tracks["woodblocksingle-MID"].track
      proto_wb_mid = tracks["woodblocksingle-MID"].proto
      track_wb_hi = tracks["woodblocksingle-HI"].track
      proto_wb_hi = tracks["woodblocksingle-HI"].proto
  
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
      -- Timings from Labels-1.txt (first 5 beats define 1 measure of 4 beats)
      local beat_times_for_measure_definition = {
        5.931,  -- M1, Beat 1
        6.422,  -- M1, Beat 2
        6.914,  -- M1, Beat 3
        7.406,  -- M1, Beat 4
        7.898   -- Start of M2 (defines end of M1)
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
      local wb_lo_hits_rel = {
        rel_b[1],                 -- On Beat 1
        rel_b[2] + d[2] * 0.5,    -- Mid-point of Beat 2 (2&)
        rel_b[3] + d[3] * 0.75,   -- Three-quarters through Beat 3 (3a)
        rel_b[4] + d[4] * 0.25    -- One-quarter through Beat 4 (4e)
      }
      local wb_mid_hits_rel = {
        rel_b[1] + d[1] * 0.25,   -- One-quarter through Beat 1 (1e)
        rel_b[1] + d[1] * 0.75,   -- Three-quarters through Beat 1 (1a)
        rel_b[2] + d[2] * 0.25,   -- One-quarter through Beat 2 (2e)
        rel_b[3] + d[3] * 0.5,    -- Mid-point of Beat 3 (3&)
        rel_b[4],                 -- On Beat 4
        rel_b[4] + d[4] * 0.75    -- Three-quarters through Beat 4 (4a)
      }
      local wb_hi_hits_rel = {
        rel_b[1] + d[1] * 0.5,    -- Mid-point of Beat 1 (1&)
        rel_b[2] + d[2] * 0.75,   -- Three-quarters through Beat 2 (2a)
        rel_b[3] + d[3] * 0.25,   -- One-quarter through Beat 3 (3e)
        rel_b[4] + d[4] * 0.5     -- Mid-point of Beat 4 (4&)
      }
  
      local all_wb_lo_times = {}
      local all_wb_mid_times = {}
      local all_wb_hi_times = {}
  
      local num_repetitions = 4 -- How many times the one-measure pattern repeats
  
      for i = 0, num_repetitions - 1 do
        local current_measure_actual_start_time = measure_start_abs + (i * one_measure_duration)
        for _, rel_time in ipairs(wb_lo_hits_rel) do table.insert(all_wb_lo_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(wb_mid_hits_rel) do table.insert(all_wb_mid_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(wb_hi_hits_rel) do table.insert(all_wb_hi_times, current_measure_actual_start_time + rel_time) end
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
      place_hits(track_wb_lo, proto_wb_lo, all_wb_lo_times, "woodblocksingle-LO")
      place_hits(track_wb_mid, proto_wb_mid, all_wb_mid_times, "woodblocksingle-MID")
      place_hits(track_wb_hi, proto_wb_hi, all_wb_hi_times, "woodblocksingle-HI")
  
      print(num_repetitions .. " measure(s) of intricate woodblock arrangement inserted.")
  end
end