from dotenv import load_dotenv
load_dotenv()
from flask import Flask, render_template, request, session, jsonify, redirect
from datetime import datetime
from database import get_connection, init_db
from werkzeug.security import check_password_hash, generate_password_hash

# ✅ NEW IMPORTS (SAFE)
import os
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "fallback_key")

UPDATE_LOG = {
    "v1.1.0": [
        "Added update popup system",
        "Manual 'View Updates' button in settings",
        "Improved UI animations"
    ],
    "v1.0.0": [
        "Initial release",
        "Purchase, Stock, Sales modules added",
        "Dark mode + UI improvements",
        "Year dropdown calendar upgrade"
    ]
}

APP_VERSION = list(UPDATE_LOG.keys())[0]

def setup():
    init_db()  

# ✅ UPLOAD CONFIG (SAFE)
UPLOAD_FOLDER = "static/uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# ✅ ✅ CENTRAL NOTIFICATION SYSTEM
def notify(message, category="success"):
    session["toast"] = {
        "message": message,
        "category": category
    }

# ✅ CACHE CONTROL FIX
@app.after_request
def add_header(response):
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response

# LOGIN PROTECTION
@app.before_request
def require_login():
    if request.endpoint is None:
        return
    if request.endpoint in ["login", "static", "forgot_username", "forgot_password"]:
        return
    if "user_id" not in session:
        return redirect("/login")

# ✅ CONTEXT (UPDATED)
@app.context_processor
def inject_user():
    toast = session.pop("toast", None)

    last_seen = session.get("seen_version")
    show_update = last_seen != APP_VERSION   

    if show_update:
        session["seen_version"] = APP_VERSION

    latest_updates = list(UPDATE_LOG.items())[:2]    

    return dict(
        current_user=session.get("user_id"),
        current_role=session.get("role"),
        display_name=session.get("display_name", "User"),
        toast=toast,
        app_version=APP_VERSION,
        show_update=show_update,
        latest_updates=latest_updates
    )

# HOME
@app.route("/")
def home():
    # ===== DATE FILTER =====
    filter_type = request.args.get("filter", "all")

    start_date = request.args.get("start")
    end_date = request.args.get("end")

    date_condition = ""

    today_str = datetime.now().strftime("%Y-%m-%d")
    month_str = datetime.now().strftime("%Y-%m")

    if filter_type == "today":
        date_condition = f"WHERE date = '{today_str}'"

    elif filter_type == "month":
        date_condition = f"WHERE TO_CHAR(TO_DATE(date, 'YYYY-MM-DD'), 'YYYY-MM') = '{month_str}'"

    elif filter_type == "custom" and start_date and end_date:
        date_condition = f"WHERE date BETWEEN '{start_date}' AND '{end_date}'"

    print("FILTER:", filter_type)
    print("DATE CONDITION:", date_condition)     

    conn = get_connection()
    cursor = conn.cursor()

    monthly_labels = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    monthly_values = [0]*12

    cursor.execute(f"""
    SELECT EXTRACT(MONTH FROM TO_DATE(date, 'YYYY-MM-DD')), SUM(total)
    FROM invoice_master
    {date_condition}
    GROUP BY EXTRACT(MONTH FROM TO_DATE(date, 'YYYY-MM-DD'))            
    """)

    for month, total in cursor.fetchall():
        monthly_values[int(month)-1] = total

    weekly_labels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
    weekly_values = [0]*7

    cursor.execute(f"""
    SELECT EXTRACT(DOW FROM TO_DATE(date, 'YYYY-MM-DD')), SUM(total)
    FROM invoice_master
    {date_condition}               
    GROUP BY EXTRACT(DOW FROM TO_DATE(date, 'YYYY-MM-DD'))
    """)

    for day, total in cursor.fetchall():
        weekly_values[int(day)] = total

    cursor.execute("SELECT SUM(quantity) FROM purchase_register WHERE quantity <= 5")
    low_stock = cursor.fetchone()[0] or 0

    cursor.execute("SELECT SUM(quantity) FROM purchase_register WHERE quantity <= 2")
    critical_stock = cursor.fetchone()[0] or 0

    # TOTAL SOLD
    cursor.execute(f"""
    SELECT COALESCE(SUM(total),0) FROM invoice_master
    {date_condition}
    """)
    total_sold = cursor.fetchone()[0]

    # EXPIRY ANALYSIS
    cursor.execute("SELECT expiry_date, quantity FROM purchase_register WHERE quantity > 0")
    rows = cursor.fetchall()

    today = datetime.today().date()

    expired = days_30 = days_60 = days_90 = safe = 0

    for expiry, qty in rows:
        try:
            exp_date = datetime.strptime(expiry, "%Y-%m-%d").date()
            diff = (exp_date - today).days

            if diff < 0:
                expired += qty
            elif diff <= 30:
                days_30 += qty
            elif diff <= 60:
                days_60 += qty
            elif diff <= 90:
                days_90 += qty
            else:
                safe += qty
        except:
            pass
    # TOP SELLING MEDICINES
    cursor.execute("""
     SELECT medicine_name, SUM(quantity) as total_qty
    FROM purchase_register
    GROUP BY medicine_name
    ORDER BY total_qty DESC
    LIMIT 5
    """)

    top_data = cursor.fetchall()

    top_labels = [row[0] for row in top_data]
    top_values = [row[1] for row in top_data]  

    # ===== PROFIT CALCULATION =====
    cursor.execute("""
    SELECT 
        COALESCE(SUM((mrp - purchase_rate) * quantity), 0)
    FROM purchase_register
    WHERE quantity > 0
    """)

    total_profit = cursor.fetchone()[0]  

    conn.close()

    return render_template(
        "dashboard.html",
        total_sold=total_sold,
        expired=expired,
        days_30=days_30,
        days_60=days_60,
        days_90=days_90,
        safe=safe,
        monthly_labels=monthly_labels,
        monthly_values=monthly_values,
        low_stock=low_stock,
        critical_stock=critical_stock,
        weekly_labels=weekly_labels,
        weekly_values=weekly_values,
        top_labels=top_labels,
        top_values=top_values,
        total_profit=total_profit,
    
    )

# ---------------- SETTINGS ----------------
@app.route("/settings")
def settings():
    return render_template("settings.html")

# ✅ SET DISPLAY NAME
@app.route("/set_name", methods=["POST"])
def set_name():
    name = request.form.get("name")
    if name:
        session["display_name"] = name
        notify("Profile name updated successfully", "success")
    return redirect("/settings")

# ---------------- PROFILE UPLOAD ----------------
@app.route("/upload_profile", methods=["POST"])
def upload_profile():
    if "profile_pic" not in request.files:
        return jsonify({"status": "error"})

    file = request.files["profile_pic"]

    if file.filename == "":
        return jsonify({"status": "error"})

    filename = secure_filename(file.filename)
    filepath = os.path.join(UPLOAD_FOLDER, filename)
    file.save(filepath)

    session["profile_pic"] = "/" + filepath

    return jsonify({
        "status": "success",
        "path": "/" + filepath
    })

# LOGIN
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, password, role FROM users WHERE username=%s", (username,))
        user = cursor.fetchone()
        conn.close()

        if user and check_password_hash(user[1], password):
            session["user_id"] = user[0]
            session["role"] = user[2]
            session["display_name"] = username
            return redirect("/")
        else:
            notify("Invalid credentials", "error")
            return render_template("login.html")

    return render_template("login.html")

# ---------------- FORGOT USERNAME ----------------
@app.route("/forgot_username", methods=["GET", "POST"])
def forgot_username():
    username = None

    if request.method == "POST":
        user_input = request.form.get("user_id")

        conn = get_connection()
        cursor = conn.cursor()

        # ✅ FIX: SUPPORT BOTH ID AND USERNAME
        cursor.execute(
            "SELECT username FROM users WHERE id=%s OR username=%s",
            (user_input, user_input)
        )

        user = cursor.fetchone()
        conn.close()

        if user:
            username = user[0]
        else:
            notify("User not found", "error")

    return render_template("forgot_username.html", username=username)


# ---------------- FORGOT PASSWORD ----------------
@app.route("/forgot_password", methods=["GET", "POST"])
def forgot_password():
    if request.method == "POST":
        username = request.form.get("username")
        new_password = request.form.get("new_password")

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM users WHERE username=%s", (username,))
        user = cursor.fetchone()

        if user:
            hashed = generate_password_hash(new_password)
            cursor.execute("UPDATE users SET password=%s WHERE username=%s", (hashed, username))
            conn.commit()
            conn.close()

            notify("Password reset successful", "success")
            return redirect("/login")
        else:
            conn.close()
            notify("Username not found", "error")

    return render_template("forgot_password.html")

# ---------------- CHANGE PASSWORD ----------------
@app.route("/change_password", methods=["GET", "POST"])
def change_password():
    if request.method == "POST":
        current = request.form["current_password"]
        new = request.form["new_password"]

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT password FROM users WHERE id=%s", (session["user_id"],))
        user = cursor.fetchone()

        if user and check_password_hash(user[0], current):
            new_hash = generate_password_hash(new)
            cursor.execute("UPDATE users SET password=%s WHERE id=%s", (new_hash, session["user_id"]))
            conn.commit()
            conn.close()

            notify("Password updated successfully", "success")
            return render_template("change_password.html")
        else:
            conn.close()

            notify("Wrong current password", "error")
            return render_template("change_password.html")

    return render_template("change_password.html")

# ---------------- CHANGE USERNAME ----------------
@app.route("/change_username", methods=["GET", "POST"])
def change_username():
    if request.method == "POST":
        new_username = request.form["new_username"]

        conn = get_connection()
        cursor = conn.cursor()

        try:
            cursor.execute("UPDATE users SET username=%s WHERE id=%s", (new_username, session["user_id"]))
            conn.commit()
            conn.close()

            session["display_name"] = new_username
            notify("Username updated successfully", "success")

            return render_template("change_username.html")
        except:
            conn.close()

            notify("Username already exists", "error")
            return render_template("change_username.html")

    return render_template("change_username.html")

# LOGOUT
@app.route("/logout")
def logout():
    session.clear()
    return redirect("/login")

# ---------------- PURCHASE ----------------
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
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            data["date"], data["supplier"], data["medicine_name"],
            data["batch_no"], data["expiry_date"],
            quantity, purchase_rate, mrp, gst_percent, gst_amount, total_amount
        ))

        conn.commit()
        conn.close()

        notify("Purchase saved successfully", "success")

    return render_template("purchase.html")

# ---------------- EXPIRY ----------------
@app.route("/expiry")
def expiry():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT medicine_name, batch_no, MAX(expiry_date), SUM(quantity)
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

# ---------------- STOCK ----------------
@app.route("/stock")
def stock():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT 
        medicine_name, batch_no, MAX(mrp), MAX(purchase_rate),
        MAX(expiry_date), SUM(quantity)
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
            status = "Invalid"

        stock_data.append((medicine, batch, mrp, ptr, expiry, qty, status))

    return render_template("stock.html", stock=stock_data)

# ---------------- SELL ----------------
@app.route("/sell", methods=["POST"])
def sell():
    medicine = request.form["medicine_name"]
    qty = int(request.form["quantity"])

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT SUM(quantity), MAX(mrp)
        FROM purchase_register
        WHERE medicine_name=%s
    """, (medicine,))
    data = cursor.fetchone()

    if not data or data[0] < qty:
        return jsonify({"status": "error", "message": "Not enough stock"})

    mrp = data[1]
    total = mrp * qty

    bill = session.get("bill", [])

    found = False
    for item in bill:
        if item["medicine"] == medicine:
            item["qty"] += qty
            item["total"] = item["qty"] * mrp
            found = True
            break

    if not found:
        bill.append({
            "medicine": medicine,
            "qty": qty,
            "mrp": mrp,
            "total": total
        })

    session["bill"] = bill

    updated_stock = [{
        "medicine": medicine,
        "stock": data[0] - qty
    }]

    return jsonify({
        "status": "success",
        "bill": bill,
        "updated_stock": updated_stock
    })

# ---------------- UPDATE QTY ----------------
@app.route("/update_qty", methods=["POST"])
def update_qty():
    index = int(request.form["index"])
    action = request.form["action"]

    bill = session.get("bill", [])

    if index >= len(bill):
        return jsonify({"status": "error"})

    item = bill[index]

    if action == "plus":
        item["qty"] += 1
    elif action == "minus":
        if item["qty"] > 1:
            item["qty"] -= 1
    elif action == "set":
        new_qty = int(request.form["new_qty"])
        if new_qty >= 1:
            item["qty"] = new_qty

    item["total"] = item["qty"] * item["mrp"]
    session["bill"] = bill

    return jsonify({"status": "success"})

# ---------------- SALES ----------------
@app.route("/sales")
def sales():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
    SELECT medicine_name, batch_no, MAX(expiry_date),
           MAX(mrp), MAX(purchase_rate), SUM(quantity)
    FROM purchase_register
    GROUP BY medicine_name, batch_no
    HAVING SUM(quantity) > 0
    ORDER BY MAX(expiry_date) ASC
    """)

    stock_data = cursor.fetchall()
    conn.close()

    bill = session.get("bill", [])
    return render_template("sales.html", stock=stock_data, bill=bill)

# ---------------- BILL ----------------
@app.route("/bill")
def bill_page():
    bill = session.get("bill", [])
    total = sum(item["total"] for item in bill)
    date = datetime.now().strftime("%Y-%m-%d")

    return render_template("bill.html", bill=bill, total=total, date=date)

# ---------------- INVOICES ----------------
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

# ---------------- FINALIZE ----------------
@app.route("/finalize", methods=["POST"])
def finalize():
    if "bill" not in session:
        return "No items"

    bill = session["bill"]

    conn = get_connection()
    cursor = conn.cursor()

    for item in bill:
        qty_to_reduce = item["qty"]
        medicine = item["medicine"]

        cursor.execute("""
            SELECT id, quantity FROM purchase_register
            WHERE medicine_name=%s AND quantity > 0
            ORDER BY expiry_date ASC
        """, (medicine,))

        batches = cursor.fetchall()

        for batch_id, stock in batches:
            if qty_to_reduce <= 0:
                break

            if stock >= qty_to_reduce:
                cursor.execute("""
                    UPDATE purchase_register
                    SET quantity = quantity - %s
                    WHERE id=%s
                """, (qty_to_reduce, batch_id))
                qty_to_reduce = 0
            else:
                cursor.execute("""
                    UPDATE purchase_register
                    SET quantity = 0
                    WHERE id=%s
                """, (batch_id,))
                qty_to_reduce -= stock

    invoice_no = "INV" + datetime.now().strftime("%Y%m%d%H%M%S")
    total = sum(item["total"] for item in bill)

    cursor.execute("""
    INSERT INTO invoice_master (invoice_no, date, total)
    VALUES (%s, %s, %s)
    """, (invoice_no, datetime.now().strftime("%Y-%m-%d"), total))

    conn.commit()
    conn.close()

    session["bill"] = []
    session["last_invoice"] = invoice_no

    return redirect("/success")

# ---------------- SUCCESS ----------------
@app.route("/success")
def success():
    invoice_no = session.get("last_invoice")
    return render_template("success.html", invoice_no=invoice_no)

@app.route("/version")
def version():
    return {"version": APP_VERSION}

# RUN
if __name__ == "__main__":
    init_db()
    app.run(debug=False)