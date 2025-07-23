ardour {
  ["type"]   = "EditorAction",
  name        = "Detect Key (Simple)",
  author      = "AI Assistant",
  license     = "MIT",
  description = [[
Simple key detection using the Cepstral Pitch Tracker. Analyzes the
fundamental frequency content to estimate the musical key of selected regions.

This uses only basic pitch analysis and works with the available VAMP plugins.

Usage:
  1. Select one or more audio regions in the editor.
  2. Run this script from Edit ▸ Lua Scripts ▸ Detect Key (Simple).
]]
}

function factory () return function ()

  ------------------------------------------------------------
  -- Configuration
  ------------------------------------------------------------
  local cfg = {
    -- VAMP plugin for pitch tracking
    vamp_id = "cepstral-pitchtracker",
    -- Color for key markers
    colour = { r = 0.9, g = 0.4, b = 0.1, a = 0.8 },
    -- Minimum region length to analyze (seconds)
    min_length = 2.0,
  }

  -- Note names for MIDI numbers
  local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

  ------------------------------------------------------------
  -- Helper functions
  ------------------------------------------------------------
  local function colour_rgba (c)
    return ARDOUR.LuaAPI.rgba_to_color (c.r, c.g, c.b, c.a)
  end

  -- Convert frequency to MIDI note number
  local function freq_to_midi (freq)
    if freq <= 0 then return nil end
    return 69 + 12 * math.log(freq / 440) / math.log(2)
  end

  -- Get note name from MIDI number
  local function midi_to_note (midi)
    if not midi then return "?" end
    local note_class = math.floor(midi) % 12
    return note_names[note_class + 1]
  end

  -- Analyze pitch data to estimate key
  local function estimate_key (pitch_data)
    if #pitch_data < 10 then return "Unknown" end
    
    -- Count occurrences of each pitch class
    local pitch_class_counts = {}
    for i = 0, 11 do
      pitch_class_counts[i] = 0
    end
    
    for _, freq in ipairs(pitch_data) do
      if freq > 0 then
        local midi = freq_to_midi(freq)
        if midi then
          local pitch_class = math.floor(midi) % 12
          pitch_class_counts[pitch_class] = pitch_class_counts[pitch_class] + 1
        end
      end
    end
    
    -- Find most common pitch class
    local max_count = 0
    local tonic = 0
    for i = 0, 11 do
      if pitch_class_counts[i] > max_count then
        max_count = pitch_class_counts[i]
        tonic = i
      end
    end
    
    -- Simple major/minor detection based on third
    local major_third = (tonic + 4) % 12
    local minor_third = (tonic + 3) % 12
    
    local major_score = pitch_class_counts[tonic] + pitch_class_counts[major_third] + pitch_class_counts[(tonic + 7) % 12]
    local minor_score = pitch_class_counts[tonic] + pitch_class_counts[minor_third] + pitch_class_counts[(tonic + 7) % 12]
    
    local key_name = note_names[tonic + 1]
    if minor_score > major_score then
      key_name = key_name .. "m"
    end
    
    return key_name
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
  Session:begin_reversible_command ("Detect Key (Simple)")

  local ok, err = pcall (function ()
    for region in sel.regions:regionlist():iter () do
      local ar = region:to_audioregion ()
      if not ar:isnil () then
        local length_sec = region:length():samples() / sr
        
        if length_sec >= cfg.min_length then
          local region_start = region:position():samples ()
          local pitch_data = {}
          
          -- Analyze region for pitch content
          local callback = function(feats)
            local pitch_list = feats:table()[0] -- f0 output
            if pitch_list then
              for f in pitch_list:iter () do
                if f.hasTimestamp and f.values:size() > 0 then
                  local freq = f.values[0]
                  if freq > 50 and freq < 2000 then -- reasonable frequency range
                    table.insert(pitch_data, freq)
                  end
                end
              end
            end
            return false
          end

          vamp:analyze (ar:to_readable (), 0, callback)
          callback (vamp:plugin ():getRemainingFeatures ())
          vamp:reset ()

          -- Estimate key from pitch data
          local estimated_key = estimate_key(pitch_data)
          
          if estimated_key ~= "Unknown" then
            -- Create point marker at region start
            local loc = Session:new_location (
              Temporal.timepos_t (region_start),
              Temporal.timepos_t (region_start),
              false, -- point marker
              estimated_key)
            loc:set_name (estimated_key)
            loc:set_color (colour_rgba (cfg.colour))
            
            if not Session:add_stateful_diff_command (loc:to_statefuldestructible ()):empty () then
              add_undo = true
            end
            
            print (string.format ("Region '%s' (%.1fs): %s", region:name(), length_sec, estimated_key))
          else
            print (string.format ("Region '%s': insufficient pitch data for key detection", region:name()))
          end
        else
          print (string.format ("Skipping short region '%s' (%.1fs)", region:name(), length_sec))
        end
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
    LuaDialog.Message ("Key Detector", "No keys detected.", LuaDialog.MessageType.Info, LuaDialog.ButtonType.OK):run ()
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