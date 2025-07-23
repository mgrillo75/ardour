import pandas as pd
import numpy as np

# Read the generated Excel file
df = pd.read_excel('extracted_cowbell_sequences.xlsx')

print("🎵 SALSA COWBELL PATTERN EXTRACTION RESULTS 🎵")
print("=" * 60)

# Clean the data - remove header rows and convert types
df_clean = df.copy()

# Remove rows where Sequence is not numeric
df_clean = df_clean[pd.to_numeric(df_clean['Sequence'], errors='coerce').notna()]
df_clean['Sequence'] = pd.to_numeric(df_clean['Sequence'])

# Convert Time(s) to numeric, keeping only valid entries
df_clean['Time(s)'] = pd.to_numeric(df_clean['Time(s)'], errors='coerce')
df_clean = df_clean[df_clean['Time(s)'].notna()]

print(f"📊 Total cowbell hits extracted: {len(df_clean)}")
print(f"🔍 Total sequences found: {int(df_clean['Sequence'].max())}")

print("\n📈 SEQUENCE SUMMARY:")
print("-" * 40)

sequences = sorted(df_clean['Sequence'].unique())
for seq_num in sequences:
    seq_data = df_clean[df_clean['Sequence'] == seq_num].copy()
    if len(seq_data) > 0:
        source = seq_data['Source'].iloc[0]
        confidence = seq_data['Confidence'].iloc[0]
        start_time = seq_data['Time(s)'].iloc[0]
        end_time = seq_data['Time(s)'].iloc[-1]
        
        print(f"Sequence {int(seq_num)}: {source}")
        print(f"  ⏱️  Duration: {start_time:.3f}s - {end_time:.3f}s ({end_time-start_time:.3f}s total)")
        print(f"  🎯 Confidence: {confidence:.1%}")
        print(f"  🥁 Hits: {len(seq_data)}")
        print()

# Show detailed analysis of detected sequences
detected_seqs = df_clean[df_clean['Source'] == 'Detected']
if len(detected_seqs) > 0:
    print("🔍 DETECTED SEQUENCE ANALYSIS:")
    print("-" * 40)
    
    for seq_num in detected_seqs['Sequence'].unique():
        seq_data = detected_seqs[detected_seqs['Sequence'] == seq_num].sort_values('Beat')
        confidence = seq_data['Confidence'].iloc[0]
        
        print(f"\nSequence {int(seq_num)} - Confidence: {confidence:.1%}")
        print("Reference pattern: [278, 467, 583, 139, 441, 254, 446, 204, 543] ms")
        
        # Calculate actual deltas
        times = seq_data['Time(s)'].values
        actual_deltas = []
        for i in range(1, len(times)):
            delta = round((times[i] - times[i-1]) * 1000)
            actual_deltas.append(delta)
        
        print(f"Detected pattern:  {actual_deltas} ms")
        
        # Compare with reference
        ref_pattern = [278, 467, 583, 139, 441, 254, 446, 204, 543]
        matches = 0
        print("\nDelta comparison:")
        for i, (actual, reference) in enumerate(zip(actual_deltas, ref_pattern)):
            diff = abs(actual - reference)
            is_match = diff <= 80  # 80ms tolerance
            status = "✓" if is_match else "✗"
            if is_match:
                matches += 1
            print(f"  Delta {i+1}: {actual:3d}ms vs {reference:3d}ms (diff: {diff:2d}ms) {status}")
        
        print(f"\nMatches: {matches}/{len(ref_pattern)} = {matches/len(ref_pattern):.1%}")

else:
    print("\n❌ No new sequences detected in the mixed data")

print(f"\n📁 Full results saved to: extracted_cowbell_sequences.xlsx")
print("✅ Analysis complete!") 