from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()

class Ledger(db.Model):

    id = db.Column(db.Integer, primary_key=True)    
    customer_name = db.Column(db.String(100), nullable=False)    
    date = db.Column(db.DateTime, default=datetime.utcnow)   
    previous_balance = db.Column(db.Float, nullable=False)    
    current_purchase = db.Column(db.Float, default=0)    
    total = db.Column(db.Float, nullable=False)   
    payment = db.Column(db.Float, default=0)    
    balance = db.Column(db.Float, nullable=False)

    phone = db.Column(db.String(15), nullable=True)

    def __repr__(self):
        return f"<Ledger {self.customer_name} - {self.balance}>"   
class Expense(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(150), nullable=False)
    amount = db.Column(db.Float, nullable=False)
    date = db.Column(db.DateTime, default=datetime.utcnow)

    def __repr__(self):
        return f"<Expense {self.title} - {self.amount}>"    