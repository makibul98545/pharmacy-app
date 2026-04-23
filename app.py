import os
from flask import Flask, request, jsonify, render_template
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

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
        date=datetime.fromisoformat(data.get("date")) if data.get("date") else datetime.now(),
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

# ================= RUN =================
if __name__ == '__main__':
    app.run(debug=True)