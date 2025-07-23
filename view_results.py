import pandas as pd

# Read the generated Excel file
df = pd.read_excel('extracted_cowbell_sequences.xlsx')

print("=== COWBELL PATTERN EXTRACTION RESULTS ===")
print(f"Total rows: {len(df)}")
print("\nFirst 10 rows:")
print(df.head(10).to_string(index=False))

print("\nSummary by sequence:")
sequence_summary = df.groupby('Sequence').agg({
    'Beat': 'count',
    'Source': 'first',
    'Confidence': 'first'
}).rename(columns={'Beat': 'Hit_Count'})
print(sequence_summary.to_string())

print("\nDetected sequences (confidence < 1.0):")
detected = df[df['Confidence'] < 1.0]
if len(detected) > 0:
    print(detected.to_string(index=False))
else:
    print("No detected sequences found") 