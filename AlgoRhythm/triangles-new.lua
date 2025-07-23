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
    local triangle_tracks_data = {} -- Store detailed track and region info
    
    for route in session:get_routes():iter() do
      local tr = route:to_track()
      if not tr:isnil() then
        local track_name = tr:name()
        -- print(string.format("Found track: '%s'", track_name)) -- Keep this for debugging if needed
        
        if string.lower(track_name):find("triangle") then
          print(string.format("  -> Triangle track detected: '%s'", track_name))
          local at = tr:to_audio_track()
          if not at:isnil() then
            -- Initialize with playlist and an empty list of regions
            triangle_tracks_data[track_name] = {track_obj = at, playlist_obj = at:playlist(), regions_list = {}}
            
            for r in at:playlist():region_list():iter() do
              local region_name = r:name()
              local region_id_str = "ID_RETRIEVAL_FAILED" -- Default if ID cannot be obtained

              if type(r.id) == "function" then
                local id_obj = r:id()
                if id_obj and type(id_obj.to_string) == "function" then
                  region_id_str = id_obj:to_string()
                else
                  if not id_obj then
                    print(string.format("    LUA_WARNING: r:id() returned nil for region '%s' on track '%s'.", region_name, track_name))
                  else
                    print(string.format("    LUA_WARNING: r:id():to_string() is not a function for region '%s' on track '%s'. Type of id_obj.to_string is %s.", region_name, track_name, type(id_obj.to_string)))
                  end
                end
              else
                print(string.format("    LUA_WARNING: r.id is not a function for region '%s' on track '%s'. Type of r.id is %s.", region_name, track_name, type(r.id)))
                if type(r) == "userdata" then
                    local mt = getmetatable(r)
                    if mt then
                        print(string.format("        LUA_DEBUG: Metatable for region '%s' found. mt.id type: %s, mt.name type: %s", region_name, type(mt.id), type(mt.name)))
                    else
                       print(string.format("        LUA_DEBUG: Metatable for region '%s' NOT found.", region_name))
                    end
                end
              end
              
              print(string.format("    Region in '%s': '%s' (ID: %s)", track_name, region_name, region_id_str))
              table.insert(triangle_tracks_data[track_name].regions_list, r) -- Store the actual region object
            end
          end
        end
      end
    end
    
    print("--- END DISCOVERY PHASE ---")
    
    local identified_track_names = {}
    for track_name, _ in pairs(triangle_tracks_data) do
      table.insert(identified_track_names, track_name)
    end
    
    if #identified_track_names == 0 then
      print("ERROR: No tracks containing 'triangle' in their name were found.")
      return
    end
    
    print(string.format("Found %d triangle track(s): %s", #identified_track_names, table.concat(identified_track_names, ", ")))

    --------------------------------------------------------------------------------
    -- 1) Identify specific triangle-400 and triangle-500 tracks and their regions
    --------------------------------------------------------------------------------
    local tri400_data = nil
    local tri500_data = nil
  
    for track_name, data in pairs(triangle_tracks_data) do
      if string.lower(track_name):find("400") then
        tri400_data = data
        print(string.format("Identified '%s' as triangle-400 track. It has %d regions.", track_name, #data.regions_list))
      elseif string.lower(track_name):find("500") then
        tri500_data = data
        print(string.format("Identified '%s' as triangle-500 track. It has %d regions.", track_name, #data.regions_list))
      end
    end

    local missing_data = false
    if not tri400_data then
      print("ERROR: Could not find/identify triangle track containing '400'.")
      missing_data = true
    end
    if not tri500_data then
      print("ERROR: Could not find/identify triangle track containing '500'.")
      missing_data = true
    end
    if missing_data then return end

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
  
      local num_repetitions = 6 -- Number of times the one-measure pattern repeats
  
      for i = 0, num_repetitions - 1 do
        local current_measure_actual_start_time = measure_start_abs + (i * one_measure_duration)
        for _, rel_time in ipairs(tri400_hits_rel) do table.insert(all_tri400_times, current_measure_actual_start_time + rel_time) end
        for _, rel_time in ipairs(tri500_hits_rel) do table.insert(all_tri500_times, current_measure_actual_start_time + rel_time) end
    end
      
    --------------------------------------------------------------------------------
    -- 3) Reposition existing regions according to the pattern
    --------------------------------------------------------------------------------
    local region_counters = {
      tri400 = 1, -- 1-based index for regions_list
      tri500 = 1
    }

    -- Temporarily remove regions from playlists before re-adding to avoid issues
    -- This is a common Ardour scripting pattern for moving regions reliably.
    local temp_region_storage = { tri400 = {}, tri500 = {} }

    if tri400_data and tri400_data.playlist_obj then
        for _, region_obj in ipairs(tri400_data.regions_list) do
            if tri400_data.playlist_obj:remove_region(region_obj, false) then -- false = don't delete source
                table.insert(temp_region_storage.tri400, region_obj)
            else
                print(string.format("Warning: Could not remove region %s from track 400 for repositioning.", region_obj:name()))
            end
        end
        tri400_data.regions_list = temp_region_storage.tri400 -- Update with successfully removed regions
    end
    if tri500_data and tri500_data.playlist_obj then
        for _, region_obj in ipairs(tri500_data.regions_list) do
            if tri500_data.playlist_obj:remove_region(region_obj, false) then
                table.insert(temp_region_storage.tri500, region_obj)
            else
                print(string.format("Warning: Could not remove region %s from track 500 for repositioning.", region_obj:name()))
            end
        end
        tri500_data.regions_list = temp_region_storage.tri500
    end

    print("Repositioning regions...")
    for i = 0, num_repetitions - 1 do
      local current_measure_actual_start_time = measure_start_abs + (i * one_measure_duration)

      -- Reposition for triangle-400 (on beats)
      for _, rel_time in ipairs(tri400_hits_rel) do
        if tri400_data and region_counters.tri400 <= #tri400_data.regions_list then
          local region_to_move = tri400_data.regions_list[region_counters.tri400]
          local target_pos_abs_samples = math.floor((current_measure_actual_start_time + rel_time) * sr)
          local target_timepos = Temporal.timepos_t(target_pos_abs_samples)
          
          -- Re-add region to playlist at new position
          tri400_data.playlist_obj:add_region(region_to_move, target_timepos, 1.0, false)
          print(string.format("Moved region '%s' (ID: %s) on tri-400 track to time %.3fs", 
            region_to_move:name(), region_to_move:id():to_string(), current_measure_actual_start_time + rel_time))
          region_counters.tri400 = region_counters.tri400 + 1
        else
          if i == 0 then print("Warning: Not enough regions on triangle-400 track for all planned hits.") end
          break -- Stop trying to place hits for this track in this measure if out of regions
        end
      end

      -- Reposition for triangle-500 (off-beats)
      for _, rel_time in ipairs(tri500_hits_rel) do
        if tri500_data and region_counters.tri500 <= #tri500_data.regions_list then
          local region_to_move = tri500_data.regions_list[region_counters.tri500]
          local target_pos_abs_samples = math.floor((current_measure_actual_start_time + rel_time) * sr)
          local target_timepos = Temporal.timepos_t(target_pos_abs_samples)

          tri500_data.playlist_obj:add_region(region_to_move, target_timepos, 1.0, false)
          print(string.format("Moved region '%s' (ID: %s) on tri-500 track to time %.3fs", 
            region_to_move:name(), region_to_move:id():to_string(), current_measure_actual_start_time + rel_time))
          region_counters.tri500 = region_counters.tri500 + 1
        else
          if i == 0 then print("Warning: Not enough regions on triangle-500 track for all planned hits.") end
          break
        end
      end
    end

    --------------------------------------------------------------------------------
    -- 4) Cleanup / Final Message
    --------------------------------------------------------------------------------
    print(num_repetitions .. " measure(s) of triangle regions repositioned.")
  end
end