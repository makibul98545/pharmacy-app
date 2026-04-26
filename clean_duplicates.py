#!/usr/bin/env python3
"""
Clean up duplicate entries in local database
"""

import requests
from collections import defaultdict

def clean_duplicates():
    """Remove duplicate entries from local database"""

    print('🧹 CLEANING UP DUPLICATE ENTRIES IN LOCAL')
    print('=' * 45)

    # Get local data
    try:
        response = requests.get('http://172.19.53.38:5000/get_entries?type=customer')
        local_data = response.json() if response.status_code == 200 else []
    except:
        local_data = []
        print('❌ Cannot fetch local data')
        return False

    if not local_data:
        print('No data to clean')
        return True

    # Group by name and date
    grouped = defaultdict(list)
    for entry in local_data:
        key = (entry.get('name', ''), entry.get('date', ''))
        grouped[key].append(entry)

    # Find duplicates
    duplicates = {k: v for k, v in grouped.items() if len(v) > 1}

    print(f'Total entries: {len(local_data)}')
    print(f'Unique combinations: {len(grouped)}')
    print(f'Groups with duplicates: {len(duplicates)}')

    if not duplicates:
        print('No duplicates found')
        return True

    # For each duplicate group, keep the one with highest ID (most recent)
    to_delete = []
    for key, entries in duplicates.items():
        # Sort by ID descending, keep the first (highest ID)
        sorted_entries = sorted(entries, key=lambda x: x.get('id', 0), reverse=True)
        keep_entry = sorted_entries[0]
        delete_entries = sorted_entries[1:]

        name, date = key
        print(f'\n{name} ({date}):')
        print(f'  Keeping ID {keep_entry.get("id")}')
        print(f'  Deleting IDs: {[e.get("id") for e in delete_entries]}')

        to_delete.extend(delete_entries)

    print(f'\nTotal entries to delete: {len(to_delete)}')

    # Delete duplicates
    deleted_count = 0
    for entry in to_delete:
        entry_id = entry.get('id')
        try:
            response = requests.delete(f'http://172.19.53.38:5000/delete_entry/{entry_id}')
            if response.status_code == 200:
                deleted_count += 1
                print(f'✅ Deleted duplicate entry ID {entry_id}')
            else:
                print(f'❌ Failed to delete entry ID {entry_id}: {response.status_code}')
        except Exception as e:
            print(f'❌ Error deleting entry ID {entry_id}: {e}')

    print(f'\n✅ Successfully deleted {deleted_count}/{len(to_delete)} duplicate entries')
    return deleted_count == len(to_delete)

if __name__ == "__main__":
    success = clean_duplicates()
    if success:
        print('\n🎉 Local database cleaned up!')
    else:
        print('\n❌ Cleanup failed')