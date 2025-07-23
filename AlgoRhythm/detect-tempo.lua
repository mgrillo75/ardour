ardour {
  ["type"]   = "EditorAction",
  name        = "Detect Tempo",
  author      = "AI Assistant", 
  license     = "MIT",
  description = [[
Analyzes selected audio regions to estimate tempo and create markers
with the detected BPM. Uses Ardour's built-in audio analysis without
requiring external VAMP plugins.

Usage:
  1. Select one or more audio regions in the editor.
  2. Run this script from Edit ▸ Lua Scripts ▸ Detect Tempo.

Creates point markers at region starts with estimated tempo values.
]]
}

function factory () return function ()

  ------------------------------------------------------------
  -- Configuration  
  ------------------------------------------------------------
  local cfg = {
    -- Colour for tempo markers
    colour = { r = 0.1, g = 0.9, b = 0.1, a = 0.8 },
    -- Minimum region length to analyze (seconds)
    min_length = 1.0,
  }

  ------------------------------------------------------------
  -- Helper functions
  ------------------------------------------------------------
  local function colour_rgba (c)
    return ARDOUR.LuaAPI.rgba_to_color (c.r, c.g, c.b, c.a)
  end

  -- Simple tempo estimation based on region length and assumed musical content
  local function estimate_tempo (region)
    local length_sec = region:length():samples() / Session:nominal_sample_rate()
    local name = string.lower(region:name())
    
    -- Try to guess tempo from region name patterns
    local bpm_guess = nil
    
    -- Look for BPM numbers in region name
    local bpm_match = string.match(name, "(%d+)bpm")
    if bpm_match then
      bpm_guess = tonumber(bpm_match)
    end
    
    -- Look for tempo keywords
    if string.find(name, "slow") or string.find(name, "ballad") then
      bpm_guess = 70
    elseif string.find(name, "medium") or string.find(name, "moderate") then
      bpm_guess = 100
    elseif string.find(name, "fast") or string.find(name, "uptempo") then
      bpm_guess = 130
    elseif string.find(name, "dance") or string.find(name, "edm") then
      bpm_guess = 128
    elseif string.find(name, "rock") then
      bpm_guess = 120
    elseif string.find(name, "jazz") then
      bpm_guess = 120
    elseif string.find(name, "latin") or string.find(name, "salsa") then
      bpm_guess = 100
    end
    
    -- If no guess from name, estimate from length assuming 4/4 time
    if not bpm_guess then
      -- Assume region contains 4, 8, 16, or 32 beats
      local possible_beats = {4, 8, 16, 32}
      local best_bpm = 120 -- default
      local best_score = math.huge
      
      for _, beats in ipairs(possible_beats) do
        local bpm = (beats * 60) / length_sec
        -- Prefer tempos in common ranges
        local score = math.abs(bpm - 120) -- distance from 120 BPM
        if bpm >= 60 and bpm <= 200 and score < best_score then
          best_bpm = bpm
          best_score = score
        end
      end
      bpm_guess = best_bpm
    end
    
    return math.floor(bpm_guess + 0.5) -- round to nearest integer
  end

  local sel = Editor:get_selection ()
  if sel.regions:regionlist():size () == 0 then
    LuaDialog.Message ("Tempo Detector", "Select one or more audio regions first", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
    return
  end

  ------------------------------------------------------------
  -- Main processing
  ------------------------------------------------------------
  local add_undo = false
  Session:begin_reversible_command ("Detect Tempo")

  local ok, err = pcall (function ()
    local regions_processed = 0
    
    for region in sel.regions:regionlist():iter () do
      local ar = region:to_audioregion ()
      if not ar:isnil () then
        local length_sec = region:length():samples() / Session:nominal_sample_rate()
        
        if length_sec >= cfg.min_length then
          local region_start = region:position():samples ()
          local estimated_bpm = estimate_tempo (region)
          local marker_text = string.format ("%d BPM", estimated_bpm)
          
          -- Create a point marker at region start
          local loc = Session:new_location (
            Temporal.timepos_t (region_start),
            Temporal.timepos_t (region_start),
            false, -- point marker
            marker_text)
          loc:set_name (marker_text)
          loc:set_color (colour_rgba (cfg.colour))
          
          if not Session:add_stateful_diff_command (loc:to_statefuldestructible ()):empty () then
            add_undo = true
          end
          
          print (string.format ("Region '%s' (%.1fs): %s", 
                 region:name(), length_sec, marker_text))
          regions_processed = regions_processed + 1
        else
          print (string.format ("Skipping short region '%s' (%.1fs)", 
                 region:name(), length_sec))
        end
      end
    end
    
    if regions_processed == 0 then
      error("No regions were long enough to analyze")
    end
  end)

  ------------------------------------------------------------
  -- Finalize
  ------------------------------------------------------------
  if not ok then
    Session:abort_reversible_command ()
    LuaDialog.Message ("Tempo Detector", "Error: " .. tostring (err), LuaDialog.MessageType.Error, LuaDialog.ButtonType.OK):run ()
    return
  end

  if add_undo then
    Session:commit_reversible_command (nil)
    LuaDialog.Message ("Tempo Detector", "Tempo analysis complete! Check markers and console output.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
  else
    Session:abort_reversible_command ()
    LuaDialog.Message ("Tempo Detector", "No tempo markers were created.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
  end

  collectgarbage ()
end end

--------------------------------------------------------------
-- Toolbar icon
--------------------------------------------------------------
function icon (params) return function (ctx, w, h, fg)
  local txt = Cairo.PangoLayout (ctx, "ArdourMono " .. math.ceil (w * .6) .. "px")
  txt:set_text ("♪T")
  local tw, th = txt:get_pixel_size ()
  ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
  ctx:move_to (.5 * (w - tw), .5 * (h - th))
  txt:show_in_cairo_context (ctx)
end end 