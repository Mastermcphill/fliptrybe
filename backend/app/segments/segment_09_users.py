"""
=====================================================
FLIPTRYBE SEGMENT 9
FINANCIAL CORE
PAYSTACK • ESCROW • WITHDRAWALS
WEBHOOKS • ADMIN SWITCH
RECONCILIATION LEDGER
=====================================================
Do not merge yet.
"""

import os
import hmac
import hashlib
import requests
from datetime import datetime
from uuid import uuid4

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, Transaction, Withdrawal, Order
from app.utils.commission import compute_commission, RATES

# =====================================================
# CONFIG
# =====================================================

PAYSTACK_SECRET = os.getenv("PAYSTACK_SECRET_KEY")
PAYSTACK_BASE = "https://api.paystack.co"

# =====================================================
# MODELS
# =====================================================

class AdminPaymentMode(db.Model):

    __tablename__ = "admin_payment_modes"

    id = db.Column(db.Integer, primary_key=True)

    auto_enabled = db.Column(db.Boolean, default=True)

    updated_at = db.Column(db.DateTime, default=datetime.utcnow)


class ReconciliationEntry(db.Model):

    __tablename__ = "reconciliation_entries"

    id = db.Column(db.Integer, primary_key=True)

    reference = db.Column(db.String(80), unique=True)
    amount = db.Column(db.Float)

    channel = db.Column(db.String(20))
    matched = db.Column(db.Boolean, default=False)

    created_at = db.Column(db.DateTime, default=datetime.utcnow)


# =====================================================
# PAYSTACK HELPERS
# =====================================================

def paystack_headers():

    return {
        "Authorization": f"Bearer {PAYSTACK_SECRET}",
        "Content-Type": "application/json",
    }


# =====================================================
# WALLET FUNDING
# =====================================================

def initialize_payment(user, amount):

    ref = f"FT-{uuid4().hex[:12]}"

    payload = {
        "email": user.email,
        "amount": int(amount * 100),
        "reference": ref,
    }

    r = requests.post(
        f"{PAYSTACK_BASE}/transaction/initialize",
        json=payload,
        headers=paystack_headers(),
        timeout=10,
    )

    return r.json(), ref


# =====================================================
# WEBHOOK
# =====================================================

finance = Blueprint('finance_segment_09_users',
    __name__,
    url_prefix="/api/finance",
)


@finance.route("/webhook/paystack", methods=["POST"])
def paystack_webhook():

    sig = request.headers.get("x-paystack-signature")

    computed = hmac.new(
        PAYSTACK_SECRET.encode(),
        request.data,
        hashlib.sha512,
    ).hexdigest()

    if sig != computed:
        return jsonify({"error": "Invalid"}), 403

    event = request.json

    if event["event"] == "charge.success":

        data = event["data"]

        user = User.query.filter_by(email=data["customer"]["email"]).first()

        amount = data["amount"] / 100

        user.wallet_balance += amount

        tx = Transaction(
            user_id=user.id,
            amount=amount,
            type="Credit",
            reference=data["reference"],
        )

        db.session.add(tx)

        db.session.add(
            ReconciliationEntry(
                reference=data["reference"],
                amount=amount,
                channel="paystack",
                matched=True,
            )
        )

        db.session.commit()

    return jsonify({"status": "ok"})


# =====================================================
# WITHDRAWALS
# =====================================================

def request_withdrawal(user, amount, bank, acct, name):

    if amount > user.wallet_balance:
        raise ValueError("Insufficient funds")

    fee = round(amount * 0.02, 2)
    payout = amount - fee

    user.wallet_balance -= amount

    w = Withdrawal(
        user_id=user.id,
        amount=payout,
        bank_name=bank,
        account_number=acct,
        account_name=name,
        status="Pending",
    )

    tx = Transaction(
        user_id=user.id,
        amount=amount,
        type="Debit",
        reference=f"WDL-{uuid4().hex[:8]}",
    )

    db.session.add(w)
    db.session.add(tx)
    db.session.commit()

    return w


# =====================================================
# ADMIN MODE
# =====================================================

def get_payment_mode():

    mode = AdminPaymentMode.query.first()

    if not mode:
        mode = AdminPaymentMode(auto_enabled=True)
        db.session.add(mode)
        db.session.commit()

    return mode.auto_enabled


def toggle_payment_mode(enabled):

    mode = AdminPaymentMode.query.first()
    mode.auto_enabled = enabled
    db.session.commit()


# =====================================================
# ESCROW RELEASE HOOK
# =====================================================

def release_order_funds(order):

    if not get_payment_mode():
        return False

    seller = order.listing.seller

    gross = float(getattr(order, "total_price", 0.0) or 0.0)
    fee = compute_commission(gross, float(RATES.get("listing_sale", 0.05)))
    seller_amount = round(max(gross - fee, 0.0), 2)

    seller.wallet_balance += seller_amount

    tx = Transaction(
        user_id=seller.id,
        amount=seller_amount,
        type="Credit",
        reference=f"ORD-{order.id}",
    )

    order.status = "Completed"

    db.session.add(tx)
    db.session.commit()

    return True


print("Segment 9 Loaded: Payments Core Active")
