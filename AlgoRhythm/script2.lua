ardour {
  ["type"] = "EditorAction",
  name     = "Insert Minimalist Accent (Fixed Beats)",
}

function factory()
  return function()
    local session = Session
    local sr      = session:nominal_sample_rate()

    --------------------------------------------------------------------------------
    -- 1) Locate your existing hit‐tracks and prototype regions
    --------------------------------------------------------------------------------
    local track_C5, track_D, track_C5_clave2
    local proto_C5, proto_D, proto_C5_clave2
    for route in session:get_routes():iter() do
      local tr = route:to_track()
      if not tr:isnil() then
        local nm = tr:name()
        if nm == "C5_1_hit" or nm == "D_Sharp4_1_hit" or nm == "c5-clave2_1_hit" then
          local at = tr:to_audio_track()
          if not at:isnil() then
            if nm == "C5_1_hit"       then track_C5 = at
            elseif nm == "D_Sharp4_1_hit" then track_D  = at
            elseif nm == "c5-clave2_1_hit" then track_C5_clave2 = at
            end
            for r in at:playlist():region_list():iter() do
              if r:name() == nm then
                if nm == "C5_1_hit"       then proto_C5 = r
                elseif nm == "D_Sharp4_1_hit" then proto_D  = r
                elseif nm == "c5-clave2_1_hit" then proto_C5_clave2 = r
                end
                break
              end
            end
          end
        end
      end
    end

    if not track_C5 or not track_D or not proto_C5 or not proto_D or not track_C5_clave2 or not proto_C5_clave2 then
      print("ERROR: Missing one or more hit‐tracks or prototype regions (C5_1_hit, D_Sharp4_1_hit, c5-clave2_1_hit).")
      return
    end

    --------------------------------------------------------------------------------
    -- 2) Define and repeat two condensed 3-2/2-3 Clave patterns
    --------------------------------------------------------------------------------
    local original_clave_base_beats = {
      7.783,  -- M1, Beat 1
      8.267,  -- M1, Beat 2
      8.750,  -- M1, Beat 3
      9.236,  -- M1, Beat 4
      9.718,  -- M2, Beat 1 (5th beat of 8-beat cycle)
      10.206, -- M2, Beat 2 (6th)
      10.685, -- M2, Beat 3 (7th)
      11.171  -- M2, Beat 4 (8th)
    }

    local overall_start_time = original_clave_base_beats[1]
    -- Duration of the content of the original 8-beat sequence (from its first to its last beat)
    local original_content_duration = original_clave_base_beats[8] - original_clave_base_beats[1]

    local num_condensed_patterns = 2
    -- New calculation to set the start time of the second pattern:
    local target_start_time_for_second_pattern = 9.967 -- Desired start for the 2nd group
    -- 'condensed_pattern_content_duration' is used as the time offset from the start of the
    -- first pattern to the start of the second pattern.
    local condensed_pattern_content_duration = target_start_time_for_second_pattern - overall_start_time

    local all_d_sharp_clave_times = {} -- For D_Sharp4_1_hit (3-2 Clave)
    local all_c5_clave_times      = {} -- For C5_1_hit      (2-3 Clave)

    -- Calculate relative offsets of original beats from their start
    local original_relative_beat_offsets = {}
    for _, beat_abs_time in ipairs(original_clave_base_beats) do
      table.insert(original_relative_beat_offsets, beat_abs_time - overall_start_time)
    end

    for i = 0, num_condensed_patterns - 1 do
      local current_condensed_pattern_loop_start_offset = i * condensed_pattern_content_duration
      local current_condensed_pattern_actual_start_time = overall_start_time + current_condensed_pattern_loop_start_offset

      -- These are the 8 structural beat times for the *current condensed pattern*
      local condensed_base_beats_for_this_pattern = {}
      for _, original_rel_offset in ipairs(original_relative_beat_offsets) do
        -- Scale the original relative offset (halve it) and add to current pattern's actual start time
        local scaled_rel_offset = original_rel_offset / num_condensed_patterns
        table.insert(condensed_base_beats_for_this_pattern, current_condensed_pattern_actual_start_time + scaled_rel_offset)
      end

      -- Calculate 3-2 Son Clave for D_Sharp4 for this condensed pattern
      -- Hits: Beat 1, Beat 2&, Beat 4 (first measure of pattern) | Beat 2, Beat 3 (second measure of pattern)
      table.insert(all_d_sharp_clave_times, condensed_base_beats_for_this_pattern[1])
      table.insert(all_d_sharp_clave_times, condensed_base_beats_for_this_pattern[2] + (condensed_base_beats_for_this_pattern[3] - condensed_base_beats_for_this_pattern[2]) / 2)
      table.insert(all_d_sharp_clave_times, condensed_base_beats_for_this_pattern[4])
      table.insert(all_d_sharp_clave_times, condensed_base_beats_for_this_pattern[6]) -- Corresponds to beat 2 of the pattern's second measure
      table.insert(all_d_sharp_clave_times, condensed_base_beats_for_this_pattern[7]) -- Corresponds to beat 3 of the pattern's second measure

      -- Calculate 2-3 Son Clave for C5 for this condensed pattern
      -- Hits: Beat 2, Beat 3 (first measure of pattern) | Beat 1, Beat 2&, Beat 4 (second measure of pattern)
      table.insert(all_c5_clave_times, condensed_base_beats_for_this_pattern[2])
      table.insert(all_c5_clave_times, condensed_base_beats_for_this_pattern[3])
      table.insert(all_c5_clave_times, condensed_base_beats_for_this_pattern[5]) -- Corresponds to beat 1 of the pattern's second measure
      table.insert(all_c5_clave_times, condensed_base_beats_for_this_pattern[6] + (condensed_base_beats_for_this_pattern[7] - condensed_base_beats_for_this_pattern[6]) / 2)
      table.insert(all_c5_clave_times, condensed_base_beats_for_this_pattern[8]) -- Corresponds to beat 4 of the pattern's second measure
    end
      
    --------------------------------------------------------------------------------
    -- 3) Place D_Sharp4 hits (repeated 3-2 Clave)
    --------------------------------------------------------------------------------
    do
      local pl = track_D:playlist()
      for _, t in ipairs(all_d_sharp_clave_times) do
        local pos   = Temporal.timepos_t(math.floor(t * sr))
        local clone = ARDOUR.RegionFactory.clone_region(proto_D, true, true)
        pl:add_region(clone, pos, 1.0, false) -- Standard velocity for clave
      end
    end
      
    --------------------------------------------------------------------------------
    -- 4) Place C5 hits (repeated 2-3 Clave)
    --------------------------------------------------------------------------------
    do
      local pl = track_C5:playlist()
      for _, t in ipairs(all_c5_clave_times) do
        local pos   = Temporal.timepos_t(math.floor(t * sr))
        local clone = ARDOUR.RegionFactory.clone_region(proto_C5, true, true)
        pl:add_region(clone, pos, 1.0, false) -- Standard velocity for clave
      end
    end
      
    print("Two condensed 3-2 Clave (D_Sharp4) and 2-3 Clave (C5) patterns inserted.")

    --------------------------------------------------------------------------------
    -- 5) Define and calculate 2-3 Clave for new c5-clave2 track
    --------------------------------------------------------------------------------
    -- Beats for the new clave, starting around 9.28s (using 9.718s as the first beat)
    local new_clave_base_beats = {
      9.718,  -- New M1, Beat 1
      10.206, -- New M1, Beat 2
      10.685, -- New M1, Beat 3
      11.171, -- New M1, Beat 4
      11.655, -- New M2, Beat 1 (5th beat of this new 8-beat cycle)
      12.138, -- New M2, Beat 2 (6th)
      12.621, -- New M2, Beat 3 (7th)
      13.106  -- New M2, Beat 4 (8th)
    }

    local new_c5_clave2_hit_times = {}

    -- Calculate 2-3 Son Clave for the new c5-clave2 track
    -- Measure 1 (2-side): Beat 2, Beat 3
    table.insert(new_c5_clave2_hit_times, new_clave_base_beats[2])
    table.insert(new_c5_clave2_hit_times, new_clave_base_beats[3])
    -- Measure 2 (3-side): Beat 1, Beat 2&, Beat 4
    table.insert(new_c5_clave2_hit_times, new_clave_base_beats[5]) -- M2 Beat 1
    table.insert(new_c5_clave2_hit_times, new_clave_base_beats[6] + (new_clave_base_beats[7] - new_clave_base_beats[6]) / 2) -- M2 Beat 2&
    table.insert(new_c5_clave2_hit_times, new_clave_base_beats[8]) -- M2 Beat 4

    --------------------------------------------------------------------------------
    -- 6) Place new c5-clave2 hits (2-3 Clave)
    --------------------------------------------------------------------------------
    if track_C5_clave2 and proto_C5_clave2 then
      local pl = track_C5_clave2:playlist()
      for _, t in ipairs(new_c5_clave2_hit_times) do
        local pos   = Temporal.timepos_t(math.floor(t * sr))
        local clone = ARDOUR.RegionFactory.clone_region(proto_C5_clave2, true, true)
        pl:add_region(clone, pos, 1.0, false) -- Standard velocity for clave
      end
      print("New 2-3 Clave (c5-clave2) pattern inserted.")
    else
      print("ERROR: Could not insert c5-clave2 pattern, track or prototype region missing.") -- Should have been caught earlier
    end

  end
end