# Mecca Track Analysis

## GOAL
Analyze time segment from 1:04 to 1:36 across 6 defined tracks in Ardour, plus 1 additional track containing manually extracted talking drum samples. Output structured, feature-rich metadata describing rhythmic, spectral, and amplitude behavior across all tracks. The LLM will consume this output to generate a Lua script that places talking drum hits rhythmically within the same segment (1:04–1:36).

## I. INPUT

### Time Range:
- **Start:** 00:01:04.000
- **End:** 00:01:36.000
- **Duration:** 32 seconds

### Track Sources (from screenshot):
- `main-track`
- `synth1-stem`
- `drums-stem`
- `bass-stem`
- `synth2-stem`
- `tdrum-samples` (manually sliced hits)

Each audio file/region must be cropped to the specified time range before analysis.

## II. ANALYTICAL PIPELINE

### Step 1: Temporal Segmentation
- Trim each track to the target range (1:04–1:36)
- Normalize sample amplitude where appropriate (optional toggle)
- Resample to 48kHz (if not already)

### Step 2: Per-Track Analysis (Tracks 1–5)

#### A. Rhythm/Timing
- Onset detection → timestamps (in seconds)
- Inter-Onset Interval (IOI) histogram per track
- Dominant pulse estimate (tempo and subdivisions per bar)

#### B. Spectral Summary
- Average Spectral Centroid over time
- Band-limited energy breakdown (e.g., low/mid/high freq power)
- Optional: MFCCs (if using Python + Librosa)

#### C. Amplitude Envelope
- RMS envelope (32-second window, frame-wise, 50ms)
- Peak amplitude per second (coarse dynamics map)

### Step 3: tdrum-samples Track Analysis
For each isolated hit (based on Ardour region boundaries or time silence gaps):

**Timing:** Onset time

**Amplitude:** Peak and RMS

**Spectral:** Spectral centroid, Zero-crossing rate

**Classification:** Assign each hit to one of N tonal categories (via clustering)

**Clustering methods:**
- K-means (recommended)
- Agglomerative (optional)
- Heuristic thresholds (fallback)

**Group hit metadata:**
```json
{
  "id": "hit_001",
  "start_sec": 4.35,
  "duration_sec": 0.29,
  "rms": 0.21,
  "peak": 0.96,
  "spectral_centroid": 3560.7,
  "zcr": 712.0,
  "cluster": 2
}
```

## III. OUTPUT

**Format:** `analysis_output.json`

```json
{
  "analysis_range": {
    "start_sec": 64.0,
    "end_sec": 96.0
  },
  "tracks": [
    {
      "name": "main-track",
      "onsets": [64.3, 64.9, 65.3, ...],
      "rms_envelope": [...],
      "spectral_centroid": [...],
      "ioi_histogram": {...},
      "tempo": 120,
      "beat_division": 2
    },
    ...
  ],
  "talking_drum_samples": [
    {
      "id": "hit_001",
      "start_sec": 0.12,
      "duration_sec": 0.3,
      "rms": 0.21,
      "spectral_centroid": 3250.4,
      "zcr": 705,
      "cluster": 1
    },
    ...
  ]
}
```

## IV. OUTPUT PURPOSE

This file will be manually submitted to an LLM

**The LLM will use it to:**
- Generate Lua code that selects rhythmic placements for drum hits
- Insert those hits rhythmically and tonally into 1:04–1:36 range of the main/stem timeline
- Place regions via Ardour Lua API aligned to quantized grid (Phase 2)

## V. REQUIREMENTS

| Analysis window trim 
| Multi-track input parsing 
| Talking drum feature extraction 
| K-means clustering 
| Console/debug logging 
| JSON structured export 