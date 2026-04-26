import os
import requests
from flask import Flask, request, jsonify, render_template, make_response
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

def parse_datetime(date_str):
    """Parse various datetime formats from frontend"""
    if not date_str:
        return datetime.now()
    
    try:
        # Try ISO format first (2026-04-26T10:00)
        return datetime.fromisoformat(date_str.replace('T', ' '))
    except ValueError:
        try:
            # Try direct ISO format
            return datetime.fromisoformat(date_str)
        except ValueError:
            # Fallback to now
            return datetime.now()

app = Flask(__name__)

# ================= DATABASE CONFIG (FIXED) =================
BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# create /database folder if not exists
db_folder = os.path.join(BASE_DIR, "database")
os.makedirs(db_folder, exist_ok=True)

# database path
db_path = os.path.join(db_folder, "ledger.db")


app.config['SQLALCHEMY_DATABASE_URI'] = f"sqlite:///{db_path}"

db_url = os.getenv("DATABASE_URL")
REMOTE_API_URL = os.getenv("REMOTE_API_URL")

if db_url:
    # Render fix (important)
    if db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)

    app.config['SQLALCHEMY_DATABASE_URI'] = db_url
    print("🚀 Using PostgreSQL")
else:
    print("💻 Using SQLite (local)")

if REMOTE_API_URL:
    print(f"🌐 Remote API proxy enabled: {REMOTE_API_URL}")

db = SQLAlchemy(app)

# ================= MODELS =================
class Ledger(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    entry_type = db.Column(db.String(20), default="customer")
    customer_name = db.Column(db.String(100))
    phone = db.Column(db.String(20))
    date = db.Column(db.DateTime)
    current_purchase = db.Column(db.Float)
    payment = db.Column(db.Float)
    balance = db.Column(db.Float)
    previous_balance = db.Column(db.Float, default=0)  # Balance before this entry
    total = db.Column(db.Float, default=0)  # Total purchase amount

class Expense(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100))
    category = db.Column(db.String(50))   
    amount = db.Column(db.Float)
    date = db.Column(db.DateTime)

# ================= CREATE DB =================
with app.app_context():
    db.create_all()
    print("✅ Database created at:", db_path)

# ================= SCHEMA HELPERS =================
def get_table_columns(table_name):
    from sqlalchemy import text
    engine = db.engine
    dialect = engine.dialect.name

    if dialect == 'sqlite':
        result = db.session.execute(text(f"PRAGMA table_info({table_name})"))
        return [row[1] for row in result]

    result = db.session.execute(text(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_name = :table_name ORDER BY ordinal_position"
    ), {"table_name": table_name})
    return [row[0] for row in result]


def add_column_if_missing(table_name, column_name, column_sql):
    columns = get_table_columns(table_name)
    if column_name not in columns:
        from sqlalchemy import text
        db.session.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {column_sql}"))
        db.session.commit()
        return True
    return False


def proxy_request(method, path, **kwargs):
    if not REMOTE_API_URL:
        return None
    url = REMOTE_API_URL.rstrip('/') + path
    response = requests.request(method, url, timeout=20, **kwargs)
    try:
        return jsonify(response.json()), response.status_code
    except ValueError:
        return response.text, response.status_code

@app.route('/import_data', methods=['POST'])
def import_data():
    if REMOTE_API_URL:
        return proxy_request('POST', '/import_data', json=request.get_json())

    try:
        data = request.json
        if not data or 'ledger' not in data:
            return jsonify({"error": "Invalid data format"}), 400

        imported_ledger = 0
        imported_expenses = 0

        # Import ledger entries
        if 'ledger' in data:
            for entry in data['ledger']:
                # Skip if entry already exists (by checking customer_name, date, and amount)
                existing = Ledger.query.filter_by(
                    customer_name=entry['customer_name'],
                    date=parse_datetime(entry['date']),
                    current_purchase=entry.get('current_purchase', 0)
                ).first()

                if not existing:
                    ledger_entry = Ledger(
                        entry_type=entry.get('entry_type', 'customer'),
                        customer_name=entry['customer_name'],
                        phone=entry.get('phone', ''),
                        date=parse_datetime(entry['date']),
                        current_purchase=entry.get('current_purchase', 0),
                        payment=entry.get('payment', 0),
                        balance=entry.get('balance', 0),
                        previous_balance=entry.get('previous_balance', 0),
                        total=entry.get('total', 0)
                    )
                    db.session.add(ledger_entry)
                    imported_ledger += 1

        # Import expenses
        if 'expenses' in data:
            for expense in data['expenses']:
                # Skip if expense already exists
                existing = Expense.query.filter_by(
                    title=expense['title'],
                    date=parse_datetime(expense['date']),
                    amount=expense['amount']
                ).first()

                if not existing:
                    expense_entry = Expense(
                        title=expense['title'],
                        category=expense.get('category', 'other'),
                        amount=expense['amount'],
                        date=parse_datetime(expense['date'])
                    )
                    db.session.add(expense_entry)
                    imported_expenses += 1

        db.session.commit()

        return jsonify({
            "message": f"Imported {imported_ledger} ledger entries and {imported_expenses} expenses",
            "ledger_count": imported_ledger,
            "expenses_count": imported_expenses
        })

    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

# ================= CACHE CONTROL =================
@app.after_request
def add_cache_control(response):
    # Prevent caching for API responses
    if request.path.startswith('/get_') or request.path.startswith('/total_') or request.path.startswith('/add_') or request.path.startswith('/update_') or request.path.startswith('/delete_'):
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    return response

# ================= ROUTES =================

@app.route('/')
def home():
    return render_template('index.html')

# -------- ADD ENTRY --------
@app.route('/add_entry', methods=['POST'])
def add_entry():
    if REMOTE_API_URL:
        return proxy_request('POST', '/add_entry', json=request.get_json())

    data = request.json

    name = data.get('customer_name')
    type_ = data.get("type") or data.get("entry_type") or "customer"

    if not name:
        return jsonify({"error": "Name required"}), 400

    purchase = float(data.get('current_purchase', 0))
    payment = float(data.get('payment', 0))

    last = Ledger.query.filter_by(customer_name=name, entry_type=type_)\
        .order_by(Ledger.id.desc()).first()

    prev_balance = last.balance if last else 0
    balance = prev_balance + purchase - payment

    entry = Ledger(
        entry_type=type_,
        customer_name=name,
        phone=data.get("phone"),
        date=parse_datetime(data.get("date")) if data.get("date") else datetime.now(),
        current_purchase=purchase,
        payment=payment,
        balance=balance,
        previous_balance=prev_balance,
        total=purchase  # Current purchase amount
    )

    db.session.add(entry)
    db.session.commit()

    return jsonify({"message": "Added", "balance": balance})

# -------- GET ENTRIES --------
@app.route('/get_entries')
def get_entries():
    if REMOTE_API_URL:
        return proxy_request('GET', '/get_entries', params=request.args)

    type_ = request.args.get("type", "customer")

    entries = Ledger.query.filter_by(entry_type=type_)\
        .order_by(Ledger.id.desc()).all()

    return jsonify([{
        "id": e.id,
        "date": e.date.strftime("%Y-%m-%d %H:%M"),
        "name": e.customer_name,
        "phone": e.phone,
        "purchase": e.current_purchase,
        "payment": e.payment,
        "balance": e.balance,
        "previous": (e.balance + e.payment - e.current_purchase)
    } for e in entries])

# -------- UPDATE --------
@app.route('/update_entry/<int:id>', methods=['PUT'])
def update_entry(id):
    if REMOTE_API_URL:
        return proxy_request('PUT', f'/update_entry/{id}', json=request.get_json())

    data = request.json
    entry = Ledger.query.get(id)

    if not entry:
        return jsonify({"error": "Not found"}), 404

    entry.customer_name = data.get("customer_name", entry.customer_name)
    entry.phone = data.get("phone", entry.phone)
    entry.current_purchase = float(data.get("current_purchase", entry.current_purchase))
    entry.payment = float(data.get("payment", entry.payment))

    # FULL RECALCULATION
    entries = Ledger.query.filter_by(
        customer_name=entry.customer_name,
        entry_type=entry.entry_type
    ).order_by(Ledger.id.asc()).all()

    running = 0
    for e in entries:
        running += (e.current_purchase or 0) - (e.payment or 0)
        e.balance = running

    db.session.commit()

    return jsonify({"message": "Updated"})

# -------- DELETE --------
@app.route('/delete_entry/<int:id>', methods=['DELETE'])
def delete_entry(id):
    if REMOTE_API_URL:
        return proxy_request('DELETE', f'/delete_entry/{id}')

    entry = Ledger.query.get(id)

    if not entry:
        return jsonify({"error": "Not found"}), 404

    name = entry.customer_name
    type_ = entry.entry_type

    db.session.delete(entry)
    db.session.commit()

    # RECALCULATE AFTER DELETE
    entries = Ledger.query.filter_by(
        customer_name=name,
        entry_type=type_
    ).order_by(Ledger.id.asc()).all()

    running = 0
    for e in entries:
        running += (e.current_purchase or 0) - (e.payment or 0)
        e.balance = running

    db.session.commit()

    return jsonify({"message": "Deleted"})

# -------- DATABASE MIGRATION --------
@app.route('/migrate_db', methods=['POST'])
def migrate_db():
    """Add missing columns to database"""
    try:
        added = []

        if add_column_if_missing('ledger', 'entry_type', "entry_type VARCHAR(20) DEFAULT 'customer'"):
            added.append('entry_type')
        if add_column_if_missing('ledger', 'previous_balance', 'previous_balance FLOAT DEFAULT 0'):
            added.append('previous_balance')
        if add_column_if_missing('ledger', 'total', 'total FLOAT DEFAULT 0'):
            added.append('total')

        if added:
            return jsonify({"message": f"Added columns: {', '.join(added)}"})
        return jsonify({"message": "All required columns already exist"})

    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

# -------- DEBUG COLUMNS --------
@app.route('/debug_columns')
def debug_columns():
    """Debug: Show all columns in ledger table"""
    try:
        columns = get_table_columns('ledger')
        return jsonify({"columns": columns})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# -------- IMPORT ENTRIES (FOR MIGRATION) --------
@app.route('/import_entries', methods=['POST'])
def import_entries():
    try:
        from sqlalchemy import text
        data = request.json
        if not data or 'entries' not in data:
            return jsonify({"error": "No entries provided"}), 400

        imported_count = 0
        for entry_data in data['entries']:
            # Use raw SQL to avoid SQLAlchemy field mapping issues
            sql = """
            INSERT INTO ledger (entry_type, customer_name, phone, date, previous_balance, current_purchase, total, payment, balance)
            VALUES (:entry_type, :customer_name, :phone, :date, :previous_balance, :current_purchase, :total, :payment, :balance)
            """
            
            db.session.execute(text(sql), {
                'entry_type': entry_data.get('type', 'customer'),
                'customer_name': entry_data['customer_name'],
                'phone': entry_data.get('phone', ''),
                'date': parse_datetime(entry_data.get('date')),
                'previous_balance': 0,
                'current_purchase': float(entry_data.get('current_purchase', 0)),
                'total': float(entry_data.get('current_purchase', 0)),
                'payment': float(entry_data.get('payment', 0)),
                'balance': 0  # Will be recalculated
            })
            imported_count += 1

        db.session.commit()

        # Recalculate balances for all customers using raw SQL
        # Get distinct customer_name and entry_type combinations
        customer_query = text("SELECT DISTINCT customer_name, entry_type FROM ledger")
        customers = db.session.execute(customer_query).fetchall()
        
        for customer_name, entry_type in customers:
            # Get all entries for this customer/type ordered by date
            entries_query = text("""
                SELECT id, current_purchase, payment 
                FROM ledger 
                WHERE customer_name = :customer_name AND entry_type = :entry_type 
                ORDER BY date ASC
            """)
            entries = db.session.execute(entries_query, {
                'customer_name': customer_name, 
                'entry_type': entry_type
            }).fetchall()

            running_balance = 0
            for entry in entries:
                running_balance += (entry[1] or 0) - (entry[2] or 0)  # current_purchase - payment
                # Update balance for this entry
                update_query = text("UPDATE ledger SET balance = :balance WHERE id = :id")
                db.session.execute(update_query, {'balance': running_balance, 'id': entry[0]})

        db.session.commit()

        return jsonify({
            "message": f"Imported {imported_count} entries successfully",
            "count": imported_count
        })

    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

# -------- DASHBOARD --------
@app.route('/total_summary')
def total_summary():
    if REMOTE_API_URL:
        return proxy_request('GET', '/total_summary', params=request.args)

    type_ = request.args.get("type", "customer")

    entries = Ledger.query.filter_by(entry_type=type_).all()

    total_purchase = sum(e.current_purchase or 0 for e in entries)
    total_payment = sum(e.payment or 0 for e in entries)
    net = total_purchase - total_payment

    return jsonify({
        "total_purchase": total_purchase,
        "total_payment": total_payment,
        "net": net
    })

# -------- EXPENSE --------
@app.route('/add_expense', methods=['POST'])
def add_expense():
    if REMOTE_API_URL:
        return proxy_request('POST', '/add_expense', json=request.get_json())

    data = request.json

    exp = Expense(
        title=data['title'],
        category=data.get('category', 'other'),
        amount=float(data['amount']),
        date=datetime.fromisoformat(data.get("date")) if data.get("date") else datetime.now()
    )

    db.session.add(exp)
    db.session.commit()

    return jsonify({"message": "Added"})

@app.route('/get_expenses')
def get_expenses():
    if REMOTE_API_URL:
        return proxy_request('GET', '/get_expenses', params=request.args)

    expenses = Expense.query.order_by(Expense.id.desc()).all()

    return jsonify([{
        "title": e.title,
        "amount": e.amount,
        "date": e.date.strftime("%Y-%m-%d %H:%M")
    } for e in expenses])

@app.route('/expense_breakdown')
def expense_breakdown():
    if REMOTE_API_URL:
        return proxy_request('GET', '/expense_breakdown', params=request.args)

    from datetime import datetime, timedelta

    period = request.args.get("period", "last_month")
    now = datetime.now()

    # -------- PERIOD LOGIC --------
    if period == "last_week":
        end = now - timedelta(days=now.weekday()+1)
        start = end - timedelta(days=7)

    elif period == "last_year":
        start = now.replace(year=now.year-1, month=1, day=1)
        end = now.replace(month=1, day=1)

    else:  # last_month
        first = now.replace(day=1)
        end = first
        start = (first - timedelta(days=1)).replace(day=1)

    expenses = Expense.query.filter(
        Expense.date >= start,
        Expense.date < end
    ).all()

    # -------- CATEGORY GROUPING --------
    breakdown = {}

    for e in expenses:
        cat = e.category or "other"
        breakdown[cat] = breakdown.get(cat, 0) + (e.amount or 0)

    total = sum(breakdown.values())

    return jsonify({
        "period": period,
        "total": total,
        "categories": breakdown
    })

# -------- DEBUG --------
@app.route('/test_db')
def test_db():
    return f"DB PATH: {db_path}"

@app.route('/summary')
def summary():
    if REMOTE_API_URL:
        return proxy_request('GET', '/summary', params=request.args)

    type_ = request.args.get("type", "customer")

    entries = Ledger.query.filter_by(entry_type=type_).all()

    total_purchase = sum(e.current_purchase or 0 for e in entries)
    total_payment = sum(e.payment or 0 for e in entries)
    net = total_purchase - total_payment

    return jsonify({
        "total_purchase": total_purchase,
        "total_payment": total_payment,
        "net": net,
        "closing_balance": net
    })

@app.route('/expense_summary')
def expense_summary():
    if REMOTE_API_URL:
        return proxy_request('GET', '/expense_summary', params=request.args)

    from datetime import datetime, timedelta

    period = request.args.get("period", "month")

    now = datetime.now()

    if period == "week":
        start = now - timedelta(days=7)
    elif period == "year":
        start = now.replace(month=1, day=1)
    else:  # month (default)
        start = now.replace(day=1)

    expenses = Expense.query.filter(Expense.date >= start).all()

    total = sum(e.amount or 0 for e in expenses)

    return jsonify({
        "period": period,
        "total": total,
        "count": len(expenses)
    })

@app.route('/expenses_by_range')
def expenses_by_range():
    if REMOTE_API_URL:
        return proxy_request('GET', '/expenses_by_range', params=request.args)

    from datetime import datetime, timedelta

    start = request.args.get("start")
    end = request.args.get("end")

    if not start or not end:
        return jsonify({"error": "Start and End date required"}), 400

    start_dt = datetime.fromisoformat(start).replace(hour=0, minute=0, second=0)
    end_dt = datetime.fromisoformat(end).replace(hour=23, minute=59, second=59)

    expenses = Expense.query.filter(
        Expense.date >= start_dt,
        Expense.date <= end_dt
    ).order_by(Expense.date.desc()).all()

    total = sum(e.amount or 0 for e in expenses)

    return jsonify({
        "total": total,
        "count": len(expenses),
        "data": [
            {
                "date": e.date.strftime("%Y-%m-%d %H:%M"),
                "title": e.title,
                "amount": e.amount,
                "category": e.category
            } for e in expenses
        ]
    })

@app.route('/export_html')
def export_html():
    if REMOTE_API_URL:
        return proxy_request('GET', '/export_html')

    # Export all ledger entries and expenses as HTML
    ledger_entries = Ledger.query.order_by(Ledger.id.asc()).all()
    expenses = Expense.query.order_by(Expense.id.asc()).all()

    # Calculate totals
    total_ledger = len(ledger_entries)
    total_expenses = len(expenses)
    total_ledger_value = sum((e.current_purchase or 0) - (e.payment or 0) for e in ledger_entries)
    total_expenses_value = sum(e.amount or 0 for e in expenses)

    html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pharmacy Ledger Backup - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        h1, h2 {{ color: #333; }}
        table {{ border-collapse: collapse; width: 100%; margin-bottom: 20px; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
        .summary {{ background-color: #e8f4fd; padding: 15px; border-radius: 5px; margin-bottom: 20px; }}
        .customer {{ background-color: #fff2e8; }}
        .distributor {{ background-color: #f0f8e8; }}
    </style>
</head>
<body>
    <h1>Pharmacy Ledger Backup</h1>
    <p><strong>Exported on:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>

    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Ledger Entries:</strong> {total_ledger}</p>
        <p><strong>Total Expenses:</strong> {total_expenses}</p>
        <p><strong>Net Ledger Balance:</strong> ₹{total_ledger_value:.2f}</p>
        <p><strong>Total Expenses:</strong> ₹{total_expenses_value:.2f}</p>
    </div>

    <h2>Ledger Entries</h2>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Type</th>
                <th>Name</th>
                <th>Phone</th>
                <th>Date</th>
                <th>Purchase</th>
                <th>Payment</th>
                <th>Balance</th>
            </tr>
        </thead>
        <tbody>
"""

    for entry in ledger_entries:
        row_class = "customer" if entry.entry_type == "customer" else "distributor"
        html_content += f"""
            <tr class="{row_class}">
                <td>{entry.id}</td>
                <td>{entry.entry_type.title()}</td>
                <td>{entry.customer_name}</td>
                <td>{entry.phone or ''}</td>
                <td>{entry.date.strftime('%Y-%m-%d %H:%M')}</td>
                <td>₹{entry.current_purchase or 0:.2f}</td>
                <td>₹{entry.payment or 0:.2f}</td>
                <td>₹{entry.balance or 0:.2f}</td>
            </tr>
"""

    html_content += """
        </tbody>
    </table>

    <h2>Expenses</h2>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Title</th>
                <th>Category</th>
                <th>Amount</th>
                <th>Date</th>
            </tr>
        </thead>
        <tbody>
"""

    for expense in expenses:
        html_content += f"""
            <tr>
                <td>{expense.id}</td>
                <td>{expense.title}</td>
                <td>{expense.category or 'other'}</td>
                <td>₹{expense.amount or 0:.2f}</td>
                <td>{expense.date.strftime('%Y-%m-%d %H:%M')}</td>
            </tr>
"""

    html_content += """
        </tbody>
    </table>

    <p><em>This backup was generated by Pharmacy Ledger App</em></p>
</body>
</html>
"""

    response = make_response(html_content)
    response.headers['Content-Type'] = 'text/html'
    response.headers['Content-Disposition'] = f'attachment; filename=pharmacy-ledger-backup-{datetime.now().strftime("%Y-%m-%d")}.html'
    return response

from flask import send_from_directory

@app.route('/.well-known/<path:filename>')
def well_known(filename):
    return send_from_directory('static/.well-known', filename)   

# ================= RUN =================
if __name__ == '__main__':
    app.run(host='0.0.0.0', debug=True)