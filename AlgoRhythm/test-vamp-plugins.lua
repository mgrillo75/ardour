ardour {
  ["type"]   = "EditorAction",
  name        = "Test VAMP Plugin IDs",
  author      = "AI Assistant",
  license     = "MIT",
  description = [[
Tests various VAMP plugin ID formats to find the correct syntax
for loading plugins on this system.
]]
}

function factory () return function ()
  
  print("=== Testing VAMP Plugin ID Formats ===")
  
  local sr = Session:nominal_sample_rate()
  
  -- List of plugin IDs to test in various formats
  local test_ids = {
    -- Direct IDs from the list
    "cqchromavamp",
    "cepstral-pitchtracker",
    "qm-barbeattracker",
    "beatroot",
    "percussiononsets",
    
    -- With vamp-plugins prefix
    "vamp-plugins:cqchromavamp",
    "vamp-plugins:cepstral-pitchtracker",
    "vamp-plugins:qm-barbeattracker",
    
    -- With library prefixes
    "qm-vamp-plugins:qm-barbeattracker",
    "cqvamp:cqchromavamp",
    "vamp-example-plugins:percussiononsets",
    
    -- Try some common variations
    "vamp:cqchromavamp",
    "vamp:cepstral-pitchtracker",
    
    -- Windows specific attempts
    "cqchromavamp.dll",
    "vamp-cqchromavamp",
    
    -- Based on the error messages, try the exact strings
    "libardourvampplugins:cqchromavamp",
    "libardourvampplugins:cepstral-pitchtracker",
  }
  
  local working_plugins = {}
  
  for _, plugin_id in ipairs(test_ids) do
    local vamp = ARDOUR.LuaAPI.Vamp(plugin_id, sr)
    if not vamp:isnil() then
      print(string.format("✓ SUCCESS: '%s' loaded!", plugin_id))
      table.insert(working_plugins, plugin_id)
      vamp:reset()
    else
      print(string.format("✗ FAILED: '%s'", plugin_id))
    end
  end
  
  print("\n=== Summary ===")
  if #working_plugins > 0 then
    print("Working plugin IDs:")
    for _, id in ipairs(working_plugins) do
      print("  " .. id)
    end
  else
    print("No working plugin IDs found!")
    print("\nThis might mean:")
    print("1. VAMP plugins are not installed in the expected location")
    print("2. Windows Ardour uses a different plugin loading mechanism")
    print("3. The plugins need to be installed separately")
  end
  
  -- Try to get more information
  print("\n=== System Info ===")
  print("Sample rate: " .. sr)
  print("Platform: Windows")
  
  LuaDialog.Message ("VAMP Test Results", 
    string.format("Tested %d plugin IDs, found %d working. Check console for details.", 
                  #test_ids, #working_plugins),
    LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run()

end end

function icon (params) return function (ctx, w, h, fg)
  local txt = Cairo.PangoLayout (ctx, "ArdourMono " .. math.ceil (w * .6) .. "px")
  txt:set_text ("?T")
  local tw, th = txt:get_pixel_size ()
  ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
  ctx:move_to (.5 * (w - tw), .5 * (h - th))
  txt:show_in_cairo_context (ctx)
end end 