import os
from flask import Flask, request, jsonify, render_template
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

if db_url:
    # Render fix (important)
    if db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)

    app.config['SQLALCHEMY_DATABASE_URI'] = db_url
    print("🚀 Using PostgreSQL")
else:
    print("💻 Using SQLite (local)")

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
    data = request.json

    name = data.get('customer_name')
    type_ = data.get("type", "customer")

    if not name:
        return jsonify({"error": "Name required"}), 400

    purchase = float(data.get('current_purchase', 0))
    payment = float(data.get('payment', 0))

    last = Ledger.query.filter_by(customer_name=name, entry_type=type_)\
        .order_by(Ledger.id.desc()).first()

    prev = last.balance if last else 0
    balance = prev + purchase - payment

    entry = Ledger(
        entry_type=type_,
        customer_name=name,
        phone=data.get("phone"),
        date=parse_datetime(data.get("date")) if data.get("date") else datetime.now(),
        current_purchase=purchase,
        payment=payment,
        balance=balance
    )

    db.session.add(entry)
    db.session.commit()

    return jsonify({"message": "Added", "balance": balance})

# -------- GET ENTRIES --------
@app.route('/get_entries')
def get_entries():
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
        from sqlalchemy import text

        # Check if entry_type column exists
        result = db.session.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='ledger' AND column_name='entry_type'"))

        if not result.fetchone():
            # Add entry_type column with default value
            db.session.execute(text("ALTER TABLE ledger ADD COLUMN entry_type VARCHAR(20) DEFAULT 'customer'"))
            db.session.commit()
            return jsonify({"message": "entry_type column added successfully"})
        else:
            return jsonify({"message": "entry_type column already exists"})

    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

# -------- IMPORT DATA (FOR MIGRATION) --------
@app.route('/import_data', methods=['POST'])
def import_data():
    try:
        data = request.json
        if not data or 'entries' not in data:
            return jsonify({"error": "No entries provided"}), 400

        imported_count = 0
        for entry_data in data['entries']:
            # Create entry
            entry = Ledger(
                entry_type=entry_data.get('type', 'customer'),
                customer_name=entry_data['customer_name'],
                phone=entry_data.get('phone', ''),
                date=parse_datetime(entry_data.get('date')),
                previous_balance=0,  # Required field
                current_purchase=float(entry_data.get('current_purchase', 0)),
                payment=float(entry_data.get('payment', 0)),
                balance=0  # Will be recalculated
            )
            db.session.add(entry)
            imported_count += 1

        db.session.commit()

        # Recalculate balances for all customers
        customers = db.session.query(Ledger.customer_name, Ledger.entry_type).distinct().all()
        for customer_name, entry_type in customers:
            entries = Ledger.query.filter_by(
                customer_name=customer_name,
                entry_type=entry_type
            ).order_by(Ledger.date.asc()).all()

            running_balance = 0
            for entry in entries:
                running_balance += (entry.current_purchase or 0) - (entry.payment or 0)
                entry.balance = running_balance

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
    expenses = Expense.query.order_by(Expense.id.desc()).all()

    return jsonify([{
        "title": e.title,
        "amount": e.amount,
        "date": e.date.strftime("%Y-%m-%d %H:%M")
    } for e in expenses])

@app.route('/expense_breakdown')
def expense_breakdown():
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

from flask import send_from_directory

@app.route('/.well-known/<path:filename>')
def well_known(filename):
    return send_from_directory('static/.well-known', filename)   

# ================= RUN =================
if __name__ == '__main__':
    app.run(host='0.0.0.0', debug=True)