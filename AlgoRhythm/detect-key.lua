ardour {
  ["type"]   = "EditorAction",
  name        = "Detect Key",
  author      = "AI Assistant", 
  license     = "MIT",
  description = [[
Detects the musical key of selected audio regions using the built-in
QM Key Detector VAMP plugin. Creates a marker at the start of each
region with the detected key (e.g. "C major", "A minor").

Usage:
  1. Select one or more audio regions in the editor.
  2. Run this script from Edit ▸ Lua Scripts ▸ Detect Key.

Works with any audio content and uses plugins that should be available
in all Ardour installations.
]]
}

function factory () return function ()

  ------------------------------------------------------------
  -- Configuration  
  ------------------------------------------------------------
  local cfg = {
    -- VAMP plugin ID for key detection
    vamp_id = "libardourvampplugins:qm-keydetector",
    -- Minimum confidence threshold (0-1)
    confidence_min = 0.1,
    -- Colour for key markers
    colour = { r = 0.9, g = 0.6, b = 0.1, a = 0.8 },
  }

  ------------------------------------------------------------
  -- Helper functions
  ------------------------------------------------------------
  local function colour_rgba (c)
    return ARDOUR.LuaAPI.rgba_to_color (c.r, c.g, c.b, c.a)
  end

  local sel = Editor:get_selection ()
  if sel.regions:regionlist():size () == 0 then
    LuaDialog.Message ("Key Detector", "Select one or more audio regions first", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
    return
  end

  local sr = Session:nominal_sample_rate ()
  local vamp = ARDOUR.LuaAPI.Vamp (cfg.vamp_id, sr)
  if vamp:isnil () then
    LuaDialog.Message ("Key Detector", "Cannot load VAMP plugin: " .. cfg.vamp_id, LuaDialog.MessageType.Warning, LuaDialog.ButtonType.OK):run ()
    return
  end

  ------------------------------------------------------------
  -- Main processing
  ------------------------------------------------------------
  local add_undo = false
  Session:begin_reversible_command ("Detect Key")

  local ok, err = pcall (function ()
    for region in sel.regions:regionlist():iter () do
      local ar = region:to_audioregion ()
      if not ar:isnil () then
        local region_start = region:position():samples ()
        
        -- Analyze entire region for key
        local feats = vamp:analyseEntire (ar:to_readable ())
        local key_list = feats:table()[0]
        
        if key_list and not key_list:empty() then
          local best_key = key_list:front() -- Get strongest key estimate
          local key_name = best_key.label or "Unknown"
          local confidence = (best_key.values:size() > 0) and best_key.values[0] or 1.0
          
          if confidence >= cfg.confidence_min then
            -- Create a point marker at region start
            local loc = Session:new_location (
              Temporal.timepos_t (region_start),
              Temporal.timepos_t (region_start),
              false, -- point marker, not range
              key_name)
            loc:set_name (key_name)
            loc:set_color (colour_rgba (cfg.colour))
            
            if not Session:add_stateful_diff_command (loc:to_statefuldestructible ()):empty () then
              add_undo = true
            end
            
            print (string.format ("Region '%s': %s (confidence: %.2f)", 
                   region:name(), key_name, confidence))
          end
        end
        
        vamp:reset ()
      end
    end
  end)

  ------------------------------------------------------------
  -- Finalize
  ------------------------------------------------------------
  if not ok then
    Session:abort_reversible_command ()
    LuaDialog.Message ("Key Detector", "Error: " .. tostring (err), LuaDialog.MessageType.Error, LuaDialog.ButtonType.OK):run ()
    return
  end

  if add_undo then
    Session:commit_reversible_command (nil)
    LuaDialog.Message ("Key Detector", "Key detection complete! Check markers and console output.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
  else
    Session:abort_reversible_command ()
    LuaDialog.Message ("Key Detector", "No keys detected above confidence threshold.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
  end

  collectgarbage ()
end end

--------------------------------------------------------------
-- Toolbar icon
--------------------------------------------------------------
function icon (params) return function (ctx, w, h, fg)
  local txt = Cairo.PangoLayout (ctx, "ArdourMono " .. math.ceil (w * .6) .. "px")
  txt:set_text ("♪K")
  local tw, th = txt:get_pixel_size ()
  ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
  ctx:move_to (.5 * (w - tw), .5 * (h - th))
  txt:show_in_cairo_context (ctx)
end end 