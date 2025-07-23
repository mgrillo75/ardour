import os
import re

def clean_filename(filename):
    """
    Clean the filename by:
    1. Removing 'Latin Percussion' or 'Meinl Percussion' from the beginning
    2. Removing any leading/trailing spaces
    3. Removing the first '#' and everything after it
    """
    # Get the file extension
    name, ext = os.path.splitext(filename)
    
    # Remove 'Latin Percussion' or 'Meinl Percussion' from the beginning
    name = re.sub(r'^(Latin Percussion|Meinl Percussion)\s*', '', name)
    
    # Remove the first '#' and everything after it
    if '#' in name:
        name = name.split('#')[0]
    
    # Remove any trailing spaces
    name = name.strip()
    
    # Return the cleaned name with extension
    return name + ext

def rename_files(directory_path):
    """
    Rename all files in the specified directory.
    
    Args:
        directory_path: Path to the directory containing files to rename
    """
    if not os.path.exists(directory_path):
        print(f"Error: Directory '{directory_path}' does not exist!")
        return
    
    # Get all files in the directory
    files = [f for f in os.listdir(directory_path) if os.path.isfile(os.path.join(directory_path, f))]
    
    renamed_count = 0
    skipped_count = 0
    error_count = 0
    
    print(f"Processing {len(files)} files in '{directory_path}'...")
    print()
    
    for filename in files:
        new_filename = clean_filename(filename)
        
        # Skip if the filename doesn't need to change
        if filename == new_filename:
            skipped_count += 1
            continue
        
        old_path = os.path.join(directory_path, filename)
        new_path = os.path.join(directory_path, new_filename)
        
        # Check if the new filename already exists
        if os.path.exists(new_path):
            print(f"⚠️  Cannot rename: '{filename}'")
            print(f"   → Target name already exists: '{new_filename}'")
            error_count += 1
            continue
        
        try:
            os.rename(old_path, new_path)
            print(f"✓ Renamed: '{filename}' → '{new_filename}'")
            renamed_count += 1
        except Exception as e:
            print(f"❌ ERROR renaming '{filename}': {e}")
            error_count += 1
    
    print(f"\nComplete!")
    print(f"  - Files renamed: {renamed_count}")
    print(f"  - Files unchanged: {skipped_count}")
    print(f"  - Errors: {error_count}")
    print(f"  - Total files: {len(files)}")

def main():
    # Directory containing the percussion files
    percussion_dir = r"C:\Users\Miguel\Documents\percussion\2"
    
    # Execute the renaming
    rename_files(percussion_dir)

if __name__ == "__main__":
    main()
