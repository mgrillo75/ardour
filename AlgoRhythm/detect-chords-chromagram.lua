ardour {
  ["type"]   = "EditorAction",
  name        = "Detect Chords (Chromagram)",
  author      = "AI Assistant",
  license     = "MIT",
  description = [[
Detects chords in selected audio regions using the CQ Chromagram VAMP plugin.
Analyzes the chromagram (pitch class energy) to identify likely chords and
creates range markers with chord labels.

This works with the VAMP plugins available in your Ardour installation.

Usage:
  1. Select one or more audio regions in the editor.
  2. Run this script from Edit ▸ Lua Scripts ▸ Detect Chords (Chromagram).
]]
}

function factory () return function ()

  ------------------------------------------------------------
  -- Configuration
  ------------------------------------------------------------
  local cfg = {
    -- VAMP plugin for chromagram analysis
    vamp_id = "cqchromavamp",
    -- Minimum energy threshold for chord detection
    energy_threshold = 0.1,
    -- Minimum duration for a chord (seconds)
    min_chord_duration = 0.5,
    -- Color for chord markers
    colour = { r = 0.2, g = 0.8, b = 0.3, a = 0.8 },
  }

  -- Chord templates (major and minor triads)
  local chord_templates = {
    -- Major chords
    ["C"] = {1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0},
    ["C#"] = {0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0},
    ["D"] = {0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0},
    ["D#"] = {0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0},
    ["E"] = {0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1},
    ["F"] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0},
    ["F#"] = {0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0},
    ["G"] = {0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1},
    ["G#"] = {1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0},
    ["A"] = {0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0},
    ["A#"] = {0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0},
    ["B"] = {0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1},
    
    -- Minor chords
    ["Cm"] = {1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0},
    ["C#m"] = {0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0},
    ["Dm"] = {0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0},
    ["D#m"] = {0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0},
    ["Em"] = {0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1},
    ["Fm"] = {1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0},
    ["F#m"] = {0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0},
    ["Gm"] = {0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0},
    ["G#m"] = {0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1},
    ["Am"] = {1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0},
    ["A#m"] = {0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0},
    ["Bm"] = {0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1}
  }

  ------------------------------------------------------------
  -- Helper functions
  ------------------------------------------------------------
  local function colour_rgba (c)
    return ARDOUR.LuaAPI.rgba_to_color (c.r, c.g, c.b, c.a)
  end

  -- Calculate correlation between chromagram and chord template
  local function calculate_chord_correlation (chromagram, template)
    local correlation = 0
    local chroma_sum = 0
    local template_sum = 0
    
    for i = 1, 12 do
      correlation = correlation + (chromagram[i] or 0) * template[i]
      chroma_sum = chroma_sum + (chromagram[i] or 0)
      template_sum = template_sum + template[i]
    end
    
    -- Normalize
    if chroma_sum > 0 and template_sum > 0 then
      return correlation / math.sqrt(chroma_sum * template_sum)
    else
      return 0
    end
  end

  -- Find best matching chord for a chromagram
  local function identify_chord (chromagram)
    local best_chord = "N"
    local best_correlation = 0
    
    for chord_name, template in pairs(chord_templates) do
      local correlation = calculate_chord_correlation(chromagram, template)
      if correlation > best_correlation then
        best_correlation = correlation
        best_chord = chord_name
      end
    end
    
    return best_chord, best_correlation
  end

  local sel = Editor:get_selection ()
  if sel.regions:regionlist():size () == 0 then
    LuaDialog.Message ("Chord Detector", "Select one or more audio regions first", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
    return
  end

  local sr = Session:nominal_sample_rate ()
  local vamp = ARDOUR.LuaAPI.Vamp (cfg.vamp_id, sr)
  if vamp:isnil () then
    LuaDialog.Message ("Chord Detector", "Cannot load VAMP plugin: " .. cfg.vamp_id, LuaDialog.MessageType.Warning, LuaDialog.ButtonType.OK):run ()
    return
  end

  ------------------------------------------------------------
  -- Main processing
  ------------------------------------------------------------
  local add_undo = false
  Session:begin_reversible_command ("Detect Chords (Chromagram)")

  local ok, err = pcall (function ()
    for region in sel.regions:regionlist():iter () do
      local ar = region:to_audioregion ()
      if not ar:isnil () then
        local region_start = region:position():samples ()
        local chromagram_data = {}
        
        -- Analyze region with chromagram
        local callback = function(feats)
          local chroma_list = feats:table()[0]
          if chroma_list then
            for f in chroma_list:iter () do
              if f.hasTimestamp and f.values:size() >= 12 then
                local frame_time = Vamp.RealTime.realTime2Frame(f.timestamp, sr) / sr
                local chromagram = {}
                for i = 0, 11 do
                  chromagram[i + 1] = f.values[i]
                end
                table.insert(chromagram_data, {
                  time = frame_time,
                  chromagram = chromagram
                })
              end
            end
          end
          return false
        end

        vamp:analyze (ar:to_readable (), 0, callback)
        callback (vamp:plugin ():getRemainingFeatures ())
        vamp:reset ()

        -- Process chromagram data to detect chords
        local current_chord = nil
        local chord_start = 0
        local chord_count = 0
        
        for i, data in ipairs(chromagram_data) do
          local chord, correlation = identify_chord(data.chromagram)
          
          if correlation > cfg.energy_threshold then
            if chord ~= current_chord then
              -- End previous chord if it was long enough
              if current_chord and current_chord ~= "N" and 
                 (data.time - chord_start) >= cfg.min_chord_duration then
                
                local abs_start = region_start + (chord_start * sr)
                local abs_end = region_start + (data.time * sr)
                
                local loc = Session:new_location (
                  Temporal.timepos_t (abs_start),
                  Temporal.timepos_t (abs_end),
                  true, -- range marker
                  current_chord)
                loc:set_name (current_chord)
                loc:set_color (colour_rgba (cfg.colour))
                
                if not Session:add_stateful_diff_command (loc:to_statefuldestructible ()):empty () then
                  add_undo = true
                end
                
                chord_count = chord_count + 1
              end
              
              -- Start new chord
              current_chord = chord
              chord_start = data.time
            end
          end
        end
        
        -- Handle final chord
        if current_chord and current_chord ~= "N" and chromagram_data[#chromagram_data] then
          local final_time = chromagram_data[#chromagram_data].time
          if (final_time - chord_start) >= cfg.min_chord_duration then
            local abs_start = region_start + (chord_start * sr)
            local abs_end = region_start + (final_time * sr)
            
            local loc = Session:new_location (
              Temporal.timepos_t (abs_start),
              Temporal.timepos_t (abs_end),
              true, -- range marker
              current_chord)
            loc:set_name (current_chord)
            loc:set_color (colour_rgba (cfg.colour))
            
            if not Session:add_stateful_diff_command (loc:to_statefuldestructible ()):empty () then
              add_undo = true
            end
            
            chord_count = chord_count + 1
          end
        end
        
        print (string.format ("Region '%s': detected %d chords", region:name(), chord_count))
      end
    end
  end)

  ------------------------------------------------------------
  -- Finalize
  ------------------------------------------------------------
  if not ok then
    Session:abort_reversible_command ()
    LuaDialog.Message ("Chord Detector", "Error: " .. tostring (err), LuaDialog.MessageType.Error, LuaDialog.ButtonType.OK):run ()
    return
  end

  if add_undo then
    Session:commit_reversible_command (nil)
    LuaDialog.Message ("Chord Detector", "Chord detection complete! Check markers and console output.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
  else
    Session:abort_reversible_command ()
    LuaDialog.Message ("Chord Detector", "No chords detected above threshold.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
  end

  collectgarbage ()
end end

--------------------------------------------------------------
-- Toolbar icon
--------------------------------------------------------------
function icon (params) return function (ctx, w, h, fg)
  local txt = Cairo.PangoLayout (ctx, "ArdourMono " .. math.ceil (w * .6) .. "px")
  txt:set_text ("♪C")
  local tw, th = txt:get_pixel_size ()
  ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
  ctx:move_to (.5 * (w - tw), .5 * (h - th))
  txt:show_in_cairo_context (ctx)
end end 