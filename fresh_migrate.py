#!/usr/bin/env python3
"""
Fresh migration script: Clear production and migrate clean local data
"""

import requests
import sys

LOCAL_URL = "http://127.0.0.1:5000"
PROD_URL = "https://pharmacy-ledger.onrender.com"
ENTRY_TYPES = ["customer", "distributor"]


def fetch_entries(base_url, entry_type):
    try:
        response = requests.get(f"{base_url}/get_entries?type={entry_type}", timeout=15)
        return response.json() if response.status_code == 200 else []
    except Exception:
        return []


def delete_entry(base_url, entry_id):
    try:
        response = requests.delete(f"{base_url}/delete_entry/{entry_id}", timeout=15)
        return response.status_code == 200
    except Exception:
        return False


def fresh_migrate(local_url=None, prod_url=None):
    local_url = local_url or LOCAL_URL
    prod_url = prod_url or PROD_URL

    print('🔄 FRESH MIGRATION: Clearing production and migrating clean local data')
    print('=' * 70)

    # Step 1: Clear production database
    print('Step 1: Clearing production database...')
    total_deleted = 0
    total_remote = 0

    for entry_type in ENTRY_TYPES:
        prod_data = fetch_entries(prod_url, entry_type)
        total_remote += len(prod_data)

        if prod_data:
            for entry in prod_data:
                entry_id = entry.get('id')
                if entry_id and delete_entry(prod_url, entry_id):
                    total_deleted += 1

    print(f'✅ Deleted {total_deleted}/{total_remote} entries from production')

    # Step 2: Get clean local data
    print('\nStep 2: Getting clean local data from local server:', local_url)
    local_data = []
    for entry_type in ENTRY_TYPES:
        data = fetch_entries(local_url, entry_type)
        for entry in data:
            entry['entry_type'] = entry_type
        local_data.extend(data)

    print(f'Found {len(local_data)} entries in local database')

    # Step 3: Migrate to production
    print('\nStep 3: Migrating to production...')
    migrated = 0

    for entry in local_data:
        entry_data = {
            'customer_name': entry.get('name', ''),
            'date': entry.get('date', ''),
            'current_purchase': entry.get('purchase', 0),
            'payment': entry.get('payment', 0),
            'phone': entry.get('phone', ''),
            'type': entry.get('entry_type', 'customer')
        }

        try:
            response = requests.post(f"{prod_url}/add_entry", json=entry_data, timeout=20)
            if response.status_code == 200:
                migrated += 1
                print(f"✅ Migrated: {entry_data['customer_name']} ({entry_data['type']})")
            else:
                print(f"❌ Failed to migrate: {entry_data['customer_name']} - HTTP {response.status_code}")
        except Exception as e:
            print(f"❌ Error migrating entry: {entry_data['customer_name']} - {e}")

    print(f'\n✅ Successfully migrated {migrated}/{len(local_data)} entries')

    # Step 4: Verify
    print('\nStep 4: Verifying migration...')
    final_prod = []
    for entry_type in ENTRY_TYPES:
        final_prod.extend(fetch_entries(prod_url, entry_type))

    print(f'Final production entries: {len(final_prod)}')
    print(f'Local entries: {len(local_data)}')

    if len(final_prod) == len(local_data):
        print('✅ Migration successful! Data is now synchronized.')
        return True
    else:
        print(f'❌ Migration incomplete: {len(final_prod)} vs {len(local_data)}')
        return False


if __name__ == "__main__":
    local_arg = sys.argv[1] if len(sys.argv) > 1 else None
    prod_arg = sys.argv[2] if len(sys.argv) > 2 else None
    success = fresh_migrate(local_arg, prod_arg)
    if success:
        print('\n🎉 Fresh migration completed successfully!')
    else:
        print('\n❌ Fresh migration failed')
