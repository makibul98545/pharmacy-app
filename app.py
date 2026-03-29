from flask import Flask, render_template, request, session, jsonify, redirect
import sqlite3
from datetime import datetime
from database import init_db

app = Flask(__name__)
app.secret_key = "pharmacy_secret_key"

# ✅ INIT DB FIRST
init_db()

# ✅ DEFINE CONNECTION FIRST (CRITICAL FIX)
def get_connection():
    return sqlite3.connect("pharmacy.db", timeout=10, check_same_thread=False)

# ✅ CREATE DEFAULT ADMIN SAFELY
def create_default_admin():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        role TEXT
    )
    """)

    cursor.execute("""
    INSERT OR IGNORE INTO users (username, password, role)
    VALUES ('admin', 'admin123', 'admin')
    """)

    conn.commit()
    conn.close()

create_default_admin()

# 🔐 LOGIN PROTECTION
@app.before_request
def require_login():
    allowed_routes = ["login", "static"]

    if request.endpoint not in allowed_routes:
        if "user_id" not in session:
            return redirect("/login")

@app.route("/")
def home():
    return render_template("index.html")

# 🔐 LOGIN
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
        SELECT id, role FROM users
        WHERE username=? AND password=?
        """, (username, password))

        user = cursor.fetchone()
        conn.close()

        if user:
            session["user_id"] = user[0]
            session["role"] = user[1]
            return redirect("/")
        else:
            return render_template("login.html", error="Invalid credentials")

    return render_template("login.html")

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/login")

# 📦 PURCHASE
@app.route("/purchase", methods=["GET", "POST"])
def purchase():
    if request.method == "POST":
        data = request.form

        quantity = int(data["quantity"]) if data["quantity"] else 0
        purchase_rate = float(data["purchase_rate"]) if data["purchase_rate"] else 0
        mrp = float(data["mrp"]) if data["mrp"] else 0
        gst_percent = float(data["gst_percent"]) if data["gst_percent"] else 0

        subtotal = purchase_rate * quantity
        gst_amount = (subtotal * gst_percent) / 100
        total_amount = subtotal + gst_amount

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("""
        INSERT INTO purchase_register
        (date, supplier, medicine_name, batch_no, expiry_date,
         quantity, purchase_rate, mrp, gst_percent, gst_amount, total_amount)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            data["date"], data["supplier"], data["medicine_name"],
            data["batch_no"], data["expiry_date"],
            quantity, purchase_rate, mrp, gst_percent, gst_amount, total_amount
        ))

        conn.commit()
        conn.close()

    return render_template("purchase.html")

# 📊 STOCK
@app.route("/stock")
def stock():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT 
        medicine_name, 
        batch_no, 
        MAX(mrp), 
        MAX(purchase_rate), 
        MAX(expiry_date),
        SUM(quantity)
    FROM purchase_register
    GROUP BY medicine_name, batch_no
    HAVING SUM(quantity) > 0
    """)

    data = cursor.fetchall()
    conn.close()

    stock_data = []
    today = datetime.today().date()

    for row in data:
        medicine, batch, mrp, ptr, expiry, qty = row

        try:
            expiry_date = datetime.strptime(expiry, "%Y-%m-%d").date()
            if expiry_date < today:
                status = "Expired"
            elif qty <= 5:
                status = "Low Stock"
            else:
                status = "OK"
        except:
            status = "Invalid Date"

        stock_data.append((medicine, batch, mrp, ptr, expiry, qty, status))

    return render_template("stock.html", stock=stock_data)

# ⏳ EXPIRY
@app.route("/expiry")
def expiry():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT 
        medicine_name,
        batch_no,
        expiry_date,
        SUM(quantity)
    FROM purchase_register
    GROUP BY medicine_name, batch_no
    HAVING SUM(quantity) > 0
    """)

    data = cursor.fetchall()
    conn.close()

    today = datetime.today().date()
    expiry_list = []

    for med, batch, expiry, qty in data:
        try:
            exp_date = datetime.strptime(expiry, "%Y-%m-%d").date()
            days_left = (exp_date - today).days

            if days_left < 0:
                status = "Expired"
            elif days_left <= 30:
                status = "Near Expiry"
            else:
                status = "Safe"
        except:
            status = "Invalid"

        expiry_list.append((med, batch, expiry, qty, status))

    return render_template("expiry.html", data=expiry_list)

# 🧾 INVOICES
@app.route("/invoices")
def invoices():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT invoice_no, date, total
    FROM invoice_master
    ORDER BY id DESC
    """)

    data = cursor.fetchall()
    conn.close()

    return render_template("invoices.html", invoices=data)

# 💰 SALES PAGE
@app.route("/sales")
def sales():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT 
        medicine_name,
        batch_no,
        MAX(expiry_date),
        MAX(mrp),
        MAX(purchase_rate),
        SUM(quantity)
    FROM purchase_register
    GROUP BY medicine_name, batch_no
    HAVING SUM(quantity) >= 0 AND MAX(expiry_date) != ''
    ORDER BY MAX(expiry_date) ASC
    """)

    stock_data = cursor.fetchall()
    conn.close()

    bill = session.get("bill", [])
    return render_template("sales.html", stock=stock_data, bill=bill)

# ➕ SELL (UNCHANGED CORE LOGIC)
@app.route("/sell", methods=["POST"])
def sell():
    if "bill" not in session:
        session["bill"] = []

    data = request.form
    medicine = data["medicine_name"]
    qty = int(data["quantity"])

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT batch_no, SUM(quantity), MAX(mrp)
    FROM purchase_register
    WHERE medicine_name=?
    GROUP BY batch_no
    HAVING SUM(quantity) > 0
    AND DATE(MAX(expiry_date)) >= DATE('now')               
    ORDER BY MAX(expiry_date) ASC
    """, (medicine,))

    batches = cursor.fetchall()
    conn.close()

    remaining_qty = qty
    temp = session["bill"]

    for batch_no, stock, mrp in batches:
        if remaining_qty <= 0:
            break

        already_used = 0
        for item in temp:
            if item["medicine"] == medicine and item["batch"] == batch_no:
                already_used = item["qty"]
                break

        available_stock = stock - already_used
        if available_stock <= 0:
            continue

        take_qty = min(available_stock, remaining_qty)

        found = False
        for item in temp:
            if item["medicine"] == medicine and item["batch"] == batch_no:
                item["qty"] += take_qty
                item["total"] = item["qty"] * item["mrp"]
                found = True
                break

        if not found:
            temp.append({
                "medicine": medicine,
                "batch": batch_no,
                "qty": take_qty,
                "mrp": mrp,
                "total": mrp * take_qty
            })

        remaining_qty -= take_qty

    if remaining_qty > 0:
        return jsonify({
            "status": "error",
            "message": f"Only {qty - remaining_qty} available"
        })

    session["bill"] = temp

    return jsonify({
        "status": "success",
        "bill": session["bill"]
    })

# 🧾 FINALIZE BILL (UNCHANGED)
@app.route("/finalize", methods=["POST"])
def finalize():
    if "bill" not in session:
        return "No items"

    bill = session["bill"]

    conn = get_connection()
    cursor = conn.cursor()
    conn.execute("BEGIN")

    date = datetime.now().strftime("%Y-%m-%d")
    invoice_no = "INV" + datetime.now().strftime("%Y%m%d%H%M%S")

    total = sum(item["total"] for item in bill)

    cursor.execute("""
    INSERT INTO invoice_master (invoice_no, date, total)
    VALUES (?, ?, ?)
    """, (invoice_no, date, total))

    for item in bill:
        cursor.execute("""
        INSERT INTO purchase_register 
        (date, supplier, medicine_name, batch_no, expiry_date,
        quantity, purchase_rate, mrp, gst_percent, gst_amount, total_amount)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            date, "SALE", item["medicine"], item["batch"], "",
            -item["qty"], item["mrp"], item["mrp"], 0, 0, -item["total"]
        ))

    conn.commit()
    conn.close()

    session["bill"] = []
    return f"Invoice {invoice_no} saved"
