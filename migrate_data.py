#!/usr/bin/env python3
"""
Data Migration Script
Migrates data from local SQLite to production PostgreSQL
"""

import json
import requests
import sys

def migrate_data(production_url="https://pharmacy-ledger.onrender.com"):
    """
    Migrate data from data_export.json to production
    """

    print("🔧 Step 1: Running database migration...")

    # First, run database migration to add missing columns
    try:
        response = requests.post(
            f"{production_url}/migrate_db",
            headers={"Content-Type": "application/json"},
            timeout=30
        )

        if response.status_code == 200:
            result = response.json()
            print(f"✅ Database migration: {result.get('message', 'Migration completed')}")
        else:
            print(f"❌ Database migration failed: HTTP {response.status_code}")
            print(f"Response: {response.text}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"❌ Database migration network error: {e}")
        return False

    # Load exported data
    try:
        with open('data_export.json', 'r') as f:
            entries = json.load(f)
    except FileNotFoundError:
        print("❌ Error: data_export.json not found. Run the export first.")
        return False
    except json.JSONDecodeError as e:
        print(f"❌ Error reading JSON file: {e}")
        return False

    if not entries:
        print("⚠️  No entries to import")
        return True

    print(f"📤 Step 2: Importing {len(entries)} entries to production...")

    # Send to production
    payload = {"entries": entries}

    try:
        response = requests.post(
            f"{production_url}/import_data",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=60  # Longer timeout for bulk import
        )

        if response.status_code == 200:
            result = response.json()
            print(f"✅ Success: {result.get('message', 'Import completed')}")
            return True
        else:
            print(f"❌ Error: HTTP {response.status_code}")
            print(f"Response: {response.text}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"❌ Network error: {e}")
        return False

if __name__ == "__main__":
    print("🚀 Starting data migration...")
    print("This will import local data to production database")
    print()

    # Allow custom URL
    url = sys.argv[1] if len(sys.argv) > 1 else "https://pharmacy-ledger.onrender.com"

    success = migrate_data(url)
    if success:
        print("🎉 Migration completed successfully!")
        print("Check your Render app and mobile app - data should now be visible.")
    else:
        print("💥 Migration failed. Check the errors above.")
        sys.exit(1)