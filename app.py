from flask import send_file
from openpyxl import Workbook
import io
import shutil
from datetime import datetime, timedelta
from models import db, Ledger, Expense
from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
import threading
import os
import sys

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

app = Flask(__name__)
CORS(app)    

os.makedirs(os.path.join(BASE_DIR, 'database'), exist_ok=True)

db_path = os.path.join(BASE_DIR, 'database', 'ledger.db')

import os

DATABASE_URL = os.environ.get("DATABASE_URL")

if DATABASE_URL:
    if DATABASE_URL.startswith("postgres://"):
        DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)
        
    app.config['SQLALCHEMY_DATABASE_URI'] = DATABASE_URL
else:
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///' + db_path

app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

def create_daily_backup():
    try:
        backup_dir = os.path.join(os.getcwd(), 'backups')
        os.makedirs(backup_dir, exist_ok=True)

        today_str = datetime.now().strftime("%Y-%m-%d")
        backup_file = os.path.join(backup_dir, f'ledger_backup_{today_str}.db')

        if os.path.exists(db_path):
            shutil.copy2(db_path, backup_file)
            print(f"Backup overwritten: {backup_file}")
        else:
            print("Database not found.")

        # Google Drive upload disabled (manual only)
        # from gdrive_backup import upload_backup_to_drive
        # upload_backup_to_drive(backup_file)     

    except Exception as e:
        print(f"Backup error: {e}")      

def recalculate_ledger_safe(customer_name):
    entries = Ledger.query.filter_by(customer_name=customer_name)\
                            .order_by(Ledger.date.asc(), Ledger.id.asc()).all()

    previous_balance = 0

    for entry in entries:
        calculated_total = previous_balance + entry.current_purchase
        calculated_balance = calculated_total - entry.payment

        entry.previous_balance = previous_balance
        entry.total = calculated_total
        entry.balance = calculated_balance

        previous_balance = calculated_balance

    db.session.commit()

# Home (UI)
@app.route('/')
def home():
    return render_template('index.html')

# Add Entry API
@app.route('/add_entry', methods=['POST'])
def add_entry():
    try:
        data = request.get_json()

        date_str = data.get('date')

        if date_str:
            try:
                entry_date = datetime.strptime(date_str, "%Y-%m-%dT%H:%M")
            except:
                entry_date = datetime.utcnow()
        else:
            entry_date = datetime.utcnow()

        customer_name = data.get('customer_name')
        current_purchase = float(data.get('current_purchase', 0))
        payment = float(data.get('payment', 0))

        last_entry = Ledger.query.filter_by(customer_name=customer_name)\
                                 .order_by(Ledger.date.desc(), Ledger.id.desc()).first()

        previous_balance = 0
        total = current_purchase
        balance = current_purchase - payment

        new_entry = Ledger(
            customer_name=customer_name,
            phone=data.get("phone"),
            date=entry_date,
            previous_balance=previous_balance,
            current_purchase=current_purchase,
            total=total,
            payment=payment,
            balance=balance
        )

        db.session.add(new_entry)
        db.session.commit()
        
        recalculate_ledger_safe(customer_name)
        create_daily_backup()

        return jsonify({
            "message": "Entry added successfully",
            "balance": balance
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
@app.route('/get_entries', methods=['GET'])
def get_entries():
    entries = Ledger.query.order_by(Ledger.date.desc(), Ledger.id.desc()).all()

    data = []
    for e in entries:
        data.append({
            "id": e.id, 
            "date": e.date.strftime("%Y-%m-%d %H:%M"),
            "name": e.customer_name,
            "phone": e.phone,
            "previous": e.previous_balance,
            "purchase": e.current_purchase,
            "total": e.total,
            "payment": e.payment,
            "balance": e.balance
        })

    return jsonify(data)

@app.route('/get_entries_by_name', methods=['GET'])
def get_entries_by_name():
    name = request.args.get('name')

    if not name:
        return jsonify([]) 

    entries = Ledger.query.filter(
        Ledger.customer_name.ilike(f"%{name}%")
    ).order_by(Ledger.id.desc()).all()

    data = []
    for e in entries:
        data.append({
            "id": e.id,
            "date": e.date.strftime("%Y-%m-%d %H:%M"),
            "name": e.customer_name,
            "phone": e.phone,
            "previous": e.previous_balance,
            "purchase": e.current_purchase,
            "total": e.total,
            "payment": e.payment,
            "balance": e.balance
        })

    return jsonify(data)

# Update Entry
@app.route('/update_entry/<int:id>', methods=['PUT'])
def update_entry(id):
    try:
        entry = Ledger.query.get(id)
        if not entry:
            return jsonify({"error": "Entry not found"}), 404

        data = request.get_json()

        old_name = entry.customer_name

        # --- DATE ---
        date_str = data.get('date')
        if date_str:
            try:
                entry.date = datetime.strptime(date_str, "%Y-%m-%dT%H:%M")
            except:
                pass
   
        #--- NAME ---#
        entry.customer_name = data.get('customer_name', entry.customer_name)

        # --- VALUES ---
        entry.current_purchase = float(data.get('current_purchase', entry.current_purchase))
        entry.payment = float(data.get('payment', entry.payment))

        db.session.commit()

        # Recalculate BOTH (important if name changed)
        recalculate_ledger_safe(old_name)
        recalculate_ledger_safe(entry.customer_name)

        create_daily_backup()

        return jsonify({"message": "Entry updated"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/fix_all')
def fix_all():
    names = db.session.query(Ledger.customer_name).distinct().all()

    for n in names:
        recalculate_ledger_safe(n[0])

    return "All recalculated"

# Delete Entry
@app.route('/delete_entry/<int:id>', methods=['DELETE'])
def delete_entry(id):
    try:
        entry = Ledger.query.get(id)
        if not entry:
            return jsonify({"error": "Entry not found"}), 404
        
        customer_name = entry.customer_name

        db.session.delete(entry)
        db.session.commit()

        recalculate_ledger_safe(customer_name)
        create_daily_backup()

        return jsonify({"message": "Entry deleted"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/daily_summary', methods=['GET'])
def daily_summary():
    today = datetime.now().date()   # ✅ only date, no time

    entries = Ledger.query.all()

    today_entries = [
        e for e in entries
        if e.date.date() == today
    ]

    total_purchase = sum(e.current_purchase for e in today_entries)
    total_payment = sum(e.payment for e in today_entries)

    net = total_purchase - total_payment

    return jsonify({
        "total_purchase": total_purchase,
        "total_payment": total_payment,
        "net": net
    })

@app.route('/export_excel', methods=['GET'])
def export_excel():
    try:
        entries = Ledger.query.order_by(Ledger.id.asc()).all()

        wb = Workbook()
        ws = wb.active
        ws.title = "Ledger"

        # Header
        ws.append([
            "Date", "Name", "Previous",
            "Purchase", "Total", "Payment", "Balance"
        ])

        # Data rows
        for e in entries:
            ws.append([
                e.date.strftime("%Y-%m-%d %H:%M"),
                e.customer_name,
                e.previous_balance,
                e.current_purchase,
                e.total,
                e.payment,
                e.balance
            ])

        # Save to memory
        output = io.BytesIO()
        wb.save(output)
        output.seek(0)

        return send_file(
            output,
            as_attachment=True,
            download_name="ledger.xlsx",
            mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
@app.route('/download_backup', methods=['GET'])
def download_backup():
    try:
        db_file_path = db_path  # already defined in your app

        return send_file(
            db_file_path,
            as_attachment=True,
            download_name="ledger_backup.db"
        )

    except Exception as e:
        return jsonify({"error": str(e)}), 500   
    
def ensure_columns():
    try:
        from sqlalchemy import text

        with db.engine.connect() as conn:
            result = conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name='ledger'
            """))

            columns = [row[0] for row in result]

            if "phone" not in columns:
                conn.execute(text("ALTER TABLE ledger ADD COLUMN phone VARCHAR"))
                print("✅ Added missing column: phone")

    except Exception as e:
        print("Column check error:", e)        

with app.app_context():
    db.create_all()
    ensure_columns()
    create_daily_backup()     

from datetime import datetime, timedelta
from models import db, Ledger, Expense

@app.route('/summary', methods=['GET'])
def summary():
    filter_type = request.args.get('filter', 'today')

    now = datetime.now()

    if filter_type == "today":
        start = datetime(now.year, now.month, now.day)
        end = start + timedelta(days=1)

    elif filter_type == "week":

        # last 7 days (including today)
        start = (now - timedelta(days=6)).replace(hour=0, minute=0, second=0, microsecond=0)
        end = now

    elif filter_type == "15days":

        start = (now - timedelta(days=14)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        end = now    
   
    elif filter_type == "month":
        start = datetime(now.year, now.month, 1)
        if now.month == 12:
            end = datetime(now.year + 1, 1, 1)
        else:
            end = datetime(now.year, now.month + 1, 1)

    elif filter_type == "3months":

        # Get absolute first entry in DB
        first_entry = Ledger.query.order_by(Ledger.date.asc()).first()

        if first_entry:
            start = datetime(first_entry.date.year, first_entry.date.month, first_entry.date.day)
        else:
            start = now

        end = now.replace(hour=23, minute=59, second=59, microsecond=999999)

    elif filter_type == "year":

        # last 12 months (rolling)
        start = now - timedelta(days=365)
        start = start.replace(hour=0, minute=0, second=0, microsecond=0)

        end = now.replace(hour=23, minute=59, second=59, microsecond=999999)        

    elif filter_type == "custom":
        start_date = request.args.get("start")
        end_date = request.args.get("end")

        if not start_date or not end_date:
            return jsonify({"error": "Missing dates"}), 400

        start = datetime.strptime(start_date, "%Y-%m-%d")
        end = datetime.strptime(end_date, "%Y-%m-%d") + timedelta(days=1)

    else:
        return jsonify({"error": "Invalid filter"}), 400
    
    previous_entries = Ledger.query.filter(
        Ledger.date < start
    ).all()

    opening_balance = sum(
        (e.current_purchase or 0) - (e.payment or 0)
        for e in previous_entries
    )
    
    entries = Ledger.query.filter(
        Ledger.date >= start,
        Ledger.date <= end
    ).all()

    total_purchase = sum(e.current_purchase for e in entries)
    total_payment = sum(e.payment for e in entries)

    expenses = Expense.query.filter(
        Expense.date >= start,
        Expense.date <= end
    ).all()

    total_expense = sum(e.amount for e in expenses)

    net = total_purchase - total_payment
    last_entry = Ledger.query.filter(
        Ledger.date <= end
    ).order_by(Ledger.date.desc(), Ledger.id.desc()).first()

    closing_balance = last_entry.balance if last_entry else 0

    return jsonify({
        "opening_balance": opening_balance,
        "total_purchase": total_purchase,
        "total_payment": total_payment,
        "total_expense": total_expense,
        "net": net,
        "closing_balance": closing_balance
    })

@app.route('/fix_dates')
def fix_dates():
    entries = Ledger.query.all()

    fixed_count = 0

    for e in entries:
        # Fix invalid year like 0026 → 2026
        if e.date.year < 2000:
            e.date = e.date.replace(year=2026)  # adjust if needed
            fixed_count += 1

    db.session.commit()

    return f"Fixed {fixed_count} entries"

@app.route('/total_summary', methods=['GET'])
def total_summary():

    entries = Ledger.query.order_by(Ledger.date.asc(), Ledger.id.asc()).all()

    if not entries:
        return jsonify({
            "total_purchase": 0,
            "total_payment": 0,
            "net": 0
        })

    last_entry = entries[-1]

    total_purchase = sum(e.current_purchase for e in entries)
    total_payment = sum(e.payment for e in entries)

    return jsonify({
        "total_purchase": total_purchase,
        "total_payment": total_payment,
        "net": last_entry.balance   # ✅ FIX
    })  

@app.route('/restore_backup', methods=['POST'])
def restore_backup():
    try:
        data = request.get_json()
        filename = data.get("filename")

        if not filename:
            return jsonify({"error": "No file selected"}), 400

        backup_dir = os.path.join(BASE_DIR, 'backups')
        backup_path = os.path.join(backup_dir, filename)

        if not os.path.exists(backup_path):
            return jsonify({"error": "Backup file not found"}), 404

        # 🔒 Step 1: backup current DB before restore
        safety_backup = os.path.join(
            backup_dir,
            f"pre_restore_{datetime.now().strftime('%Y%m%d_%H%M%S')}.db"
        )

        if os.path.exists(db_path):
            shutil.copy2(db_path, safety_backup)

        # 🔁 Step 2: restore
        shutil.copy2(backup_path, db_path)

        return jsonify({
            "message": "Database restored successfully",
            "safety_backup": os.path.basename(safety_backup)
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500    
    
@app.route('/list_backups', methods=['GET'])
def list_backups():
    try:
        backup_dir = os.path.join(BASE_DIR, 'backups')

        if not os.path.exists(backup_dir):
            return jsonify([])

        files = sorted(os.listdir(backup_dir), reverse=True)

        return jsonify(files)

    except Exception as e:
        return jsonify({"error": str(e)}), 500    
    
@app.route('/add_expense', methods=['POST'])
def add_expense():
    try:
        data = request.get_json()

        title = data.get("title")
        amount = float(data.get("amount", 0))

        date_str = data.get("date")

        if date_str:
            try:
                expense_date = datetime.strptime(date_str, "%Y-%m-%dT%H:%M")
            except:
                expense_date = datetime.utcnow()
        else:
            expense_date = datetime.utcnow()

        if not title or amount <= 0:
            return jsonify({"error": "Invalid data"}), 400

        expense = Expense(title=title, amount=amount, date=expense_date)

        db.session.add(expense)
        db.session.commit()

        create_daily_backup()

        return jsonify({"message": "Expense added"})

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
@app.route('/get_expenses', methods=['GET'])
def get_expenses():
    expenses = Expense.query.order_by(Expense.date.desc()).all()

    return jsonify([
        {
            "id": e.id,
            "title": e.title,
            "amount": e.amount,
            "date": e.date.strftime("%Y-%m-%d %H:%M")
        } for e in expenses
    ])

@app.route('/delete_expense/<int:id>', methods=['DELETE'])
def delete_expense(id):
    try:
        exp = Expense.query.get(id)
        if not exp:
            return jsonify({"error": "Not found"}), 404

        db.session.delete(exp)
        db.session.commit()

        create_daily_backup()

        return jsonify({"message": "Deleted"})

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
@app.route('/upload_to_drive', methods=['GET'])
def upload_to_drive():
    try:
        from gdrive_backup import upload_backup_to_drive

        backup_dir = os.path.join(BASE_DIR, 'backups')

        if not os.path.exists(backup_dir):
            return jsonify({"error": "No backups found"}), 404

        files = sorted(os.listdir(backup_dir), reverse=True)

        if not files:
            return jsonify({"error": "No backup files"}), 404

        latest_file = files[0]
        file_path = os.path.join(backup_dir, latest_file)

        success = upload_backup_to_drive(file_path)

        if success:
            return jsonify({"message": f"Uploaded {os.path.basename(file_path)}"})
        else:
            return jsonify({"error": "Upload failed"}), 500

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
import requests

@app.route('/send_sms', methods=['POST'])
def send_sms():
    data = request.json
    phone = data.get("phone")
    message = data.get("message")

    url = "https://www.fast2sms.com/dev/bulkV2"

    payload = {
        "route": "q",
        "message": message,
        "language": "english",
        "flash": 0,
        "numbers": phone
    }

    headers = {
        "authorization": "5mLNk04EuPbqQehSgriX8n7AoTz3jpKGwCl2DWYcFRa1sVJyHt7JCdFP3hbnMK9wrfla5DvjxW2B6OHX",
        "Content-Type": "application/json"
    }

    try:
        response = requests.post(url, json=payload, headers=headers)

        print("SMS RESPONSE RAW:", response.text)

        res = response.json()

        if res.get("return") == True:
            return jsonify({"success": True})
        else:
            return jsonify({
                "success": False,
                "error": res.get("message", "Unknown error"),
                "full": res
            })

    except Exception as e:
        return jsonify({"success": False, "error": str(e)}) 

@app.route('/get_customers_summary', methods=['GET'])
def get_customers_summary():
    from collections import defaultdict

    customers = {}

    entries = Ledger.query.order_by(Ledger.date.asc(), Ledger.id.asc()).all()

    for e in entries:
        key = e.customer_name.strip().lower()

        customers[key] = {
            "name": e.customer_name,
            "phone": e.phone or "",
            "balance": e.balance   # always latest due to ordering
        }

    return jsonify(list(customers.values()))

def run_flask():
    app.run(host="127.0.0.1", port=5000, debug=False)

if __name__ == "__main__":
    if os.environ.get("RENDER"):
        port = int(os.environ.get("PORT", 5000))
        app.run(host="0.0.0.0", port=port)
    else:
        import webview
        t = threading.Thread(target=run_flask)
        t.daemon = True
        t.start()

        webview.create_window(
            "MM LifeCare Medical Ledger",
            "http://127.0.0.1:5000",
            width=1200,
            height=800
        )
        webview.start()