import os
import psycopg2
from werkzeug.security import generate_password_hash

def get_connection():
    DATABASE_URL = os.getenv("DATABASE_URL")
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = True
    return conn

def init_db():
    print("🔥 INIT_DB RUNNING")
    conn = get_connection()
    cursor = conn.cursor()

    # Medicine Master
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS medicine_master (
        id SERIAL PRIMARY KEY,
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
        id SERIAL PRIMARY KEY,
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
        id SERIAL PRIMARY KEY,
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
        id SERIAL PRIMARY KEY,
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
        id SERIAL PRIMARY KEY,
        username TEXT UNIQUE,
        password TEXT,
        role TEXT
    )
    """)

    # ✅ HASHED ADMIN USER (FIXED)
    cursor.execute("""
    INSERT INTO users (username, password, role)
    VALUES (%s, %s, %s)
    ON CONFLICT (username) DO NOTHING
    """, ("admin", generate_password_hash("admin123"), "admin"))               

    # Sales Items
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS sales_items (
        id SERIAL PRIMARY KEY,
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

    # Invoice Master
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS invoice_master (
        id SERIAL PRIMARY KEY,
        invoice_no TEXT UNIQUE,
        date TEXT,
        total REAL
    )
    """)

    conn.close()