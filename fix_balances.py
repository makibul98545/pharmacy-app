#!/usr/bin/env python3
"""
Fix Balance Recalculation Script
Recalculates balances for all customers in production
"""

import requests
import json

def fix_balances(production_url="https://pharmacy-ledger.onrender.com"):
    """Fix balance calculations in production"""

    print("🔧 Fixing balance calculations in production...")

    # Get all entries from production
    try:
        response = requests.get(f"{production_url}/get_entries?type=customer")
        if response.status_code != 200:
            response = requests.get(f"{production_url}/get_entries?type=distributor")
        if response.status_code != 200:
            print("❌ Cannot fetch data from production")
            return False

        all_entries = response.json()
        print(f"Found {len(all_entries)} entries in production")

    except Exception as e:
        print(f"❌ Error fetching data: {e}")
        return False

    # Group entries by customer and type
    customers = {}
    for entry in all_entries:
        customer_name = entry.get('name', '')
        # For now, assume all are customer type since we can't determine from API
        customer_key = customer_name

        if customer_key not in customers:
            customers[customer_key] = []
        customers[customer_key].append(entry)

    print(f"Found {len(customers)} unique customers")

    # Calculate correct balances for each customer
    corrections = []
    for customer_name, entries in customers.items():
        # Sort entries by date (assuming they come in reverse chronological order from API)
        # Reverse to get chronological order
        entries_sorted = sorted(entries, key=lambda x: x.get('id', 0))  # Sort by ID ascending

        running_balance = 0
        for entry in entries_sorted:
            purchase = entry.get('purchase', 0) or 0
            payment = entry.get('payment', 0) or 0
            running_balance += purchase - payment

            current_balance = entry.get('balance', 0) or 0
            if abs(running_balance - current_balance) > 0.01:  # Allow small floating point differences
                corrections.append({
                    'id': entry.get('id'),
                    'name': customer_name,
                    'current_balance': current_balance,
                    'correct_balance': running_balance,
                    'difference': running_balance - current_balance
                })

    if not corrections:
        print("✅ All balances are already correct!")
        return True

    print(f"Found {len(corrections)} entries with incorrect balances")

    # Show corrections
    print("\nBALANCE CORRECTIONS NEEDED:")
    for corr in corrections[:5]:  # Show first 5
        print(f"  ID {corr['id']} ({corr['name']}): {corr['current_balance']} → {corr['correct_balance']} (diff: {corr['difference']})")

    if len(corrections) > 5:
        print(f"  ... and {len(corrections) - 5} more")

    # Apply corrections via API
    print("\n📤 Applying corrections...")
    corrected_count = 0

    for corr in corrections:
        try:
            # Use the update endpoint to fix balance
            update_data = {
                'balance': corr['correct_balance']
            }
            response = requests.put(
                f"{production_url}/update_entry/{corr['id']}",
                json=update_data,
                headers={'Content-Type': 'application/json'}
            )

            if response.status_code == 200:
                corrected_count += 1
            else:
                print(f"❌ Failed to update entry {corr['id']}: {response.status_code}")

        except Exception as e:
            print(f"❌ Error updating entry {corr['id']}: {e}")

    print(f"✅ Successfully corrected {corrected_count}/{len(corrections)} balances")
    return corrected_count > 0

if __name__ == "__main__":
    print("🛠️  BALANCE FIXING SCRIPT")
    print("=" * 30)

    success = fix_balances()
    if success:
        print("\n🎉 Balance fix completed!")
        print("Check your production app - balances should now be correct.")
    else:
        print("\n❌ Balance fix failed or no corrections needed.")