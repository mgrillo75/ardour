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
      -- 2) Hard‐coded beat times from beatfinder.txt (seconds)
      --    We accent every other beat for a minimalist feel:
      --      • Downbeats (D♯) on 1st and 3rd beats of each group of four
      --      • Off-beats (C5) on 2nd and 4th beats
      --------------------------------------------------------------------------------
      local downbeats = {17.460, 18.427}          -- beatfinder: 17.460, 18.427
      local offbeats  = {17.946, 18.914}          -- beatfinder: 17.946, 18.914
  
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
          pl:add_region(clone, pos, 1.0, false)
        end
      end
  
      print("Minimalist accent inserted at fixed beats.")
    end
  end
  