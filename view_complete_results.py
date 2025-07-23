import pandas as pd

# Read the generated Excel file
df = pd.read_excel('extracted_cowbell_sequences.xlsx')

print("🎵 SALSA COWBELL PATTERN EXTRACTION RESULTS 🎵")
print("=" * 60)

# Remove any header rows that got mixed into the data
df_clean = df[df['Sequence'].astype(str).str.isdigit()].copy()
df_clean['Sequence'] = df_clean['Sequence'].astype(int)

print(f"📊 Total cowbell hits extracted: {len(df_clean)}")
print(f"🔍 Total sequences found: {df_clean['Sequence'].nunique()}")

print("\n📈 SEQUENCE SUMMARY:")
print("-" * 40)
for seq_num in sorted(df_clean['Sequence'].unique()):
    seq_data = df_clean[df_clean['Sequence'] == seq_num]
    source = seq_data['Source'].iloc[0]
    confidence = seq_data['Confidence'].iloc[0]
    start_time = seq_data['Time(s)'].iloc[0]
    end_time = seq_data['Time(s)'].iloc[-1]
    
    print(f"Sequence {seq_num}: {source}")
    print(f"  ⏱️  Duration: {start_time:.3f}s - {end_time:.3f}s")
    print(f"  🎯 Confidence: {confidence:.1%}")
    print(f"  🥁 Hits: {len(seq_data)}")
    print()

# Show the detected sequence in detail
detected_seqs = df_clean[df_clean['Source'] == 'Detected']
if len(detected_seqs) > 0:
    print("🔍 DETECTED SEQUENCE DETAILS:")
    print("-" * 40)
    
    for seq_num in detected_seqs['Sequence'].unique():
        seq_data = detected_seqs[detected_seqs['Sequence'] == seq_num]
        print(f"\nSequence {seq_num} (Confidence: {seq_data['Confidence'].iloc[0]:.1%}):")
        
        # Calculate deltas for this sequence
        times = seq_data['Time(s)'].values
        deltas_ms = []
        for i in range(1, len(times)):
            delta = round((times[i] - times[i-1]) * 1000)
            deltas_ms.append(delta)
        
        print(f"Timing deltas (ms): {deltas_ms}")
        print(f"Reference pattern:  [278, 467, 583, 139, 441, 254, 446, 204, 543]")
        
        # Show the timing details
        print("\nBeat-by-beat timing:")
        for idx, row in seq_data.iterrows():
            beat = int(row['Beat'])
            time_val = row['Time(s)']
            delta = row['Delta(s)']
            delta_ms = int(delta * 1000) if pd.notna(delta) else 0
            
            if beat == 1:
                print(f"  Beat {beat:2d}: {time_val:7.3f}s")
            else:
                ref_delta = [278, 467, 583, 139, 441, 254, 446, 204, 543][beat-2]
                diff = abs(delta_ms - ref_delta) if delta_ms > 0 else 0
                match = "✓" if diff <= 80 else "✗"
                print(f"  Beat {beat:2d}: {time_val:7.3f}s  Δ={delta_ms:3d}ms (ref: {ref_delta:3d}ms) {match}")

print(f"\n📁 Results exported to: extracted_cowbell_sequences.xlsx")
print("✅ Extraction complete!") 