ardour {
  ["type"]   = "EditorAction",
  name        = "Detect Chords (Chordino)",
  author      = "AI Assistant",
  license     = "MIT",
  description = [[
Detects chords in the currently selected audio regions using the
"Chordino" VAMP plug-in (nnls-chroma).  For every detected chord the
script creates a coloured range marker with the chord label, perfectly
aligned to the audio so you get an instant chord lane inside Ardour.

Usage:
  1. Select one or more audio regions in the editor.
  2. Run this script from Edit ▸ Lua Scripts ▸ Detect Chords (Chordino).

Each region is analysed independently.  Existing range markers are left
untouched, so you can run the script repeatedly or on additional
regions without losing previous annotations.
]]
}

function factory () return function ()

  ------------------------------------------------------------
  -- Configuration
  ------------------------------------------------------------
  local cfg = {
    -- Full plugin ID.  Change if you have a different Chordino build.
    vamp_id          = "libardourvampplugins:nnls-chroma:chordino",
    -- Confidence threshold (0‒1).  Chords below this are ignored.
    confidence_min   = 0.1,
    -- If true, extend the marker to the next chord; otherwise use the
    -- duration field returned by the plugin (may be 0).
    span_to_next     = true,
    -- Colour (RGBA 0-1) for the chord markers.
    colour           = { r = 0.1, g = 0.6, b = 0.9, a = 0.8 },
  }

  ------------------------------------------------------------
  -- Helpers
  ------------------------------------------------------------
  local function colour_rgba (c)
    return ARDOUR.LuaAPI.rgba_to_color (c.r, c.g, c.b, c.a)
  end

  local sel = Editor:get_selection ()
  if sel.regions:regionlist():size () == 0 then
    LuaDialog.Message ("Chord Detector", "Select one or more audio regions first", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
    return
  end

  local sr = Session:nominal_sample_rate ()
  local vamp = ARDOUR.LuaAPI.Vamp (cfg.vamp_id, sr)
  if vamp:isnil () then
    LuaDialog.Message ("Chord Detector", "Cannot load VAMP plug-in: " .. cfg.vamp_id, LuaDialog.MessageType.Warning, LuaDialog.ButtonType.OK):run ()
    return
  end

  ------------------------------------------------------------
  -- Begin undo group
  ------------------------------------------------------------
  local add_undo = false
  Session:begin_reversible_command ("Detect Chords (Chordino)")

  local ok, err = pcall (function ()

  for region in sel.regions:regionlist():iter () do
    local ar = region:to_audioregion ()
    if ar:isnil () then goto next_region end

    local region_start = region:position():samples ()
    local chords = {} -- { {start, dur, label, conf} }

    -- Gather chords via callback
    local function cb (feats)
      local list = feats:table()[0]
      if list then
        for f in list:iter () do
          if f.hasTimestamp and f.label and f.label ~= "" then
            local frame = Vamp.RealTime.realTime2Frame (f.timestamp, sr)
            local dur   = (f.duration and f.duration:toFrame (sr)) or 0
            local conf  = f.values:size() > 0 and f.values[0] or 1.0
            table.insert (chords, {
              start = frame,
              dur   = dur,
              label = f.label,
              conf  = conf,
            })
          end
        end
      end
      return false
    end

    vamp:analyze (ar:to_readable (), 0, cb)
    cb (vamp:plugin ():getRemainingFeatures ())
    vamp:reset ()

    -- Build markers
    for i, ch in ipairs (chords) do
      if ch.conf >= cfg.confidence_min then
        local abs_start = region_start + ch.start
        local abs_end   = cfg.span_to_next and (
                            (chords[i+1] and (region_start + chords[i+1].start)) or
                            (abs_start + ch.dur)
                          ) or (abs_start + ch.dur)
        if abs_end <= abs_start then
          abs_end = abs_start + math.max (ch.dur, sr * 0.1) -- fallback 100ms
        end

        local loc = Session:new_location (
                      Temporal.timepos_t (abs_start),
                      Temporal.timepos_t (abs_end),
                      true, -- range marker
                      ch.label)
        loc:set_name (ch.label)
        loc:set_color (colour_rgba (cfg.colour))
        if not Session:add_stateful_diff_command (loc:to_statefuldestructible ()):empty () then
          add_undo = true
        end
      end
    end

    ::next_region::
  end

  ------------------------------------------------------------
  -- Commit / abort undo
  ------------------------------------------------------------
  end) -- end pcall

  if not ok then
    Session:abort_reversible_command ()
    LuaDialog.Message ("Chord Detector", "Error: " .. tostring (err), LuaDialog.MessageType.Error, LuaDialog.ButtonType.OK):run ()
    return
  end

  if add_undo then
    Session:commit_reversible_command (nil)
  else
    Session:abort_reversible_command ()
    LuaDialog.Message ("Chord Detector", "No chords above threshold were detected.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
  end

  collectgarbage ()
end end

--------------------------------------------------------------
-- Toolbar icon (simple ♯♭ symbol)
--------------------------------------------------------------
function icon (params) return function (ctx, w, h, fg)
  local txt = Cairo.PangoLayout (ctx, "ArdourMono " .. math.ceil (w * .5) .. "px")
  txt:set_text ("♯♭")
  local tw, th = txt:get_pixel_size ()
  ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
  ctx:move_to (.5 * (w - tw), .5 * (h - th))
  txt:show_in_cairo_context (ctx)
end end 