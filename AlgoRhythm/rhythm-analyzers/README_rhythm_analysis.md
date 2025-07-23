# Ardour Lua Rhythm Analysis Scripts

This repository contains two powerful Lua scripts for Ardour that can analyze audio tracks to identify rhythm patterns, beats, and their precise timeseries placements.

## Scripts Overview

### 1. `rhythm_analyzer.lua` - Basic Rhythm Analyzer
A comprehensive script that provides detailed rhythm analysis with console output.

**Features:**
- Beat detection and tempo estimation
- Bar/measure detection  
- Onset detection for rhythmic events
- Sample-accurate timing information
- Rhythm pattern analysis
- Inter-onset interval analysis

### 2. `rhythm_analyzer_advanced.lua` - Advanced Analyzer with Export
An enhanced version that includes all basic features plus:
- JSON export of analysis results
- Advanced rhythm classification (straight, swing, complex)
- Time signature detection
- Rhythmic complexity measurement
- Groove characteristics analysis
- Timestamped data export for external processing

## How It Works

The scripts use Ardour's built-in VAMP plugins for audio analysis:

- **`qm-barbeattracker`**: Detects beats and bars using Queen Mary University's beat tracking algorithm
- **`qm-onsetdetector`**: Identifies onset events (note attacks, percussive hits, etc.)

## Installation

1. Copy the `.lua` files to your Ardour scripts directory:
   - **Linux**: `~/.config/ardour8/scripts/`
   - **macOS**: `~/Library/Preferences/Ardour8/scripts/`
   - **Windows**: `%localappdata%\ardour8\scripts\`

2. Restart Ardour or reload scripts via the menu

## Usage

1. **Load your audio** into Ardour
2. **Select the audio regions** you want to analyze
3. **Run the script** via:
   - Menu → Edit → Scripted Actions → [Script Name]
   - Or assign to a keyboard shortcut

## What You Get

### Console Output
```
=== RHYTHM AND BEAT ANALYSIS ===
Analyzing region: Drum Loop
  Position: 0 samples (0.000 seconds)
  Length: 192000 samples (4.000 seconds)
  Performing beat and bar analysis...
  Performing onset analysis...
  Estimated tempo: 120.00 BPM
  Detected time signature: 4/4
  Rhythm classification: straight
  Onset density: 8.50 onsets per second

BEATS DETECTED: 16
Beat positions (time in seconds):
  Beat 1: 0.000 sec (absolute: 0.000 sec) - 1
  Beat 2: 0.500 sec (absolute: 0.500 sec) - 2
  ...

ONSETS DETECTED: 34
Onset positions with sample-accurate timing...
```

### JSON Export (Advanced Script)
```json
{
  "session_info": {
    "sample_rate": 48000,
    "analysis_timestamp": "2025-01-27 15:30:45",
    "total_regions": 1
  },
  "regions": [
    {
      "name": "Drum Loop",
      "position_samples": 0,
      "position_seconds": 0.0,
      "beats": [
        {
          "relative_frame": 0,
          "relative_time": 0.0,
          "absolute_time": 0.0,
          "beat_number": "1"
        }
      ],
      "analysis": {
        "estimated_tempo": 120.0,
        "time_signature": "4/4",
        "rhythm_classification": "straight",
        "onset_density": 8.5,
        "rhythmic_complexity": 2.34
      }
    }
  ]
}
```

## Applications

The analysis data can be used for:

### Music Production
- **Tempo mapping**: Set Ardour's tempo map to match the audio
- **Beat grid alignment**: Align the session grid to detected beats
- **Quantization**: Apply groove-preserving quantization
- **Region slicing**: Automatically slice audio at beat boundaries

### Audio Processing
- **Beat-synchronized effects**: Apply effects that sync to the rhythm
- **Time-stretching**: Preserve groove when changing tempo
- **Groove templates**: Extract timing templates for other tracks

### Analysis & Research
- **Rhythm classification**: Identify straight vs. swing vs. complex rhythms
- **Groove analysis**: Study micro-timing and feel
- **Machine learning**: Train models on rhythm data
- **Musicological research**: Analyze rhythmic patterns in recordings

## Technical Details

### Timing Accuracy
- **Sample-accurate**: All timing data is provided in both samples and seconds
- **Relative and absolute**: Times given relative to region start and absolute session time
- **Frame-perfect**: Uses Ardour's internal sample counting for precision

### Analysis Parameters
The scripts use optimized parameters for the VAMP plugins:
- **Onset detector**: Complex domain analysis with medium sensitivity
- **Beat tracker**: Assumes 4/4 time initially, adapts to detected patterns
- **Time signature**: Automatically detected from beat/bar relationships

### Performance
- **Real-time capable**: Analysis runs efficiently on typical audio lengths
- **Progress indication**: Shows analysis progress for longer regions
- **Memory efficient**: Processes audio in chunks to manage memory usage

## Limitations

- **Audio only**: Works with audio regions, not MIDI
- **Monophonic analysis**: Analyzes first channel of stereo/multi-channel audio
- **VAMP dependency**: Requires Ardour's built-in VAMP plugins
- **Complex rhythms**: May struggle with very irregular or polyrhythmic material

## Troubleshooting

### No regions selected
Make sure you have selected audio regions in the editor before running the script.

### No beats detected
- Try adjusting the "Beats Per Bar" parameter in the script
- Ensure the audio has clear rhythmic content
- Check that the audio isn't too quiet or distorted

### Export file not created
- Check file permissions in the current directory
- Ensure sufficient disk space
- Try running Ardour with appropriate file system permissions

## Extending the Scripts

The scripts are designed to be modular and extensible. You can:

- Add new VAMP plugins for different types of analysis
- Modify the rhythm classification algorithms
- Add new export formats (CSV, XML, etc.)
- Integrate with external analysis tools
- Create custom visualizations of the timing data

## References

- [Ardour Lua Scripting Manual](https://manual.ardour.org/lua-scripting/)
- [VAMP Plugin Documentation](http://vamp-plugins.org/)
- [Queen Mary VAMP Plugins](http://vamp-plugins.org/plugin-doc/qm-vamp-plugins.html)

## License

MIT License - Feel free to modify and distribute these scripts as needed. 