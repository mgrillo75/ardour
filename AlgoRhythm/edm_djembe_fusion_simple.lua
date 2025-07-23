ardour {
  ["type"] = "EditorAction",
  name = "EDM-Djembe Fusion (Simple)",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Simplified version of the EDM-Djembe fusion script.
Places whole djembe regions without trimming for testing.
]]
}

function factory() return function()
  
  print("=== EDM-DJEMBE FUSION (SIMPLE VERSION) ===")
  
  -- Get all audio tracks
  local tracks = {}
  for route in Session:get_routes():iter() do
    local track = route:to_track()
    if not track:isnil() then
      local audio_track = track:to_audio_track()
      if not audio_track:isnil() then
        table.insert(tracks, audio_track)
      end
    end
  end
  
  if #tracks < 2 then
    print("ERROR: Need at least 2 audio tracks")
    return
  end
  
  -- First track is EDM, rest are djembe
  local edm_track = tracks[1]
  print("EDM Track: " .. edm_track:name())
  
  -- Create new track for fusion
  local new_track = Session:new_audio_track(1, 2, nil, 1, "Djembe Fusion Simple", 
                                            ARDOUR.PresentationInfo.max_order, 
                                            ARDOUR.TrackMode.Normal, true)
  
  if new_track:empty() then
    print("ERROR: Failed to create new track")
    return
  end
  
  local fusion_track = new_track:front():to_audio_track()
  local fusion_playlist = fusion_track:playlist()
  
  print("Created fusion track: " .. fusion_track:name())
  
  -- Begin undo operation
  Session:begin_reversible_command("Simple Djembe Fusion")
  
  -- Collect djembe regions from tracks 2 onwards
  local djembe_regions = {}
  for i = 2, math.min(#tracks, 4) do -- Limit to first 3 djembe tracks
    local track = tracks[i]
    print("\nChecking track: " .. track:name())
    
    local playlist = track:playlist()
    if not playlist:isnil() then
      for region in playlist:region_list():iter() do
        print("  Found region: " .. region:name())
        table.insert(djembe_regions, region)
        
        -- Only take first region from each track
        break
      end
    end
  end
  
  print(string.format("\nFound %d djembe regions to place", #djembe_regions))
  
  -- Place regions on fusion track
  local placement_time = 0
  local sample_rate = Session:nominal_sample_rate()
  
  for i, source_region in ipairs(djembe_regions) do
    print(string.format("\nPlacing region %d: %s", i, source_region:name()))
    
    -- Clone the region
    local new_region = ARDOUR.RegionFactory.clone_region(source_region, true, true)
    
    if not new_region:isnil() then
      -- Calculate position
      local position = Temporal.timepos_t(math.floor(placement_time * sample_rate))
      
      -- Add to playlist
      fusion_playlist:add_region(new_region, position, 1.0, false)
      
      print(string.format("  Placed at %.1f seconds", placement_time))
      
      -- Move to next position (2 seconds later)
      placement_time = placement_time + 2.0
    else
      print("  ERROR: Failed to clone region")
    end
  end
  
  -- Check final result
  local final_count = 0
  for r in fusion_playlist:region_list():iter() do
    final_count = final_count + 1
    print("  Final playlist contains: " .. r:name())
  end
  
  -- Commit changes
  Session:commit_reversible_command(nil)
  
  print(string.format("\n=== COMPLETE ==="))
  print(string.format("Fusion track should have %d regions", final_count))
  
  if final_count == 0 then
    print("\nTROUBLESHOOTING:")
    print("- Check if the djembe tracks have regions")
    print("- Try refreshing the editor view")
    print("- Check the Undo history")
  end
  
end end 