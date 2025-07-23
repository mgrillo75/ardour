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
      local track_C5, track_D
      local proto_C5, proto_D
      for route in session:get_routes():iter() do
        local tr = route:to_track()
        if not tr:isnil() then
          local nm = tr:name()
          if nm == "C5_1_hit" or nm == "D_Sharp4_1_hit" then
            local at = tr:to_audio_track()
            if not at:isnil() then
              if nm == "C5_1_hit"       then track_C5 = at
              else                          track_D  = at
              end
              for r in at:playlist():region_list():iter() do
                if r:name() == nm then
                  if nm == "C5_1_hit"       then proto_C5 = r
                  else                          proto_D  = r
                  end
                  break
                end
              end
            end
          end
        end
      end
  
      if not track_C5 or not track_D or not proto_C5 or not proto_D then
        print("ERROR: Missing hit‐track or prototype region.")
        return
      end
  
      --------------------------------------------------------------------------------
      -- 2) Define a one-measure intricate pattern starting around 7s and repeat it
      --------------------------------------------------------------------------------
      -- Beats for the first measure (from beatfinder.txt, starting around 7.783s)
      local first_measure_beat_times = {7.783, 8.267, 8.750, 9.236}
      -- Duration of the 4-beat measure, based on time to the 5th beat (9.718s)
      local measure_duration = 9.718 - 7.783 
      local num_repeats = 4 -- Total number of times the measure pattern will play

      local downbeats = {} -- Will hold D♯ hit positions (times in seconds)
      local offbeats  = {} -- Will hold C5 hit positions (times in seconds)

      for i = 0, num_repeats - 1 do
        local current_measure_start_offset = i * measure_duration

        -- Pattern for D_Sharp4 (downbeats) within the current measure repetition
        -- Hit on the 1st beat of the measure
        table.insert(downbeats, first_measure_beat_times[1] + current_measure_start_offset)
        -- Hit on the 3rd beat of the measure
        table.insert(downbeats, first_measure_beat_times[3] + current_measure_start_offset)

        -- Pattern for C5 (offbeats) within the current measure repetition
        -- Hit on the 2nd beat
        table.insert(offbeats, first_measure_beat_times[2] + current_measure_start_offset)
        -- Quick succession hit shortly after the 2nd beat (60ms later)
        table.insert(offbeats, first_measure_beat_times[2] + current_measure_start_offset + 0.06)
        -- Anticipatory hit just before the 3rd beat (80ms before)
        table.insert(offbeats, first_measure_beat_times[3] + current_measure_start_offset - 0.08)
        -- Hit on the 4th beat
        table.insert(offbeats, first_measure_beat_times[4] + current_measure_start_offset)
      end
  
      --------------------------------------------------------------------------------
      -- 3) Place downbeats (D♯) into the D_Sharp4_1_hit track
      --------------------------------------------------------------------------------
      do
        local pl = track_D:playlist()
        for _, t in ipairs(downbeats) do
          local pos   = Temporal.timepos_t(math.floor(t * sr))
          local clone = ARDOUR.RegionFactory.clone_region(proto_D, true, true)
          pl:add_region(clone, pos, 1.0, false)
        end
      end
  
      --------------------------------------------------------------------------------
      -- 4) Place offbeats (C5) into the C5_1_hit track
      --------------------------------------------------------------------------------
      do
        local pl = track_C5:playlist()
        for _, t in ipairs(offbeats) do
          local pos   = Temporal.timepos_t(math.floor(t * sr))
          local clone = ARDOUR.RegionFactory.clone_region(proto_C5, true, true)
          -- Add velocity variation for more dynamic feel
          local vel = (t % 1 > 0.5) and 0.85 or 1.0
          pl:add_region(clone, pos, vel, false)
        end
      end
  
      print("Intricate repeating one-measure accent pattern inserted.")
    end
  end
  