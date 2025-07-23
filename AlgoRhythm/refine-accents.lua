ardour {
    ["type"] = "EditorAction",
    name = "Refine Accents - Auto Align",
    license = "MIT",
    author = "AI Assistant",
    description = [[Automatically identify stem and accent tracks, then reposition accent regions to align with the arrangement]]
}

function factory()
    return function()

        -- Configuration
        local config = {
            -- Naming patterns for stem tracks (case-insensitive)
            stem_patterns = {
                "stem", "backing", "main", "base", "loop", "track", "instrumental", 
                "bass", "guitar", "piano", "synth", "vocal", "lead", "melody", "harmony"
            },
            -- Naming patterns for accent tracks (case-insensitive)  
            accent_patterns = {
                "accent", "percussion", "perc", "drums", "beat", "clap", "snap", "snare", 
                "kick", "hi", "cymbal", "bell", "triangle", "cowbell", "clave", "bongo", 
                "conga", "timbale", "shaker", "maraca", "tambourine", "wood", "rim"
            },
            -- Alignment settings
            beat_snap_threshold = 0.25, -- seconds - how close to a beat to snap
            min_region_gap = 0.05,      -- minimum gap between regions
            quantize_to_beat = true,     -- align to nearest beat
            debug_output = true          -- print debug information
        }

        -- Helper function to check if a string contains any of the patterns
        function contains_pattern(text, patterns)
            local lower_text = string.lower(text)
            for _, pattern in ipairs(patterns) do
                if string.find(lower_text, string.lower(pattern), 1, true) then
                    return true
                end
            end
            return false
        end

        -- Helper function to classify track type
        function classify_track(track_name)
            if contains_pattern(track_name, config.accent_patterns) then
                return "accent"
            elseif contains_pattern(track_name, config.stem_patterns) then
                return "stem"
            else
                return "unknown"
            end
        end

        -- Helper function to find beat positions in a region
        function find_beat_positions(region, sample_rate)
            local beats = {}
            
            -- Simple beat detection: assume 4/4 time and look for strong beats
            -- This is a simplified approach - in practice you might want to use 
            -- Ardour's built-in beat tracking or tempo map
            local region_length_sec = region:length():samples() / sample_rate
            local estimated_bpm = 120 -- default assumption
            local beat_duration = 60.0 / estimated_bpm
            
            -- Generate beat positions
            local beat_pos = 0
            while beat_pos < region_length_sec do
                table.insert(beats, beat_pos)
                beat_pos = beat_pos + beat_duration
            end
            
            return beats
        end

        -- Helper function to find the best alignment position
        function find_best_alignment(accent_region, stem_beats, sample_rate)
            local accent_start_sec = accent_region:position():samples() / sample_rate
            local best_position = accent_start_sec
            local min_distance = math.huge
            
            -- Find the closest beat to the current accent position
            for _, beat_time in ipairs(stem_beats) do
                local distance = math.abs(beat_time - accent_start_sec)
                if distance < min_distance and distance < config.beat_snap_threshold then
                    min_distance = distance
                    best_position = beat_time
                end
            end
            
            return best_position * sample_rate -- convert back to samples
        end

        -- Helper function to sort regions by position
        function sort_regions_by_position(regions)
            table.sort(regions, function(a, b)
                return a:position():samples() < b:position():samples()
            end)
        end

        -- Main execution
        print("=== Refine Accents - Auto Align ===")
        
        local sample_rate = Session:nominal_sample_rate()
        local tracks_processed = 0
        local regions_moved = 0
        local stem_tracks = {}
        local accent_tracks = {}
        
        -- Phase 1: Classify all tracks
        print("Phase 1: Analyzing tracks...")
        
        for route in Session:get_tracks():iter() do
            local track = route:to_track()
            
            if not track:isnil() then
                local track_name = track:name()
                local track_type = classify_track(track_name)
                
                if track_type == "stem" then
                    table.insert(stem_tracks, {track = track, name = track_name})
                    if config.debug_output then
                        print(string.format("  STEM: %s", track_name))
                    end
                elseif track_type == "accent" then
                    table.insert(accent_tracks, {track = track, name = track_name})
                    if config.debug_output then
                        print(string.format("  ACCENT: %s", track_name))
                    end
                else
                    if config.debug_output then
                        print(string.format("  UNKNOWN: %s", track_name))
                    end
                end
            end
        end
        
        print(string.format("Found %d stem tracks and %d accent tracks", 
              #stem_tracks, #accent_tracks))
        
        if #stem_tracks == 0 then
            print("ERROR: No stem tracks found. Cannot proceed with alignment.")
            return
        end
        
        if #accent_tracks == 0 then
            print("No accent tracks found. Nothing to align.")
            return
        end
        
        -- Phase 2: Analyze stem tracks to determine beat structure
        print("Phase 2: Analyzing beat structure from stem tracks...")
        
        local master_beats = {}
        local longest_stem_region = nil
        local longest_duration = 0
        
        -- Find the longest region in stem tracks to use as reference
        for _, stem_data in ipairs(stem_tracks) do
            local playlist = stem_data.track:playlist()
            for region in playlist:region_list():iter() do
                local duration = region:length():samples()
                if duration > longest_duration then
                    longest_duration = duration
                    longest_stem_region = region
                end
            end
        end
        
        if longest_stem_region then
            master_beats = find_beat_positions(longest_stem_region, sample_rate)
            print(string.format("Using region '%s' as beat reference (%d beats found)", 
                  longest_stem_region:name(), #master_beats))
        else
            print("ERROR: No regions found in stem tracks.")
            return
        end
        
        -- Phase 3: Reposition accent regions
        print("Phase 3: Repositioning accent regions...")
        
        -- Begin undo operation
        local add_undo = false
        Session:begin_reversible_command("Refine Accents - Auto Align")
        
        for _, accent_data in ipairs(accent_tracks) do
            local track = accent_data.track
            local track_name = accent_data.name
            local playlist = track:playlist()
            local regions = {}
            
            -- Collect all regions from this accent track
            for region in playlist:region_list():iter() do
                table.insert(regions, region)
            end
            
            -- Sort regions by position
            sort_regions_by_position(regions)
            
            print(string.format("Processing accent track '%s' (%d regions)", 
                  track_name, #regions))
            
            -- Reposition each region
            for i, region in ipairs(regions) do
                -- Prepare for undo operation
                region:to_stateful():clear_changes()
                
                local original_pos = region:position():samples()
                local new_pos = find_best_alignment(region, master_beats, sample_rate)
                
                -- Only move if there's a significant difference
                if math.abs(new_pos - original_pos) > (config.min_region_gap * sample_rate) then
                    region:set_position(Temporal.timepos_t(new_pos))
                    regions_moved = regions_moved + 1
                    
                    if config.debug_output then
                        print(string.format("    Moved region '%s': %.3fs -> %.3fs", 
                              region:name(), 
                              original_pos / sample_rate, 
                              new_pos / sample_rate))
                    end
                end
                
                -- Add to undo stack
                if not Session:add_stateful_diff_command(region:to_statefuldestructible()):empty() then
                    add_undo = true
                end
            end
            
            tracks_processed = tracks_processed + 1
        end
        
        -- Commit or abort the operation
        if add_undo then
            Session:commit_reversible_command(nil)
            print(string.format("SUCCESS: Processed %d accent tracks, moved %d regions", 
                  tracks_processed, regions_moved))
        else
            Session:abort_reversible_command()
            print("No changes were needed.")
        end
        
        print("=== Refine Accents - Complete ===")
        
        -- Cleanup
        collectgarbage()
    end
end

-- Icon for the toolbar (optional)
function icon(params) 
    return function(ctx, width, height, fg)
        local wh = math.min(width, height) * 0.5
        local center_x = width * 0.5
        local center_y = height * 0.5
        
        ctx:set_line_width(2)
        ctx:set_source_rgba(fg, fg, fg, 1)
        
        -- Draw a stylized waveform with accent marks
        ctx:move_to(center_x - wh, center_y)
        ctx:line_to(center_x - wh * 0.5, center_y - wh * 0.3)
        ctx:line_to(center_x, center_y)
        ctx:line_to(center_x + wh * 0.5, center_y + wh * 0.3)
        ctx:line_to(center_x + wh, center_y)
        ctx:stroke()
        
        -- Add accent marks
        ctx:arc(center_x - wh * 0.5, center_y - wh * 0.3, 3, 0, 2 * math.pi)
        ctx:fill()
        ctx:arc(center_x + wh * 0.5, center_y + wh * 0.3, 3, 0, 2 * math.pi)
        ctx:fill()
    end
end
