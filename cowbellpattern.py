"""
Complete Cowbell Pattern Extraction Solution for Salsa Bell Pattern
"""
import pandas as pd
import numpy as np
import math
import os

class SalsaCowbellExtractor:
    def __init__(self):
        # Reference pattern from first sequence (deltas in milliseconds)
        self.reference_pattern = [278, 467, 583, 139, 441, 254, 446, 204, 543]
        
        # Algorithm parameters
        self.tolerance = 80        # ±80ms tolerance for live performance variations
        self.min_confidence = 0.6   # 60% similarity required (6 out of 9 deltas must match)
        self.sequence_length = 10   # Each cowbell pattern has 10 hits
    
    def calculate_pattern_similarity(self, test_deltas):
        """Calculate similarity between test pattern and reference pattern"""
        if len(test_deltas) != len(self.reference_pattern):
            return 0
        
        matches = 0
        for i in range(len(self.reference_pattern)):
            difference = abs(test_deltas[i] - self.reference_pattern[i])
            if difference <= self.tolerance:
                matches += 1
        
        return matches / len(self.reference_pattern)
    
    def extract_deltas(self, timestamps):
        """Extract timing deltas from a sequence of timestamps"""
        deltas = []
        for i in range(1, len(timestamps)):
            delta_ms = round((timestamps[i] - timestamps[i-1]) * 1000)
            deltas.append(delta_ms)
        return deltas
    
    def find_cowbell_sequences(self, mixed_percussion_data):
        """Main function to find cowbell sequences in mixed percussion data"""
        detected_sequences = []
        data_length = len(mixed_percussion_data)
        
        print(f"Scanning {data_length} percussion hits for cowbell patterns...")
        
        # Sliding window approach with step optimization
        i = 0
        while i <= data_length - self.sequence_length:
            # Extract candidate sequence of 10 hits
            candidate_hits = mixed_percussion_data[i:i + self.sequence_length]
            timestamps = [hit[0] for hit in candidate_hits]  # Extract time column
            
            # Calculate timing deltas for this candidate
            candidate_deltas = self.extract_deltas(timestamps)
            
            # Compare with reference pattern
            similarity = self.calculate_pattern_similarity(candidate_deltas)
            
            # If similarity meets threshold, it's likely a cowbell sequence
            if similarity >= self.min_confidence:
                detected_sequences.append({
                    'sequence_number': len(detected_sequences) + 3,  # +3 because we already have seq 1 & 2
                    'start_index': i,
                    'end_index': i + self.sequence_length - 1,
                    'hits': candidate_hits,
                    'timestamps': timestamps,
                    'deltas': candidate_deltas,
                    'confidence': similarity,
                    'start_time': timestamps[0],
                    'end_time': timestamps[-1]
                })
                
                # Skip ahead to avoid overlapping detections
                i += self.sequence_length - 1
            
            i += 1
        
        return detected_sequences
    
    def process_excel_file(self, filename):
        """Process the complete Excel file and extract all cowbell sequences"""
        try:
            # Read Excel file
            df = pd.read_excel(filename, header=None)
            print(f"Loaded {len(df)} rows from Excel file")
            
            # Convert DataFrame to list of lists for easier processing
            data = df.values.tolist()
            
            # Extract the three data sections
            sequence1 = data[0:10]   # Rows 1-10 (original sequence 1)
            sequence2 = data[10:20]  # Rows 11-20 (original sequence 2)  
            mixed_data = data[20:]   # Rows 21+ (mixed percussion data)
            
            print(f"Mixed percussion data: {len(mixed_data)} hits")
            
            # Find cowbell patterns in mixed data
            detected_sequences = self.find_cowbell_sequences(mixed_data)
            
            # Create output data combining original sequences + detected sequences
            output_data = self.create_output_data(sequence1, sequence2, detected_sequences)
            
            return {
                'original_sequence1': sequence1,
                'original_sequence2': sequence2,
                'detected_sequences': detected_sequences,
                'output_data': output_data,
                'summary': {
                    'total_sequences_found': len(detected_sequences) + 2,
                    'total_cowbell_hits': len(output_data),
                    'detection_confidence': [s['confidence'] for s in detected_sequences],
                    'time_range': {
                        'start': mixed_data[0][0] if mixed_data else None,
                        'end': mixed_data[-1][0] if mixed_data else None
                    } if mixed_data else None
                }
            }
            
        except Exception as error:
            print(f'Error processing Excel file: {error}')
            raise error
    
    def create_output_data(self, seq1, seq2, detected_seqs):
        """Create formatted output data for Excel export"""
        output = []
        
        # Add header row
        output.append(['Sequence', 'Beat', 'Time(s)', 'Delta(s)', 'Confidence', 'Source'])
        
        # Add original sequence 1
        for index, hit in enumerate(seq1):
            output.append([
                1,                                    # Sequence number
                index + 1,                           # Beat number (1-10)
                hit[0],                              # Time
                None if index == 0 else hit[2] if len(hit) > 2 else None,  # Delta (null for first beat)
                1.000,                               # Perfect confidence for original data
                'Original'                           # Source
            ])
        
        # Add original sequence 2  
        for index, hit in enumerate(seq2):
            output.append([
                2,                                    # Sequence number
                index + 1,                           # Beat number (1-10)
                hit[0],                              # Time
                None if index == 0 else hit[2] if len(hit) > 2 else None,  # Delta (null for first beat)
                1.000,                               # Perfect confidence for original data
                'Original'                           # Source
            ])
        
        # Add detected sequences
        for sequence in detected_seqs:
            for index, hit in enumerate(sequence['hits']):
                output.append([
                    sequence['sequence_number'],          # Sequence number
                    index + 1,                           # Beat number (1-10)
                    hit[0],                              # Time
                    None if index == 0 else (sequence['deltas'][index-1] / 1000),  # Delta in seconds
                    round(sequence['confidence'], 3),    # Confidence
                    'Detected'                           # Source
                ])
        
        return output
    
    def export_to_excel(self, output_data, filename='extracted_cowbell_sequences.xlsx'):
        """Export results to Excel format"""
        df = pd.DataFrame(output_data[1:], columns=output_data[0])  # Skip header row for DataFrame
        df.to_excel(filename, index=False)
        
        return {
            'filename': filename,
            'status': 'exported'
        }

def extract_cowbell_patterns():
    """Usage example function"""
    extractor = SalsaCowbellExtractor()
    
    try:
        results = extractor.process_excel_file('salsabellpattern.xlsx')
        
        print('=== EXTRACTION RESULTS ===')
        print(f"Total sequences found: {results['summary']['total_sequences_found']}")
        print(f"Total cowbell hits: {results['summary']['total_cowbell_hits']}")
        print(f"Detected sequences: {len(results['detected_sequences'])}")
        
        for idx, seq in enumerate(results['detected_sequences']):
            print(f"Sequence {seq['sequence_number']}: {seq['start_time']:.2f}s-{seq['end_time']:.2f}s ({seq['confidence']*100:.1f}% match)")
        
        # Export to Excel
        excel_file = extractor.export_to_excel(results['output_data'])
        print(f"Excel file ready: {excel_file['filename']}")
        
        return results
        
    except Exception as error:
        print(f'Extraction failed: {error}')
        return None

def run_extraction():
    """Ready-to-use extraction function"""
    extractor = SalsaCowbellExtractor()
    
    try:
        print('Starting cowbell pattern extraction...')
        results = extractor.process_excel_file('salsabellpattern.xlsx')
        
        if results:
            print('\n🎵 EXTRACTION COMPLETE! 🎵')
            print(f"✅ Found {results['summary']['total_sequences_found']} total sequences")
            print(f"✅ Extracted {results['summary']['total_cowbell_hits']} cowbell hits")
            print(f"✅ Detected {len(results['detected_sequences'])} new sequences in mixed data")
            
            # Show detected sequences
            if results['detected_sequences']:
                print('\nDetected Sequences:')
                for idx, seq in enumerate(results['detected_sequences']):
                    print(f"  Sequence {seq['sequence_number']}: {seq['start_time']:.2f}s-{seq['end_time']:.2f}s ({seq['confidence']*100:.1f}% confidence)")
            
            # Export to downloadable Excel file
            excel_file = extractor.export_to_excel(results['output_data'], 'extracted_cowbell_sequences.xlsx')
            print(f"\n📁 Excel file ready: {excel_file['filename']}")
            
            return results
        else:
            print('❌ Extraction failed')
            return None
        
    except Exception as error:
        print(f'❌ Error during extraction: {error}')
        return None

if __name__ == "__main__":
    # Execute the extraction
    print('🥁 Salsa Cowbell Pattern Extractor Ready!')
    print('📊 Reference Pattern: 278-467-583-139-441-254-446-204-543 ms')
    print('⚙️  Parameters: ±80ms tolerance, 60% confidence threshold')
    print('\nRunning extraction on salsabellpattern.xlsx...')
    
    # Run the extraction automatically
    run_extraction()