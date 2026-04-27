#!/usr/bin/env python3
"""
Database Migration Script
Adds missing columns to existing database
"""

import os
import sys
from flask import Flask
from models import db

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

def run_migration():
    """Add missing columns to database"""

    # Create Flask app context
    app = Flask(__name__)

    # Database configuration
    BASE_DIR = os.path.abspath(os.path.dirname(__file__))
    db_folder = os.path.join(BASE_DIR, "database")
    os.makedirs(db_folder, exist_ok=True)
    db_path = os.path.join(db_folder, "ledger.db")

    app.config['SQLALCHEMY_DATABASE_URI'] = f"sqlite:///{db_path}"

    db_url = os.getenv("DATABASE_URL")
    if db_url:
        if db_url.startswith("postgres://"):
            db_url = db_url.replace("postgres://", "postgresql://", 1)
        app.config['SQLALCHEMY_DATABASE_URI'] = db_url

    db.init_app(app)

    with app.app_context():
        try:
            # Check if entry_type column exists in ledger
            columns = get_table_columns('ledger')
            if 'entry_type' not in columns:
                print("Adding entry_type column...")
                # Add entry_type column with default value
                db.session.execute(text("ALTER TABLE ledger ADD COLUMN entry_type VARCHAR(20) DEFAULT 'customer'"))
                db.session.commit()
                print("✅ entry_type column added successfully")
            else:
                print("✅ entry_type column already exists")

            # Check if category column exists in expense
            columns = get_table_columns('expense')
            if 'category' not in columns:
                print("Adding category column to expense table...")
                # Add category column with default value
                db.session.execute(text("ALTER TABLE expense ADD COLUMN category VARCHAR(50) DEFAULT 'other'"))
                db.session.commit()
                print("✅ category column added successfully")
            else:
                print("✅ category column already exists")

            print("🎉 Database migration completed!")

        except Exception as e:
            print(f"❌ Migration failed: {e}")
            db.session.rollback()
            return False

    return True

if __name__ == "__main__":
    print("🚀 Starting database migration...")
    success = run_migration()
    if success:
        print("✅ Migration completed successfully!")
    else:
        print("💥 Migration failed!")
        sys.exit(1)