import sqlite3

DB_NAME = "pharmacy.db"

def get_connection():
    return sqlite3.connect(DB_NAME)

def init_db():
    conn = sqlite3.connect("pharmacy.db")
    cursor = conn.cursor()

    # Medicine Master
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS medicine_master (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medicine_name TEXT,
        hsn_code TEXT,
        gst_percent REAL,
        schedule_type TEXT,
        minimum_stock INTEGER,
        suggested_order_qty INTEGER
    )
    """)

    # Batch Master
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS batch_master (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medicine_name TEXT,
        batch_no TEXT,
        expiry_date TEXT,
        purchase_rate REAL,
        mrp REAL,
        supplier TEXT,
        UNIQUE(medicine_name, batch_no)
    )
    """)

    # Purchase Register
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS purchase_register (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        supplier TEXT,
        medicine_name TEXT,
        batch_no TEXT,
        expiry_date TEXT,
        quantity INTEGER,
        purchase_rate REAL,
        mrp REAL,
        gst_percent REAL,
        gst_amount REAL,
        total_amount REAL
    )
    """)

    # Sales Register
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS sales_register (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bill_no TEXT,
        date TEXT,
        medicine_name TEXT,
        batch_no TEXT,
        quantity_sold INTEGER,
        sale_price REAL,
        gst_percent REAL,
        gst_amount REAL,
        total_sale REAL,
        profit REAL
    )
    """)

    # Users Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        role TEXT
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS sales_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT,
        medicine_id INTEGER,
        batch_id INTEGER,
        quantity INTEGER,
        mrp REAL,
        rate REAL,
        gst REAL,
        total REAL,
        profit REAL,           
        sale_date TEXT
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS invoice_master (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT UNIQUE,
        date TEXT,
        total REAL
    )
    """)



    conn.commit()
    conn.close()