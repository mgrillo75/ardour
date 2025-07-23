ardour {
  ["type"] = "EditorAction",
  name = "Dundun Automatic Rhythm Generator",
  license = "MIT",
  author = "AI Assistant",
  description = [[
Automatically extract percussive hits from a solo dundun performance 
and generate a rhythmically structured, looping motif using tone-based 
grouping and quantized region placement.

This script analyzes a dundun recording to:
- Detect onsets (percussive hits)
- Extract and classify hits by tonal characteristics
- Generate rhythmic patterns using tone groups
- Place quantized regions on a new track

Based on dundun-specs.md
]]
}

function factory() return function()
  
  -- Configuration parameters (built-in defaults from dundun-specs.md)
  local config = {
    slice_duration = 0.5,      -- Duration of each hit region in seconds
    group_count = 4,           -- Total tonal clusters
    pattern = {1, 2, 2, 2, 1, 2, 2, 2, 1},  -- A B B B A B B B A pattern
    quantization = 0.5,        -- Quantization in beats (0.5 = 8th notes)
    repeat_count = 4,          -- Loop repetitions
    humanize_timing = 0.020,   -- ±20 ms timing variation
    humanize_gain = 2,         -- ±2 dB gain variation
    onset_threshold = 0.05,    -- Energy threshold for onset detection
    min_onset_interval = 0.1, -- Minimum time between onsets
    output_track_name = "generated-drum-track",
    extracted_track_name = "extracted-hits"
  }
  
  -- Get session and sample rate
  local session = Session
  local sample_rate = session:nominal_sample_rate()
  
  print("=== DUNDUN AUTOMATIC RHYTHM GENERATION ===")
  print("")
  print("I. INPUT STRUCTURE")
  print("------------------")
  
  -- Find the audio track with exactly one region (dundun recording)
  local source_track = nil
  local source_region = nil
  local track_count = 0
  local region_count = 0
  
  for route in session:get_routes():iter() do
    local track = route:to_track()
    if not track:isnil() then
      local audio_track = track:to_audio_track()
      if not audio_track:isnil() then
        track_count = track_count + 1
        local playlist = audio_track:playlist()
        local regions = playlist:region_list()
        
        if regions:size() == 1 then
          -- Found a track with exactly one region
          for r in regions:iter() do
            local ar = r:to_audioregion()
            if not ar:isnil() then
              source_track = audio_track
              source_region = ar
              region_count = region_count + 1
              print("Found source: Track '" .. track:name() .. "' with region '" .. r:name() .. "'")
              break
            end
          end
        end
      end
    end
  end
  
  if not source_region then
    print("ERROR: No audio track with exactly one region found.")
    print("Please ensure there is exactly one audio track with exactly one full-length audio region.")
    return
  end
  
  print("Region duration: " .. string.format("%.3f", source_region:length():samples() / sample_rate) .. " seconds")
  print("")
  
  -- === II. PROCESS PIPELINE ===
  print("II. PROCESS PIPELINE")
  print("--------------------")
  
  -- === 1. ONSET DETECTION ===
  print("\n1. Onset Detection")
  print("------------------")
  
  local function detect_onsets(region)
    local onsets = {}
    local readable = region:to_readable()
    
    if readable:isnil() then
      print("ERROR: Cannot read audio data from region")
      return onsets
    end
    
    -- Window size for energy calculation (10ms)
    local window_size = math.floor(sample_rate * 0.01)
    local hop_size = math.floor(window_size / 2)
    
    -- Read entire region in chunks and calculate energy
    local region_length = region:length():samples()
    local buffer_size = 8192
    local samples = ARDOUR.DSP.DspShm(buffer_size)
    
    -- Energy calculation
    local energy_curve = {}
    local position = 0
    
    print("Analyzing energy profile...")
    
    while position < region_length do
      local to_read = math.min(buffer_size, region_length - position)
      readable:read(samples:to_float(0), position, to_read, 0)
      
      -- Calculate energy for this buffer
      local float_array = samples:to_float(0):array()
      for i = 0, to_read - window_size, hop_size do
        local energy = 0
        for j = 0, window_size - 1 do
          local sample_val = float_array[j + i + 1] or 0
          energy = energy + sample_val * sample_val
        end
        energy = math.sqrt(energy / window_size)
        
        table.insert(energy_curve, {
          time = (position + i) / sample_rate,
          frame = position + i,
          energy = energy
        })
      end
      
      position = position + to_read
    end
    
    -- Find peaks in energy curve
    print("Detecting peaks...")
    local last_onset_time = -1
    
    for i = 2, #energy_curve - 1 do
      local prev = energy_curve[i - 1]
      local curr = energy_curve[i]
      local next = energy_curve[i + 1]
      
      -- Peak detection: current higher than neighbors and above threshold
      if curr.energy > prev.energy and 
         curr.energy > next.energy and 
         curr.energy > config.onset_threshold and
         (curr.time - last_onset_time) > config.min_onset_interval then
        
        table.insert(onsets, {
          time = curr.time,
          frame = curr.frame,
          energy = curr.energy
        })
        
        last_onset_time = curr.time
        print("Onset found at: " .. string.format("%.3f", curr.time) .. " seconds")
      end
    end
    
    print("Total onsets detected: " .. #onsets)
    return onsets
  end
  
  local onsets = detect_onsets(source_region)
  
  if #onsets < 2 then
    print("ERROR: Not enough onsets detected. Need at least 2 hits.")
    return
  end
  
  -- === 2. REGION EXTRACTION ===
  print("\n2. Region Extraction")
  print("--------------------")
  print("Slice duration: " .. config.slice_duration .. " seconds")
  
  local hit_slices = {}
  for i, onset in ipairs(onsets) do
    if i == 1 or (onset.time - onsets[i - 1].time) >= config.min_onset_interval then
      local slice = {
        index = i,
        onset_time = onset.time,
        onset_frame = onset.frame,
        duration = config.slice_duration,
        features = {},
        group_id = 0,
        hits = {onset}  -- Add the current onset to the hits field
      }
      table.insert(hit_slices, slice)
    end
  end
  print("Created " .. #hit_slices .. " grouped hit slice candidates")
  
  -- === 3. EXTRACTED HITS PLACEMENT ===
  print("\n3. Extracted Hits Placement")
  print("----------------------------")
  local extracted_track = nil
  for route in session:get_routes():iter() do
    local tr = route:to_track()
    if not tr:isnil() and tr:name() == config.extracted_track_name then
      extracted_track = tr:to_audio_track()
      break
    end
  end
  if not extracted_track or extracted_track:isnil() then
    print("Creating extracted hits track: " .. config.extracted_track_name)
    local track_list = session:new_audio_track(
      source_region:n_channels(),
      2,
      nil,
      1,
      config.extracted_track_name,
      ARDOUR.PresentationInfo.max_order,
      ARDOUR.TrackMode.Normal,
      true
    )
    if track_list and not track_list:empty() then
      local first_route = track_list:front()
      if not first_route:isnil() then
        extracted_track = first_route:to_audio_track()
      end
    end
    if not extracted_track or extracted_track:isnil() then
      print("ERROR: Could not create or access extracted hits track: " .. config.extracted_track_name)
    end
  end
  local extracted_playlist = extracted_track:playlist()
  extracted_playlist:to_stateful():clear_changes()
  local existing_extracted = {}
  for r in extracted_playlist:region_list():iter() do table.insert(existing_extracted, r) end
  for _, r in ipairs(existing_extracted) do extracted_playlist:remove_region(r) end
  session:begin_reversible_command("Dundun Extracted Hits")
  local source_start = source_region:start():samples()
  for _, slice in ipairs(hit_slices) do
    local frame_position = math.floor(slice.onset_time * sample_rate)
    local region_name = string.format("slice_%03d", slice.index)
    local new_region = ARDOUR.RegionFactory.clone_region(source_region, true, true)
    if not new_region:isnil() then
      new_region:set_start(Temporal.timepos_t(source_start + slice.onset_frame))
      new_region:set_length(Temporal.timecnt_t(math.floor(slice.duration * sample_rate)))
      new_region:set_name(region_name)
      extracted_playlist:add_region(new_region, Temporal.timepos_t(frame_position), 1.0, false)
      print(string.format("  %s: %.3fs (hits=%d)", region_name, slice.onset_time, #slice.hits))
    end
  end
  session:add_stateful_diff_command(extracted_playlist:to_statefuldestructible())
  session:commit_reversible_command(nil)
  
  -- === 4. TONE CLUSTERING ===
  print("\n4. Tone Clustering")
  print("------------------")
  
  local function calculate_features(region, onset_frame, duration_sec)
    local features = {
      spectral_centroid = 0,
      rms_amplitude = 0,
      zero_crossing_rate = 0
    }
    
    local readable = region:to_readable()
    if readable:isnil() then
      return features
    end
    
    local n_samples = math.floor(duration_sec * sample_rate)
    local samples = ARDOUR.DSP.DspShm(n_samples)
    
    -- Read the slice
    readable:read(samples:to_float(0), onset_frame, n_samples, 0)
    local sample_array = samples:to_float(0):array()
    
    -- Calculate RMS amplitude
    local sum_squares = 0
    local zero_crossings = 0
    local prev_sample = 0
    
    -- FFT preparation for spectral centroid
    local fft_size = 512
    local magnitude_sum = 0
    local weighted_freq_sum = 0
    
    for i = 1, n_samples do
      local sample = sample_array[i] or 0
      sum_squares = sum_squares + sample * sample
      
      -- Count zero crossings
      if i > 1 and prev_sample * sample < 0 then
        zero_crossings = zero_crossings + 1
      end
      prev_sample = sample
    end
    
    features.rms_amplitude = math.sqrt(sum_squares / n_samples)
    features.zero_crossing_rate = zero_crossings / duration_sec
    
    -- Approximate spectral centroid using power spectrum
    -- (Simplified version - in production would use proper FFT)
    -- For now, use ZCR as a proxy for frequency content
    features.spectral_centroid = features.zero_crossing_rate * 50  -- Rough Hz approximation
    
    return features
  end
  
  print("Calculating features for each hit slice:")
  print("  Spectral Centroid (Hz)")
  print("  RMS Amplitude")
  print("  Zero-Crossing Rate (Hz)")
  print("")
  
  -- Calculate features for each hit
  for i, slice in ipairs(hit_slices) do
    slice.features = calculate_features(source_region, slice.onset_frame, slice.duration)
  end
  
  -- K-means clustering
  local function kmeans_clustering(slices, k)
    print("Running K-means clustering with " .. k .. " clusters...")
    
    -- Normalize features
    local min_sc, max_sc = math.huge, -math.huge
    local min_rms, max_rms = math.huge, -math.huge
    local min_zcr, max_zcr = math.huge, -math.huge
    
    for _, slice in ipairs(slices) do
      min_sc = math.min(min_sc, slice.features.spectral_centroid)
      max_sc = math.max(max_sc, slice.features.spectral_centroid)
      min_rms = math.min(min_rms, slice.features.rms_amplitude)
      max_rms = math.max(max_rms, slice.features.rms_amplitude)
      min_zcr = math.min(min_zcr, slice.features.zero_crossing_rate)
      max_zcr = math.max(max_zcr, slice.features.zero_crossing_rate)
    end
    
    -- Initialize centroids using k-means++ method
    local centroids = {}
    
    -- First centroid: random slice
    local first_idx = math.random(#slices)
    centroids[1] = {
      spectral_centroid = slices[first_idx].features.spectral_centroid,
      rms_amplitude = slices[first_idx].features.rms_amplitude,
      zero_crossing_rate = slices[first_idx].features.zero_crossing_rate
    }
    
    -- Remaining centroids: probability based on distance
    for c = 2, k do
      local max_min_dist = -1
      local best_idx = 1
      
      for i, slice in ipairs(slices) do
        local min_dist = math.huge
        
        for j = 1, c - 1 do
          local dist = math.sqrt(
            ((slice.features.spectral_centroid - centroids[j].spectral_centroid) / (max_sc - min_sc + 0.001)) ^ 2 +
            ((slice.features.rms_amplitude - centroids[j].rms_amplitude) / (max_rms - min_rms + 0.001)) ^ 2 +
            ((slice.features.zero_crossing_rate - centroids[j].zero_crossing_rate) / (max_zcr - min_zcr + 0.001)) ^ 2
          )
          min_dist = math.min(min_dist, dist)
        end
        
        if min_dist > max_min_dist then
          max_min_dist = min_dist
          best_idx = i
        end
      end
      
      centroids[c] = {
        spectral_centroid = slices[best_idx].features.spectral_centroid,
        rms_amplitude = slices[best_idx].features.rms_amplitude,
        zero_crossing_rate = slices[best_idx].features.zero_crossing_rate
      }
    end
    
    -- Iterate clustering
    for iteration = 1, 20 do
      local changes = 0
      
      -- Assign slices to nearest centroid
      for _, slice in ipairs(slices) do
        local min_distance = math.huge
        local nearest_cluster = 1
        
        for cluster_id, centroid in ipairs(centroids) do
          -- Calculate normalized Euclidean distance
          local dist = math.sqrt(
            ((slice.features.spectral_centroid - centroid.spectral_centroid) / (max_sc - min_sc + 0.001)) ^ 2 +
            ((slice.features.rms_amplitude - centroid.rms_amplitude) / (max_rms - min_rms + 0.001)) ^ 2 +
            ((slice.features.zero_crossing_rate - centroid.zero_crossing_rate) / (max_zcr - min_zcr + 0.001)) ^ 2
          )
          
          if dist < min_distance then
            min_distance = dist
            nearest_cluster = cluster_id
          end
        end
        
        if slice.group_id ~= nearest_cluster then
          changes = changes + 1
        end
        slice.group_id = nearest_cluster
      end
      
      -- Update centroids
      for cluster_id = 1, k do
        local sum_sc, sum_rms, sum_zcr = 0, 0, 0
        local count = 0
        
        for _, slice in ipairs(slices) do
          if slice.group_id == cluster_id then
            sum_sc = sum_sc + slice.features.spectral_centroid
            sum_rms = sum_rms + slice.features.rms_amplitude
            sum_zcr = sum_zcr + slice.features.zero_crossing_rate
            count = count + 1
          end
        end
        
        if count > 0 then
          centroids[cluster_id].spectral_centroid = sum_sc / count
          centroids[cluster_id].rms_amplitude = sum_rms / count
          centroids[cluster_id].zero_crossing_rate = sum_zcr / count
        end
      end
      
      -- Check convergence
      if changes == 0 then
        print("Converged after " .. iteration .. " iterations")
        break
      end
    end
  end
  
  kmeans_clustering(hit_slices, config.group_count)
  
  -- Print clustering results
  print("\nClustering assignments:")
  local cluster_counts = {}
  local cluster_features = {}
  
  for _, slice in ipairs(hit_slices) do
    cluster_counts[slice.group_id] = (cluster_counts[slice.group_id] or 0) + 1
    
    if not cluster_features[slice.group_id] then
      cluster_features[slice.group_id] = {
        spectral_centroids = {},
        rms_amplitudes = {},
        zero_crossing_rates = {}
      }
    end
    
    table.insert(cluster_features[slice.group_id].spectral_centroids, slice.features.spectral_centroid)
    table.insert(cluster_features[slice.group_id].rms_amplitudes, slice.features.rms_amplitude)
    table.insert(cluster_features[slice.group_id].zero_crossing_rates, slice.features.zero_crossing_rate)
  end
  
  for cluster_id = 1, config.group_count do
    if cluster_counts[cluster_id] then
      local cf = cluster_features[cluster_id]
      
      -- Calculate averages
      local avg_sc = 0
      local avg_rms = 0
      local avg_zcr = 0
      
      for _, v in ipairs(cf.spectral_centroids) do avg_sc = avg_sc + v end
      for _, v in ipairs(cf.rms_amplitudes) do avg_rms = avg_rms + v end
      for _, v in ipairs(cf.zero_crossing_rates) do avg_zcr = avg_zcr + v end
      
      avg_sc = avg_sc / #cf.spectral_centroids
      avg_rms = avg_rms / #cf.rms_amplitudes
      avg_zcr = avg_zcr / #cf.zero_crossing_rates
      
      print(string.format("  Cluster %d: %d hits (avg SC=%.1f Hz, RMS=%.3f, ZCR=%.1f Hz)", 
            cluster_id, cluster_counts[cluster_id], avg_sc, avg_rms, avg_zcr))
    end
  end
  
  -- === 5. PATTERN CONSTRUCTION ===
  print("\n5. Pattern Construction")
  print("-----------------------")
  
  -- Select two most populated clusters as tone A and B
  local sorted_clusters = {}
  for cluster_id, count in pairs(cluster_counts) do
    table.insert(sorted_clusters, {id = cluster_id, count = count})
  end
  table.sort(sorted_clusters, function(a, b) return a.count > b.count end)
  
  local tone_a_id = sorted_clusters[1] and sorted_clusters[1].id or 1
  local tone_b_id = sorted_clusters[2] and sorted_clusters[2].id or 2
  
  print("Selected tone groups:")
  print("  tone_A: Cluster " .. tone_a_id)
  print("  tone_B: Cluster " .. tone_b_id)
  
  -- Get hits for each tone
  local tone_a_hits = {}
  local tone_b_hits = {}
  
  for _, slice in ipairs(hit_slices) do
    if slice.group_id == tone_a_id then
      table.insert(tone_a_hits, slice)
    elseif slice.group_id == tone_b_id then
      table.insert(tone_b_hits, slice)
    end
  end
  
  if #tone_a_hits == 0 or #tone_b_hits == 0 then
    print("ERROR: Could not find enough hits for both tone groups.")
    return
  end

  print(string.format("Using %d hits for tone A, %d hits for tone B", #tone_a_hits, #tone_b_hits))

  print("\nPattern: " .. table.concat(config.pattern, " "):gsub("1", "A"):gsub("2", "B"))
  print("Repeat count: " .. config.repeat_count)
  
  -- Generate sequence
  local sequence = {}
  local beat_duration = 60.0 / 120.0 * config.quantization  -- Assuming 120 BPM
  local current_time = 0
  
  math.randomseed(os.time())
  
  print("\nGenerating sequence...")
  
  local a_index, b_index = 1, 1

  for rep = 1, config.repeat_count do
    for pos, pattern_element in ipairs(config.pattern) do
      local selected_hit = nil
      local tone_type = nil

      if pattern_element == 1 then
        selected_hit = tone_a_hits[a_index]
        tone_type = "A"
        a_index = (a_index % #tone_a_hits) + 1
      elseif pattern_element == 2 then
        selected_hit = tone_b_hits[b_index]
        tone_type = "B"
        b_index = (b_index % #tone_b_hits) + 1
      end

      if selected_hit then
        table.insert(sequence, {
          hit = selected_hit,
          scheduled_time = current_time,
          tone_type = tone_type,
          pattern_position = pos,
          repetition = rep
        })
      end

      current_time = current_time + beat_duration
    end
  end
  
  print("Generated " .. #sequence .. " events")
  
  -- === 6. PLACEMENT ===
  print("\n6. Placement")
  print("------------")
  print("Output track: " .. config.output_track_name)
  print("Quantization: " .. config.quantization .. " beats")
  print("Humanization: ±" .. (config.humanize_timing * 1000) .. " ms, ±" .. config.humanize_gain .. " dB")
  
  -- Create or find the target track
  local target_track = nil
  
  -- First, search for an existing track with the desired name
  for route in session:get_routes():iter() do
    local tr = route:to_track()
    if not tr:isnil() and tr:name() == config.output_track_name then
      target_track = tr:to_audio_track()
      break
    end
  end
  
  -- If not found or invalid, create a new one
  if (target_track == nil) or target_track:isnil() then
    -- Create new track
    print("Creating new track: " .. config.output_track_name)
    
    local track_list = session:new_audio_track(
      source_region:n_channels(),  -- Same channel count as source
      2,                           -- 2 outputs (stereo)
      nil,                         -- Route group
      1,                           -- How many tracks
      config.output_track_name,    -- Name
      ARDOUR.PresentationInfo.max_order,
      ARDOUR.TrackMode.Normal,
      true                         -- Use strict I/O
    )
    
    -- Check if track creation was successful
    if track_list == nil then
      print("ERROR: Session:new_audio_track returned nil - cannot create output track.")
      return
    end
    
    if track_list:empty() then
      print("ERROR: Failed to create output track (RouteList empty).")
      return
    end
    
    -- Get the first route from the returned RouteList
    local first_route = track_list:front()
    if first_route:isnil() then
      print("ERROR: Newly created RouteList does not contain a valid route.")
      return
    end
    
    target_track = first_route:to_audio_track()
    if target_track:isnil() then
      print("ERROR: Newly created route is not an audio track.")
      return
    end
  end
  
  -- Final sanity check
  if (target_track == nil) or target_track:isnil() then
    print("ERROR: Could not create or access the target track: " .. config.output_track_name)
    return
  end
  
  -- Clear existing regions on target track
  local target_playlist = target_track:playlist()
  target_playlist:to_stateful():clear_changes()
  
  local existing_regions = {}
  for r in target_playlist:region_list():iter() do
    table.insert(existing_regions, r)
  end
  
  for _, r in ipairs(existing_regions) do
    target_playlist:remove_region(r)
  end
  
  -- Place regions
  print("\nPlacing regions:")
  
  session:begin_reversible_command("Dundun Rhythm Generation")
  
  -- Get source offset
  local source_start = source_region:start():samples()
  
  for i, event in ipairs(sequence) do
    -- Calculate position with humanization
    local time_jitter = (math.random() - 0.5) * 2 * config.humanize_timing
    local final_time = math.max(0, event.scheduled_time + time_jitter)
    local frame_position = math.floor(final_time * sample_rate)
    
    -- Create region slice
    local region_name = string.format("hit_%03d", i)
    
    -- Clone the source region
    local new_region = ARDOUR.RegionFactory.clone_region(source_region, true, true)
    
    if not new_region:isnil() then
      -- Set the region bounds to extract the hit slice
      new_region:set_start(Temporal.timepos_t(source_start + event.hit.onset_frame))
      new_region:set_length(Temporal.timecnt_t(math.floor(config.slice_duration * sample_rate)))
      new_region:set_name(region_name)
      
      -- Calculate gain with humanization
      local gain_db_variation = (math.random() - 0.5) * 2 * config.humanize_gain
      local gain_linear = 10 ^ (gain_db_variation / 20)
      
      -- Add to playlist
      target_playlist:add_region(new_region, Temporal.timepos_t(frame_position), gain_linear, false)
      
      print(string.format("  %s: %.3fs (tone %s) gain=%.1f dB", 
            region_name, final_time, event.tone_type, gain_db_variation))
    end
  end
  
  session:add_stateful_diff_command(target_playlist:to_statefuldestructible())
  session:commit_reversible_command(nil)
  
  -- === OUTPUT SUMMARY ===
  print("\n=== OUTPUT ===")
  print("New track: " .. target_track:name())
  print("Placed regions: " .. #sequence)
  print("\nConsole output includes:")
  print("  ✓ Onset log")
  print("  ✓ Clustering assignments")
  print("  ✓ Final region placements and identifiers")
  
  print("\n=== GENERATION COMPLETE ===")
  
end end

-- Icon for the script
function icon(params) return function(ctx, width, height, fg)
  local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(width * .5) .. "px")
  txt:set_text("🥁♪")
  local tw, th = txt:get_pixel_size()
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))
  ctx:move_to(.5 * (width - tw), .5 * (height - th))
  txt:show_in_cairo_context(ctx)
end end 