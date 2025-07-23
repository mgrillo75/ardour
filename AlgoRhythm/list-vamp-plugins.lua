ardour {
  ["type"]   = "EditorAction",
  name        = "List VAMP Plugins",
  author      = "AI Assistant", 
  license     = "MIT",
  description = [[
Lists all available VAMP plugins in the current Ardour installation.
This helps determine which audio analysis plugins are available for
use in other scripts.

Output is printed to the console (Window > Scripting).
]]
}

function factory () return function ()
  
  print("=== Available VAMP Plugins ===")
  
  local sr = Session:nominal_sample_rate()
  local plugin_count = 0
  
  -- List of common VAMP plugin IDs to test
  local test_plugins = {
    "libardourvampplugins:qm-keydetector",
    "libardourvampplugins:qm-chromagram", 
    "libardourvampplugins:qm-onsetdetector",
    "libardourvampplugins:qm-barbeattracker",
    "libardourvampplugins:qm-tempotracker",
    "libardourvampplugins:nnls-chroma:chordino",
    "libardourvampplugins:nnls-chroma:nnls-chroma",
    "qm-vamp-plugins:qm-keydetector",
    "qm-vamp-plugins:qm-chromagram",
    "qm-vamp-plugins:qm-onsetdetector",
    "qm-vamp-plugins:qm-barbeattracker",
    "qm-vamp-plugins:qm-tempotracker",
    "nnls-chroma:chordino",
    "nnls-chroma:nnls-chroma"
  }
  
  for _, plugin_id in ipairs(test_plugins) do
    local vamp = ARDOUR.LuaAPI.Vamp(plugin_id, sr)
    if not vamp:isnil() then
      print(string.format("✓ AVAILABLE: %s", plugin_id))
      plugin_count = plugin_count + 1
      vamp:reset()
    else
      print(string.format("✗ NOT FOUND: %s", plugin_id))
    end
  end
  
  print(string.format("\n=== Summary ==="))
  print(string.format("Found %d available VAMP plugins", plugin_count))
  
  if plugin_count == 0 then
    print("\nNo VAMP plugins found!")
    print("This means:")
    print("- Chord/key detection scripts won't work")
    print("- You need to install VAMP plugins separately")
    print("- Download from: https://code.soundsoftware.ac.uk/projects/vamp")
  else
    print("\nYou can use the available plugins in chord/key detection scripts.")
  end
  
  LuaDialog.Message ("VAMP Plugin List", 
    string.format("Found %d VAMP plugins. Check console for details.", plugin_count),
    LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run()

end end

function icon (params) return function (ctx, w, h, fg)
  local txt = Cairo.PangoLayout (ctx, "ArdourMono " .. math.ceil (w * .6) .. "px")
  txt:set_text ("?V")
  local tw, th = txt:get_pixel_size ()
  ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
  ctx:move_to (.5 * (w - tw), .5 * (h - th))
  txt:show_in_cairo_context (ctx)
end end 