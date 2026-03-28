from flask import Flask, render_template, request, session
import sqlite3
from flask import jsonify
from database import init_db

app = Flask(__name__)
app.secret_key = "pharmacy_secret_key"

from flask import redirect

init_db()

def get_connection():
    return sqlite3.connect("pharmacy.db", timeout=10, check_same_thread=False)

@app.before_request
def require_login():
    allowed_routes = ["login", "static"]

    if request.endpoint not in allowed_routes:
        if "user_id" not in session:
            return redirect("/login")

@app.route("/")
def home():
    return render_template("index.html")

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


@app.route("/purchase", methods=["GET", "POST"])
def purchase():
    if request.method == "POST":
        print("FORM SUBMITTED")

        data = request.form

        date = data["date"]
        supplier = data["supplier"]
        medicine_name = data["medicine_name"]
        batch_no = data["batch_no"]
        expiry_date = data["expiry_date"]
        quantity = int(data["quantity"]) if data["quantity"] else 0
        purchase_rate = float(data["purchase_rate"]) if data["purchase_rate"] else 0
        mrp = float(data["mrp"]) if data["mrp"] else 0
        gst_percent = float(data["gst_percent"]) if data["gst_percent"] else 0

        subtotal = purchase_rate * quantity
        gst_amount = (subtotal * gst_percent) / 100
        total_amount = subtotal + gst_amount

        print("DATA CALCULATED")

        conn = get_connection()
        cursor = conn.cursor()

        print("DB CONNECTED")

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

        print("INSERT DONE")

        conn.commit()
        conn.close()

        print("COMMIT DONE")

    return render_template("purchase.html")


from datetime import datetime

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

    from datetime import datetime, timedelta
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
        SUM(quantity) as stock
    FROM purchase_register
    GROUP BY medicine_name, batch_no
    HAVING SUM(quantity) >=0 AND MAX(expiry_date) != ''
    ORDER BY MAX(expiry_date) ASC
    """)

    stock_data = cursor.fetchall()
    conn.close()

    bill = session.get("bill", [])
    return render_template("sales.html", stock=stock_data, bill=bill)


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
            "message": f"Only {qty - remaining_qty} available for {medicine}"
        })

    session["bill"] = temp

    updated_stock = []

    for batch_no, stock, mrp in batches:
        used = 0
        for item in session["bill"]:
            if item["medicine"] == medicine and item["batch"] == batch_no:
                used = item["qty"]
                break

        updated_stock.append({
            "batch": batch_no,
            "medicine": medicine,
            "stock": stock - used
        })

    return jsonify({
        "status": "success",
        "bill": session["bill"],
        "updated_stock": updated_stock
    })


@app.route("/bill")
def show_bill():
    if "bill" not in session:
        session["bill"] = []

    bill = session["bill"]
    grand_total = sum(item["total"] for item in bill)

    today = datetime.now().strftime("%Y-%m-%d")

    return render_template("bill.html", bill=bill, total=grand_total, date=today)


@app.route("/finalize", methods=["POST"])
def finalize():
    if "bill" not in session:
        return "No items in bill"

    bill = session["bill"]

    conn = get_connection()
    cursor = conn.cursor()
    conn.execute("BEGIN")

    date = datetime.now().strftime("%Y-%m-%d")
    invoice_no = "INV" + datetime.now().strftime("%Y%m%d%H%M%S")

    grand_total = sum(item["total"] for item in bill)

    cursor.execute("""
    INSERT INTO invoice_master (invoice_no, date, total)
    VALUES (?, ?, ?)
    """, (invoice_no, date, grand_total))

    for item in bill:
        medicine = item["medicine"]
        batch = item["batch"]
        qty = item["qty"]

        cursor.execute("""
        SELECT SUM(quantity)
        FROM purchase_register
        WHERE medicine_name=? AND batch_no=?
        """, (medicine, batch))

        current_stock = cursor.fetchone()[0] or 0

        if qty > current_stock:
            conn.close()
            return f"Error: Not enough stock for {medicine} ({batch})"

        cursor.execute("""
        SELECT purchase_rate, gst_percent
        FROM purchase_register
        WHERE medicine_name=? AND batch_no=?
        LIMIT 1
        """, (medicine, batch))

        purchase_rate, gst = cursor.fetchone()

        mrp = item["mrp"]
        total = mrp * qty
        profit = (mrp - purchase_rate) * qty

        cursor.execute("""
        INSERT INTO purchase_register 
        (date, supplier, medicine_name, batch_no, expiry_date,
        quantity, purchase_rate, mrp, gst_percent, gst_amount, total_amount)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            date, "SALE", medicine, batch, "",
            -qty, purchase_rate, mrp, gst, 0, -total
        ))

        cursor.execute("""
        INSERT INTO sales_items
        (invoice_no, medicine_id, batch_id, quantity, mrp, rate, gst, total, profit, sale_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            invoice_no, 0, 0, qty, mrp, purchase_rate, gst, total, profit, date
        ))

    conn.commit()
    conn.close()

    session["bill"] = []
    return f"Invoice {invoice_no} saved successfully"


@app.route("/remove_item", methods=["POST"])
def remove_item():
    index = int(request.form["index"])

    if "bill" in session:
        bill = session["bill"]

        if 0 <= index < len(bill):
            bill[index]["qty"] -= 1
            bill[index]["total"] = bill[index]["qty"] * bill[index]["mrp"]

            if bill[index]["qty"] <= 0:
                bill.pop(index)

            session["bill"] = bill

    return jsonify({
        "status": "success",
        "bill": session.get("bill", [])
    })


# ✅ FINAL FIXED ROUTE
@app.route("/update_qty", methods=["POST"])
def update_qty():
    index = int(request.form["index"])
    action = request.form["action"]
    new_qty = request.form.get("new_qty")

    if "bill" not in session:
        return jsonify({"status": "error"})

    bill = session["bill"]

    if not (0 <= index < len(bill)):
        return jsonify({"status": "error"})

    item = bill[index]
    medicine = item["medicine"]
    batch = item["batch"]

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT SUM(quantity)
    FROM purchase_register
    WHERE medicine_name=? AND batch_no=?
    """, (medicine, batch))

    stock = cursor.fetchone()[0] or 0
    conn.close()

    # ➕
    if action == "plus":
        if item["qty"] + 1 <= stock:
            item["qty"] += 1

    # ➖
    elif action == "minus":
        item["qty"] -= 1
        if item["qty"] <= 0:
            bill.pop(index)

    # ✏️ SET
    elif action == "set":
        try:
            new_qty = int(new_qty)
            if 0 < new_qty <= stock:
                item["qty"] = new_qty
            elif new_qty <= 0:
                bill.pop(index)
        except:
            pass

    # 🔄 recalc totals
    for i in bill:
        i["total"] = i["qty"] * i["mrp"]

    session["bill"] = bill

    return jsonify({
        "status": "success",
        "bill": bill,
        "total": sum(i["total"] for i in bill)
    })


if __name__ == "__main__":
    app.run(debug=True)