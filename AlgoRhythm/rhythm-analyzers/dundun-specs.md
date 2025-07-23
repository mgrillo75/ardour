# Dundun Automatic Rhythm Generation

## Objective
Automatically extract percussive hits from a solo dundun performance and generate a rhythmically structured, looping motif using tone-based grouping and quantized region placement.

## I. INPUT STRUCTURE

Ardour session containing:

- **Exactly one audio track** with
- **Exactly one full-length audio region**, containing a short tone showcase recording from a dundun player
- Track and region names are dynamic and must be detected at runtime

## II. PROCESS PIPELINE

### 1. Onset Detection
Analyze the full region to locate percussive transients

**Implementation:**
- Use `Region:waveform_samples()` or equivalent
- Identify peaks using:
  - Energy thresholding
  - Minimum inter-onset silence duration (to prevent double hits)
- Log all onset timestamps to console:
  ```lua
  print("Onset found at:", timestamp)
  ```

### 2. Region Extraction
For each onset:
- Clone a sub-region beginning at the onset and lasting ~0.2s (configurable)
- These slices serve as isolated "hit" candidates
- Store each as a Lua object with metadata (start, duration, raw audio values)

### 3. Tone Clustering
For each hit slice, calculate:
- Spectral Centroid
- RMS Amplitude
- Zero-Crossing Rate

Group hits into N tone groups (default 4) using:
- K-means, or
- Heuristic thresholds based on features

Each hit is assigned a `group_id`

Print clustering result summary to console

### 4. Pattern Construction
From the tone groups, select 2 (default) as motif tones: `tone_A`, `tone_B`

Use a fixed or generated pattern, e.g.:
```
A B B B A B B B A
```

Repeat the pattern N times (`repeat_count = 4`)

For each position:
- Randomly choose a hit from the required tone group
- Record sequence and time location

### 5. Placement
- Create a new or clear existing track named: `generated-drum-track`
- Clone and place selected regions onto this track at the proper timeline position
- Snap to quantized grid:
  - Default: 0.5 beats (8th note at 120 BPM)
- Optionally apply humanization:
  - Timing jitter: ±20 ms
  - Gain variation: ±2 dB
- Name placed regions: `hit_001`, `hit_002`, ...

## III. CONFIGURATION (BUILT-IN DEFAULTS)

| Parameter | Default Value | Notes |
|-----------|---------------|-------|
| `slice_duration` | 0.2 seconds | Duration of each hit region |
| `group_count` | 4 | Total tonal clusters |
| `pattern` | A B B B A B B B A | Repeating structure |
| `quantization` | 0.5 beats | 8th notes |
| `repeat_count` | 4 | Loop repetitions |
| `humanize_timing` | ±20 ms | Optional micro-rhythm |
| `humanize_gain` | ±2 dB | Optional loudness variation |

## IV. OUTPUT

**New track:** `generated-drum-track`

**Placed regions** forming repeating motif

**Console output includes:**
- Onset log
- Clustering assignments
- Final region placements and identifiers