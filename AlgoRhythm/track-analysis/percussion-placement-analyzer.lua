ardour { ["type"] = "EditorAction", name = "Percussion Placement Analyzer" }

function factory() return function()
    local sr = Session:nominal_sample_rate()
    local sel = Editor:get_selection()
    
    -- Initialize multiple VAMP plugins with error handling
    local rhythm_analyzer, energy_analyzer, spectral_analyzer, beat_tracker, percussion_detector
    
    local ok, err = pcall(function()
        rhythm_analyzer = ARDOUR.LuaAPI.Vamp("vamp:bbc-vamp-plugins:bbc-rhythm", sr)
    end)
    if not ok then print("Warning: BBC rhythm plugin not available: " .. tostring(err)) end
    
    ok, err = pcall(function()
        energy_analyzer = ARDOUR.LuaAPI.Vamp("vamp:bbc-vamp-plugins:bbc-energy", sr)
    end)
    if not ok then print("Warning: BBC energy plugin not available: " .. tostring(err)) end
    
    ok, err = pcall(function()
        spectral_analyzer = ARDOUR.LuaAPI.Vamp("vamp:bbc-vamp-plugins:bbc-intensity", sr)
    end)
    if not ok then print("Warning: BBC intensity plugin not available: " .. tostring(err)) end
    
    ok, err = pcall(function()
        beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sr)
    end)
    if not ok then print("Warning: QM beat tracker not available: " .. tostring(err)) end
    
    ok, err = pcall(function()
        percussion_detector = ARDOUR.LuaAPI.Vamp("libardourvampplugins:percussiononsets", sr)
    end)
    if not ok then print("Warning: Percussion onset detector not available: " .. tostring(err)) end
    
    -- Check if at least the essential plugins are available
    if not rhythm_analyzer and not beat_tracker then
        print("ERROR: Neither BBC rhythm analyzer nor QM beat tracker available. Cannot proceed.")
        return
    end
    
    -- Report available plugins
    print("\n=== Available Analysis Plugins ===")
    print("BBC Rhythm Analyzer: " .. (rhythm_analyzer and "YES" or "NO"))
    print("BBC Energy Analyzer: " .. (energy_analyzer and "YES" or "NO"))
    print("BBC Spectral Analyzer: " .. (spectral_analyzer and "YES" or "NO"))
    print("QM Beat Tracker: " .. (beat_tracker and "YES" or "NO"))
    print("Percussion Onset Detector: " .. (percussion_detector and "YES" or "NO"))
    print("")
    
    -- Configure plugins (only if available)
    if rhythm_analyzer then
        rhythm_analyzer:plugin():setParameter("min_bpm", 60)
        rhythm_analyzer:plugin():setParameter("max_bpm", 180)
    end
    if energy_analyzer then
        energy_analyzer:plugin():setParameter("threshold", 0.5)
    end
    if spectral_analyzer then
        spectral_analyzer:plugin():setParameter("numBands", 4)
    end
    
    for r in sel.regions:regionlist():iter() do
        local ar = r:to_audioregion()
        if ar:isnil() then goto next end
        
        -- Collect analysis data
        local analysis = {
            onsets = {},
            beats = {},
            energy_dips = {},
            spectral_gaps = {},
            rhythm_strength = 0,
            placement_suggestions = {}
        }
        
        -- 1. Rhythm Analysis
        local rhythm_callback = function(feats)
            -- Get rhythm strength (index 5)
            local strength_output = feats:table()[5]
            if strength_output and strength_output:size() > 0 then
                local f = strength_output:at(0)
                if f.values and f.values:size() > 0 then
                    analysis.rhythm_strength = f.values:at(0)
                end
            end
            
            -- Get onsets (index 3)
            local onset_output = feats:table()[3]
            if onset_output then
                for f in onset_output:iter() do
                    if f.hasTimestamp then
                        local time = Vamp.RealTime.realTime2Frame(f.timestamp, sr) / sr
                        table.insert(analysis.onsets, time)
                    end
                end
            end
            return false
        end
        
        -- 2. Energy Analysis
        local energy_callback = function(feats)
            -- Track energy dips
            local dip_output = feats:table()[4] -- pdip output
            if dip_output then
                for f in dip_output:iter() do
                    if f.hasTimestamp and f.values:at(0) > 0.5 then
                        local time = Vamp.RealTime.realTime2Frame(f.timestamp, sr) / sr
                        table.insert(analysis.energy_dips, time)
                    end
                end
            end
            return false
        end
        
        -- 3. Beat tracking callback
        local beat_callback = function(feats)
            -- Get beats
            local beat_output = feats:table()[0] -- beats output
            if beat_output then
                for f in beat_output:iter() do
                    if f.hasTimestamp then
                        local time = Vamp.RealTime.realTime2Frame(f.timestamp, sr) / sr
                        table.insert(analysis.beats, time)
                    end
                end
            end
            return false
        end
        
        -- Helper function to find nearest beat
        function find_nearest_beat(time, beats)
            if #beats == 0 then return time end
            
            local nearest = beats[1]
            local min_distance = math.abs(time - beats[1])
            
            for _, beat in ipairs(beats) do
                local distance = math.abs(time - beat)
                if distance < min_distance then
                    min_distance = distance
                    nearest = beat
                end
            end
            
            return nearest
        end
        
        -- 3. Find placement opportunities
        function find_placement_points(analysis, region_length)
            local suggestions = {}
            local max_suggestions = 50  -- Limit total suggestions
            local min_spacing = 2.0     -- Minimum seconds between suggestions
            
            -- Strategy 1: Fill energy dips that fall on beats
            for _, dip_time in ipairs(analysis.energy_dips) do
                local nearest_beat = find_nearest_beat(dip_time, analysis.beats)
                if math.abs(nearest_beat - dip_time) < 0.05 then
                    -- Check if there's already an onset here
                    local has_onset = false
                    for _, onset in ipairs(analysis.onsets) do
                        if math.abs(onset - nearest_beat) < 0.05 then
                            has_onset = true
                            break
                        end
                    end
                    
                    if not has_onset then
                        table.insert(suggestions, {
                            time = nearest_beat,
                            priority = "high",
                            reason = "energy_dip_on_beat",
                            suggested_type = "light_percussion"
                        })
                    end
                end
            end
            
            -- Strategy 2: Add sparse off-beat percussion in sections without onsets
            if #analysis.onsets == 0 or analysis.rhythm_strength < 0.5 then
                -- Identify gaps without onsets
                local onset_gaps = {}
                
                if #analysis.onsets == 0 then
                    -- No onsets at all - consider the whole region
                    table.insert(onset_gaps, {start_time = 0, end_time = region_length})
                else
                    -- Find gaps between onsets
                    table.sort(analysis.onsets)
                    
                    -- Check start
                    if analysis.onsets[1] > 4.0 then
                        table.insert(onset_gaps, {start_time = 0, end_time = analysis.onsets[1]})
                    end
                    
                    -- Check between onsets
                    for i = 1, #analysis.onsets - 1 do
                        local gap_start = analysis.onsets[i]
                        local gap_end = analysis.onsets[i + 1]
                        if gap_end - gap_start > 4.0 then  -- Only consider gaps > 4 seconds
                            table.insert(onset_gaps, {start_time = gap_start, end_time = gap_end})
                        end
                    end
                    
                    -- Check end
                    if region_length - analysis.onsets[#analysis.onsets] > 4.0 then
                        table.insert(onset_gaps, {start_time = analysis.onsets[#analysis.onsets], end_time = region_length})
                    end
                end
                
                -- Add suggestions in gaps, spaced appropriately
                for _, gap in ipairs(onset_gaps) do
                    local gap_duration = gap.end_time - gap.start_time
                    local num_suggestions = math.min(math.floor(gap_duration / 4), 8) -- Max 8 per gap
                    
                    for j = 1, num_suggestions do
                        local position = gap.start_time + (gap_duration / (num_suggestions + 1)) * j
                        
                        -- Find nearest off-beat position
                        local nearest_beat = find_nearest_beat(position, analysis.beats)
                        if nearest_beat > 0 then
                            -- Find the beat before and after
                            local beat_before, beat_after = nearest_beat, nearest_beat
                            for _, beat in ipairs(analysis.beats) do
                                if beat < position and beat > beat_before then
                                    beat_before = beat
                                elseif beat > position and beat < beat_after then
                                    beat_after = beat
                                end
                            end
                            
                            -- Place on the off-beat
                            local off_beat = (beat_before + beat_after) / 2
                            
                            -- Check spacing from other suggestions
                            local too_close = false
                            for _, existing in ipairs(suggestions) do
                                if math.abs(existing.time - off_beat) < min_spacing then
                                    too_close = true
                                    break
                                end
                            end
                            
                            if not too_close and #suggestions < max_suggestions then
                                table.insert(suggestions, {
                                    time = off_beat,
                                    priority = "medium",
                                    reason = "sparse_section",
                                    suggested_type = "shaker_or_hihat"
                                })
                            end
                        end
                    end
                end
            end
            
            -- Sort by time and limit
            table.sort(suggestions, function(a, b) return a.time < b.time end)
            
            -- Ensure minimum spacing and limit total
            local filtered = {}
            local last_time = -min_spacing
            for _, suggestion in ipairs(suggestions) do
                if suggestion.time - last_time >= min_spacing and #filtered < max_suggestions then
                    table.insert(filtered, suggestion)
                    last_time = suggestion.time
                end
            end
            
            return filtered
        end
        
        -- Run analyses (only for available plugins)
        if rhythm_analyzer then
            print("Analyzing rhythm...")
            rhythm_analyzer:analyze(ar:to_readable(), 0, rhythm_callback)
            rhythm_callback(rhythm_analyzer:plugin():getRemainingFeatures())
            rhythm_analyzer:reset()
        else
            -- Fallback: use built-in onset detector if BBC rhythm plugin not available
            if percussion_detector then
                print("Using percussion onset detector as fallback...")
                percussion_detector:plugin():setParameter("sensitivity", 40)
                
                local onset_fallback = function(feats)
                    local onset_output = feats:table()[0]
                    if onset_output then
                        for f in onset_output:iter() do
                            if f.hasTimestamp then
                                local time = Vamp.RealTime.realTime2Frame(f.timestamp, sr) / sr
                                table.insert(analysis.onsets, time)
                            end
                        end
                    end
                    return false
                end
                
                percussion_detector:analyze(ar:to_readable(), 0, onset_fallback)
                onset_fallback(percussion_detector:plugin():getRemainingFeatures())
                percussion_detector:reset()
                
                -- Estimate rhythm strength from onset density
                if #analysis.onsets > 0 then
                    local region_duration = r:length():samples() / sr
                    local onset_rate = #analysis.onsets / region_duration  -- onsets per second
                    -- Map onset rate to rhythm strength (0-1)
                    analysis.rhythm_strength = math.min(onset_rate / 4.0, 1.0)
                end
            end
        end
        
        if energy_analyzer then
            print("Analyzing energy...")
            energy_analyzer:analyze(ar:to_readable(), 0, energy_callback)
            energy_callback(energy_analyzer:plugin():getRemainingFeatures())
            energy_analyzer:reset()
        end
        
        if beat_tracker then
            print("Tracking beats...")
            beat_tracker:plugin():setParameter("bpb", 4) -- 4 beats per bar
            beat_tracker:analyze(ar:to_readable(), 0, beat_callback)
            beat_callback(beat_tracker:plugin():getRemainingFeatures())
            beat_tracker:reset()
        end
        
        -- Generate placement suggestions
        local region_length = r:length():samples() / sr
        analysis.placement_suggestions = find_placement_points(analysis, region_length)
        
        -- Output results
        print("\n=== Percussion Placement Analysis ===")
        print("Region: " .. r:name())
        print("Duration: " .. string.format("%.2f", r:length():samples() / sr) .. " seconds")
        print("Detected onsets: " .. #analysis.onsets)
        print("Detected beats: " .. #analysis.beats)
        print("Energy dips: " .. #analysis.energy_dips)
        print("Rhythm Strength: " .. string.format("%.2f", analysis.rhythm_strength))
        
        if #analysis.placement_suggestions > 0 then
            print("\nSuggested Percussion Placements:")
            for i, suggestion in ipairs(analysis.placement_suggestions) do
                print(string.format("  %d. Time: %.2fs, Type: %s, Priority: %s, Reason: %s", 
                    i, suggestion.time, suggestion.suggested_type, suggestion.priority, suggestion.reason))
            end
        else
            print("\nNo percussion placement suggestions - the track may already have sufficient rhythmic content.")
        end
        
        ::next::
    end
    
end end
