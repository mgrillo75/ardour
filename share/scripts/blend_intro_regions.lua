ardour {
	["type"] = "EditorAction",
	name = "Blend Intro Regions",
	author = "AI Assistant",
	license = "MIT",
	description = [[
Analyzes and blends regions 'intro.3' and 'intro.23' from track 'intro 1'.
Automatically trims excess silence/space from the front of the second region,
positions them for seamless musical transition, and applies crossfades.
]]
}

function factory() return function()

	---------------------------------------------------------------------------
	-- CONFIGURATION
	---------------------------------------------------------------------------
	local cfg = {
		track_name = "intro 1",        -- Target track name
		region1_name = "intro.3",      -- First region name
		region2_name = "intro.23",     -- Second region name
		crossfade_time_sec = 0.1,      -- Crossfade duration (seconds) - shorter for smoother transition
		silence_threshold = -60,       -- dB threshold for detecting silence
		min_trim_sec = 0.01,          -- Minimum trim amount (seconds)
		max_trim_sec = 2.0,           -- Maximum trim amount (seconds)
		beat_sync = true,             -- Try to align to beats if possible
		overlap_percentage = 0.1      -- Percentage of region1 to overlap for blend (deprecated)
	}

	---------------------------------------------------------------------------
	-- UTILITY FUNCTIONS
	---------------------------------------------------------------------------
	
	-- Find track by name
	local function find_track_by_name(name)
		for route in Session:get_routes():iter() do
			local track = route:to_track()
			if not track:isnil() and track:name() == name then
				return track
			end
		end
		return nil
	end
	
	-- Find region by name in playlist
	local function find_region_by_name(playlist, name)
		for r in playlist:region_list():iter() do
			if r:name() == name then
				return r
			end
		end
		return nil
	end
	
	-- Analyze region for silence/space at beginning using Readable:read()
	local function analyze_region_start(audio_region, sr, threshold_db)
		local readable = audio_region:to_readable()
		if readable:isnil() then
			return 0
		end

		local samples_per_analysis = 1024
		local region_length_samples = audio_region:length():samples()
		local max_samples_to_check = math.min(region_length_samples, cfg.max_trim_sec * sr)

		-- Threshold in linear amplitude
		local threshold_linear = 10 ^ (threshold_db / 20)
		local trim_point = 0

		-- Allocate shared memory buffer once
		local cmem = ARDOUR.DSP.DspShm(samples_per_analysis)
		local float_buf = cmem:to_float(0)

		-- Iterate over chunks from region start
		local start_sample = 0
		while start_sample < max_samples_to_check do
			local chunk_size = math.min(samples_per_analysis, max_samples_to_check - start_sample)
			local peak = 0

			-- Scan every channel for this chunk
			for chan = 0, audio_region:n_channels() - 1 do
				local read = readable:read(float_buf, start_sample, chunk_size, chan)
				if read > 0 then
					local arr = float_buf:array()
					for i = 1, read do -- Lua arrays are 1-based
						local sample_val = math.abs(arr[i])
						if sample_val > peak then
							peak = sample_val
						end
					end
				end
			end

			-- If this chunk is above threshold we found audio content
			if peak >= threshold_linear then
				trim_point = start_sample -- first non-silent sample
				break
			end

			start_sample = start_sample + chunk_size
		end

		-- Convert to seconds and clamp to limits
		local trim_sec = trim_point / sr
		trim_sec = math.max(cfg.min_trim_sec, math.min(trim_sec, cfg.max_trim_sec))
		return trim_sec
	end
	
	-- Apply beat detection for musical alignment
	local function find_beat_aligned_position(audio_region, position_sec, sr)
		if not cfg.beat_sync then
			return position_sec
		end
		
		local beat_tracker = ARDOUR.LuaAPI.Vamp("libardourvampplugins:qm-barbeattracker", sr)
		if not beat_tracker then
			print("Beat tracker not available, using exact position")
			return position_sec
		end
		
		beat_tracker:plugin():setParameter("Beats Per Bar", 4)
		
		local beat_times = {}
		local function beat_cb(feats)
			local fl = feats:table()[0]
			if fl then
				for f in fl:iter() do
					if f.hasTimestamp then
						local tm = Vamp.RealTime.realTime2Frame(f.timestamp, sr) / sr
						table.insert(beat_times, tm)
					end
				end
			end
			return false
		end
		
		beat_tracker:analyze(audio_region:to_readable(), 0, beat_cb)
		beat_cb(beat_tracker:plugin():getRemainingFeatures())
		beat_tracker:reset()
		
		-- Find closest beat to our target position
		local closest_beat = position_sec
		local min_distance = math.huge
		
		for _, beat_time in ipairs(beat_times) do
			local distance = math.abs(beat_time - position_sec)
			if distance < min_distance and distance < 0.5 then -- Within 0.5 seconds
				min_distance = distance
				closest_beat = beat_time
			end
		end
		
		return closest_beat
	end

	---------------------------------------------------------------------------
	-- MAIN EXECUTION
	---------------------------------------------------------------------------
	
	print("Starting intro region blending process...")
	
	-- Find target track
	local target_track = find_track_by_name(cfg.track_name)
	if not target_track then
		print("ERROR: Track '" .. cfg.track_name .. "' not found!")
		return
	end
	
	local playlist = target_track:playlist()
	local sr = Session:nominal_sample_rate()
	
	-- Find both regions
	local region1 = find_region_by_name(playlist, cfg.region1_name)
	local region2 = find_region_by_name(playlist, cfg.region2_name)
	
	if not region1 then
		print("ERROR: Region '" .. cfg.region1_name .. "' not found!")
		return
	end
	
	if not region2 then
		print("ERROR: Region '" .. cfg.region2_name .. "' not found!")
		return
	end
	
	-- Convert to audio regions; ensure they are valid
	local audio_region1 = region1:to_audioregion()
	local audio_region2 = region2:to_audioregion()

	if (audio_region1 == nil) or (audio_region2 == nil) or audio_region1:isnil() or audio_region2:isnil() then
		print("ERROR: One or both regions are not audio regions!")
		return
	end
	
	print("Found regions: " .. region1:name() .. " and " .. region2:name())
	
	-- PROFESSIONAL APPROACH: Keep region1 completely intact, position region2 to crossfade at the end
	local region1_start_pos = region1:position():samples()
	local region1_length = region1:length():samples()
	local region1_end_pos = region1_start_pos + region1_length
	
	print(string.format("Region1: %.3f to %.3f seconds (%.3f sec duration)", 
		region1_start_pos / sr, region1_end_pos / sr, region1_length / sr))
	print(string.format("Region2 original position: %.3f seconds", region2:position():samples() / sr))
	
	-- Begin undo-able operation
	Session:begin_reversible_command("Blend Intro Regions")
	playlist:to_stateful():clear_changes()
	
	-- Analyze region2 for trimming
	local trim_amount = analyze_region_start(audio_region2, sr, cfg.silence_threshold)
	print(string.format("Detected %.3f seconds of silence/space to trim from %s", trim_amount, region2:name()))
	
	local trim_samples = math.floor(trim_amount * sr)
	
	-- Calculate crossfade parameters
	local crossfade_samples = math.floor(cfg.crossfade_time_sec * sr)
	
	-- CORRECT APPROACH: Position region2 to start exactly at region1's end
	-- Then extend region1's fade-out and region2's fade-in to create the crossfade
	local new_region2_start = region1_end_pos
	
	-- For a proper crossfade, we need a small overlap - move region2 back slightly
	local minimal_overlap = math.floor(crossfade_samples / 2) -- Use half the crossfade time for overlap
	new_region2_start = region1_end_pos - minimal_overlap
	
	print(string.format("Positioning region2 to start at: %.3f seconds (%.3f sec overlap)", 
		new_region2_start / sr, minimal_overlap / sr))
	
	-- Apply beat alignment if enabled (adjust the junction point)
	local junction_sec = new_region2_start / sr
	local aligned_junction_sec = find_beat_aligned_position(audio_region1, junction_sec, sr)
	if math.abs(aligned_junction_sec - junction_sec) > 0.01 then
		new_region2_start = math.floor(aligned_junction_sec * sr)
		print(string.format("Beat-aligned junction: %.3f seconds", aligned_junction_sec))
	end
	
	print(string.format("Final region2 position: %.3f seconds", new_region2_start / sr))
	
	-- Create a copy of region2 for modification
	local region2_copy = ARDOUR.RegionFactory.clone_region(region2, true, true)
	if region2_copy:isnil() then
		print("ERROR: Failed to clone region2")
		Session:abort_reversible_command()
		return
	end
	
	-- Trim the front of region2_copy if needed
	if trim_samples > 0 then
		local new_start = region2_copy:start():samples() + trim_samples
		local new_length = region2_copy:length():samples() - trim_samples
		
		if new_length > 0 then
			region2_copy:set_start(Temporal.timepos_t(new_start))
			region2_copy:set_length(Temporal.timecnt_t(new_length))
			print(string.format("Trimmed %.3f seconds from front of %s", trim_amount, region2:name()))
		end
	end
	
	-- Position region2_copy for blending
	region2_copy:set_position(Temporal.timepos_t(new_region2_start))
	
	-- Add the modified region2 to playlist at a higher layer to avoid cutting off region1
	playlist:add_region(region2_copy, Temporal.timepos_t(new_region2_start), 1.0, false)
	
	-- Ensure region2 is on top layer for proper crossfading
	region2_copy:raise_to_top()
	
	-- Remove original region2 if it's different from the copy
	if region2:position():samples() ~= new_region2_start or trim_samples > 0 then
		playlist:remove_region(region2)
	end
	
	-- PROFESSIONAL CROSSFADE: Apply fades to overlapping regions
	-- Region1 gets fade-out for the overlap duration
	-- Region2 gets fade-in for the overlap duration  
	-- Both regions remain at their original positions, only fades are applied
	
	-- Set up crossfades on the overlapping portion
	local overlap_fade_samples = crossfade_samples
	
	-- Apply fade-out to region1 (at the END of region1, for the overlap duration)
	audio_region1:set_fade_out_length(overlap_fade_samples)
	audio_region1:set_fade_out_shape(ARDOUR.FadeShape.FadeSlow)
	audio_region1:set_fade_out_active(true)
	
	-- Apply fade-in to region2_copy (at the START of region2, for the overlap duration)
	local audio_region2_copy = region2_copy:to_audioregion()
	audio_region2_copy:set_fade_in_length(overlap_fade_samples)
	audio_region2_copy:set_fade_in_shape(ARDOUR.FadeShape.FadeFast)
	audio_region2_copy:set_fade_in_active(true)
	
	print(string.format("Applied gentle crossfades: Region1 slow fade-out, Region2 fast fade-in, both %.3f seconds", 
		overlap_fade_samples / sr))
	
	-- Commit the changes
	Session:add_stateful_diff_command(playlist:to_statefuldestructible())
	
	if not Session:abort_empty_reversible_command() then
		Session:commit_reversible_command(nil)
		print("\nRegion blending completed successfully!")
		print(string.format("Regions blended with %.3f second crossfade", cfg.crossfade_time_sec))
		print(string.format("Total overlap: %.3f seconds", crossfade_samples / sr))
		if trim_samples > 0 then
			print(string.format("Trimmed: %.3f seconds from second region", trim_amount))
		end
	else
		print("No changes were made")
	end

end end 