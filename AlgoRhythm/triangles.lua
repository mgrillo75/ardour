ardour {
  ["type"] = "EditorAction",
  name     = "Insert Triangle Arrangement",
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
    -- 0) Discovery Phase: Scan all tracks and regions to find triangle-related ones
    --------------------------------------------------------------------------------
    print("--- DISCOVERY PHASE: Scanning all tracks and regions ---")
    local triangle_tracks = {}
    
    for route in session:get_routes():iter() do
      local tr = route:to_track()
      if not tr:isnil() then
        local track_name = tr:name()
        print(string.format("Found track: '%s'", track_name))
        
        -- Check if this track name contains "triangle" (case-insensitive)
        if string.lower(track_name):find("triangle") then
          print(string.format("  -> Triangle track detected: '%s'", track_name))
          local at = tr:to_audio_track()
          if not at:isnil() then
            triangle_tracks[track_name] = {track = at, regions = {}}
            
            -- Scan regions in this triangle track
            for r in at:playlist():region_list():iter() do
              local region_name = r:name()
              print(string.format("    Region in '%s': '%s'", track_name, region_name))
              table.insert(triangle_tracks[track_name].regions, {name = region_name, region = r})
            end
          end
        end
      end
    end
    
    print("--- END DISCOVERY PHASE ---")
    
    -- Check if we found any triangle tracks
    local triangle_track_names = {}
    for track_name, _ in pairs(triangle_tracks) do
      table.insert(triangle_track_names, track_name)
    end
    
    if #triangle_track_names == 0 then
      print("ERROR: No tracks containing 'triangle' in their name were found.")
      return
    end
    
    print(string.format("Found %d triangle track(s): %s", #triangle_track_names, table.concat(triangle_track_names, ", ")))

    --------------------------------------------------------------------------------
      -- 1) Locate hit‐tracks and prototype regions
    --------------------------------------------------------------------------------
      local track_tri400, proto_tri400
      local track_tri500, proto_tri500
  
      -- Try to identify triangle-400 and triangle-500 tracks from discovered tracks
      for track_name, track_data in pairs(triangle_tracks) do
        if string.lower(track_name):find("400") then
          track_tri400 = track_data.track
          -- Use the first region as prototype
          if #track_data.regions > 0 then
            proto_tri400 = track_data.regions[1].region
            print(string.format("Using track '%s' as triangle-400 with prototype region '%s'", track_name, track_data.regions[1].name))
          end
        elseif string.lower(track_name):find("500") then
          track_tri500 = track_data.track
          -- Use the first region as prototype
          if #track_data.regions > 0 then
            proto_tri500 = track_data.regions[1].region
            print(string.format("Using track '%s' as triangle-500 with prototype region '%s'", track_name, track_data.regions[1].name))
          end
        end
      end

      local missing_assets = false
      if not track_tri400 or not proto_tri400 then
        print("ERROR: Could not find triangle track containing '400' or its prototype region")
        missing_assets = true
      end
      if not track_tri500 or not proto_tri500 then
        print("ERROR: Could not find triangle track containing '500' or its prototype region")
        missing_assets = true
      end
      if missing_assets then return end

    --------------------------------------------------------------------------------
      -- 2) Define the intricate arrangement for one measure and repetition logic
    --------------------------------------------------------------------------------
      -- Timings from swaying-sea.txt (first 5 beats define 1 measure of 4 beats)
      local beat_times_for_measure_definition = {
        30.041,  -- M1, Beat 1
        30.552,  -- M1, Beat 2
        31.051,  -- M1, Beat 3
        31.552,  -- M1, Beat 4
        32.052   -- Start of M2 (defines end of M1)
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
      local tri400_hits_rel = {
        rel_b[1],                 -- On Beat 1
        rel_b[2],                 -- On Beat 2
        rel_b[3],                 -- On Beat 3
        rel_b[4]                  -- On Beat 4
      }
      local tri500_hits_rel = {
        rel_b[1] + d[1] * 0.5,    -- Mid-point of Beat 1 (1&)
        rel_b[2] + d[2] * 0.5,    -- Mid-point of Beat 2 (2&)
        rel_b[3] + d[3] * 0.5,    -- Mid-point of Beat 3 (3&)
        rel_b[4] + d[4] * 0.5     -- Mid-point of Beat 4 (4&)
      }
  
      local all_tri400_times = {}
      local all_tri500_times = {}
  
      local num_repetitions = 6 -- Number of times the one-measure pattern repeats (based on image)
  
      for i = 0, num_repetitions - 1 do
        local current_measure_actual_start_time = measure_start_abs + (i * one_measure_duration)
        for _, rel_time in ipairs(tri400_hits_rel) do table.insert(all_tri400_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(tri500_hits_rel) do table.insert(all_tri500_times, current_measure_actual_start_time + rel_time) end
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
      place_hits(track_tri400, proto_tri400, all_tri400_times, "triangle-400")
      place_hits(track_tri500, proto_tri500, all_tri500_times, "triangle-500")
  
      print(num_repetitions .. " measure(s) of triangle arrangement inserted.")
  end
end