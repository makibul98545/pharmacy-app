from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class Ledger(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    customer_name = db.Column(db.String(100))
    phone = db.Column(db.String(20))
    date = db.Column(db.DateTime)
    previous_balance = db.Column(db.Float, default=0)
    current_purchase = db.Column(db.Float, default=0)
    total = db.Column(db.Float, default=0)
    payment = db.Column(db.Float, default=0)
    balance = db.Column(db.Float, default=0)

class Expense(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100))
    amount = db.Column(db.Float)
    date = db.Column(db.DateTime)