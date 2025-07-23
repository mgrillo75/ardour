# Triangle Alignment Scripts for Ardour

These scripts automatically analyze your main track's rhythm and intelligently position triangle tracks to create musically complementary arrangements.

## Scripts Overview

### 1. `rhythm_align_triangles.lua` - Basic Triangle Alignment
Analyzes the main track and creates complementary triangle arrangements with different strategies for triangle-400 and triangle-500.

### 2. `smart_triangle_arranger.lua` - Advanced Smart Arranger  
Enhanced version with multiple arrangement styles, swing detection, and sophisticated musical intelligence.

## How It Works

1. **Rhythm Analysis**: Uses VAMP plugins to detect beats, bars, and onsets in your main track
2. **Musical Intelligence**: Calculates optimal placement based on:
   - Beat strength (downbeats vs. weak beats)
   - Rhythmic density of the main track
   - Swing feel detection
   - Musical phrasing and bar structure
3. **Smart Placement**: Creates different patterns for different triangle types:
   - **Triangle-400 (Low)**: Strong beats + syncopation
   - **Triangle-500 (High)**: Off-beats + decorative elements
4. **Automatic Arrangement**: Repositions existing triangle regions to new calculated positions

## Setup Requirements

### Track Naming
Your triangle tracks should be named with "triangle" in the name:
- `triangle-400` or `triangle_400` (detected as "low" triangle)
- `triangle-500` or `triangle_500` (detected as "high" triangle)  
- Any track with "triangle" in the name (detected as "generic")

### Source Regions
Make sure your triangle tracks have some existing audio regions - the scripts will use these as source material and reposition them.

## Usage Instructions

### Basic Workflow
1. **Load your session** with the main rhythmic track and triangle tracks
2. **Select the main track regions** you want to analyze (usually drums or main rhythm)
3. **Run the script** via Menu → Edit → Scripted Actions → [Script Name]
4. **Review the results** - triangle tracks will be automatically rearranged

### Example Session Setup
```
Tracks:
├── SwayingSea (main rhythmic track) ← SELECT THIS
├── triangle-400                     ← Will be auto-arranged  
└── triangle-500                     ← Will be auto-arranged
```

## Arrangement Styles

### Complementary (Default)
- **Triangle-400**: Placed on strong beats (1, 3) with occasional syncopation
- **Triangle-500**: Placed on off-beats and weak beats for rhythmic interest
- **Result**: Natural, complementary rhythm that enhances the groove

### Call & Response  
- Triangles respond to strong beats with slight delays
- Creates conversational feel between main track and triangles
- Good for jazz and Latin styles

### Polyrhythmic
- Creates independent rhythmic patterns (e.g., dotted eighth notes)
- Adds complexity and interest to simple grooves
- Good for progressive and world music styles

## Musical Intelligence Features

### Beat Strength Analysis
- **Downbeats (1)**: Strongest placement, full volume
- **Beat 3**: Strong placement, high volume  
- **Beats 2 & 4**: Medium strength, moderate volume
- **Off-beats**: Lighter placement, lower volume

### Swing Detection
- Automatically detects swing feel in the main track
- Preserves swing timing in triangle placement
- Maintains the groove's natural feel

### Velocity Variation
- Adds natural velocity variation to prevent mechanical feel
- Based on beat strength and position type
- Configurable range for different musical styles

### Automatic Gain Staging
- Prevents overcrowding with maximum region limits
- Balances volumes based on rhythmic function
- Maintains mix clarity

## Console Output Example

```
=== SMART TRIANGLE ARRANGER ===
Found triangle track: triangle-400 (type: low)
Found triangle track: triangle-500 (type: high)

=== ANALYZING MAIN TRACK RHYTHM ===
Analyzing: SwayingSea.1
Swing detected: 1.15 ratio
Analysis complete: 32 beats, 8 bars, 127 onsets
Tempo: 120.50 BPM
Rhythmic density: 8.45 onsets/second

Creating complementary arrangement for triangle-400...
=== ARRANGING TRIANGLE-400 ===
  1: 7.783s (strong_beat) gain=0.95
  2: 8.642s (syncopation) gain=0.68
  3: 8.750s (strong_beat) gain=0.82
  ...
Placed 16 regions in triangle-400

Creating complementary arrangement for triangle-500...
=== ARRANGING TRIANGLE-500 ===
  1: 8.025s (off_beat) gain=0.58
  2: 8.317s (decoration) gain=0.47
  3: 8.992s (off_beat) gain=0.61
  ...
Placed 18 regions in triangle-500

=== SMART ARRANGEMENT COMPLETE ===
Swing feel detected and preserved (1.15 ratio)
```

## Customization Options

### In `smart_triangle_arranger.lua`, you can modify the config section:

```lua
local config = {
  max_regions_per_track = 24,        -- Maximum triangle hits per track
  min_interval_seconds = 0.1,        -- Minimum time between hits
  swing_detection_threshold = 0.15,  -- Sensitivity for swing detection
  velocity_variation_range = 0.4,    -- Amount of velocity variation
  arrangement_style = "complementary" -- "complementary", "call_response", "polyrhythmic"
}
```

## Tips for Best Results

### Main Track Selection
- **Select clear rhythmic material**: Drums, percussion, or strong rhythmic instruments
- **Avoid overly complex polyrhythms**: Scripts work best with clear beat patterns
- **Include complete phrases**: Select full bars/measures for better analysis

### Triangle Track Preparation  
- **Have source regions ready**: Scripts reposition existing regions
- **Use short, punchy samples**: Triangle hits work best as short percussive elements
- **Consider track names**: Use "400" and "500" in names for automatic type detection

### Musical Considerations
- **Start with complementary style**: Most musical for most genres
- **Try call_response for jazz**: Great for swing and Latin music
- **Use polyrhythmic sparingly**: Adds complexity but can clash with simple grooves

## Troubleshooting

### "No triangle tracks found"
- Check track naming - must contain "triangle"
- Ensure tracks are audio tracks, not MIDI

### "No beats detected"  
- Main track may be too quiet or complex
- Try selecting clearer rhythmic sections
- Check that selected regions contain audio

### "No source regions found"
- Triangle tracks need existing audio regions to reposition
- Import or record some triangle samples first

### Results sound too busy
- Reduce `max_regions_per_track` in config
- Increase `min_interval_seconds` for more spacing
- Try "call_response" style for sparser arrangements

## Advanced Usage

### Multiple Main Tracks
Run the script multiple times with different main track selections to create layered arrangements.

### Manual Fine-Tuning
After automatic arrangement, manually adjust individual regions for perfect musical fit.

### Combining with Other Scripts
Use rhythm analysis scripts first to understand your track's characteristics, then apply triangle arrangement.

### Export and Reuse
The arrangement patterns can be saved as templates for similar musical styles.

## Musical Applications

### Genre-Specific Uses
- **Latin Music**: Use complementary style with swing detection
- **Electronic**: Try polyrhythmic for complex textures  
- **Jazz**: Call & response works great with swing feel
- **Rock/Pop**: Complementary style enhances groove without cluttering

### Production Techniques
- **Layered Percussion**: Build complex percussion arrangements
- **Groove Enhancement**: Add subtle rhythmic interest to simple beats
- **Call & Response**: Create musical conversations between elements
- **Polyrhythmic Textures**: Add sophisticated rhythmic layers

The scripts provide a professional starting point that you can further refine manually for perfect musical results! 