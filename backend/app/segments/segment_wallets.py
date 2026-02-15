from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, Wallet, WalletTxn, PayoutRequest
from app.utils.jwt_utils import decode_token
from app.utils.wallets import get_or_create_wallet, post_txn, reserve_funds, release_reserved
from app.utils.risk import can_request_payout, txn_velocity_ok
from app.models import AuditLog, PayoutRecipient
from app.utils.commission import resolve_rate
from app.utils.account_flags import record_account_flag, flag_duplicate_bank
from app.models import Receipt
from app.services.fraud import should_block_withdrawal
from app.utils.events import log_event
from app.utils.observability import get_request_id
import os

wallets_bp = Blueprint("wallets_bp", __name__, url_prefix="/api/wallet")

_INIT = False


@wallets_bp.before_app_request
def _ensure_tables_once():
    global _INIT
    if _INIT:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT = True


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user() -> User | None:
    token = _bearer_token()
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    sub = payload.get("sub")
    if not sub:
        return None
    try:
        uid = int(sub)
    except Exception:
        return None
    return User.query.get(uid)


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    try:
        if int(u.id or 0) == 1:
            return True
    except Exception:
        pass
    return "admin" in (u.email or "").lower()


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _is_email_verified(u: User | None) -> bool:
    if not u:
        return False
    return bool(getattr(u, "is_verified", False))


def _platform_user_id() -> int:
    raw = (os.getenv("PLATFORM_USER_ID") or "").strip()
    if raw.isdigit():
        return int(raw)
    try:
        admin = User.query.filter_by(role="admin").order_by(User.id.asc()).first()
        if admin:
            return int(admin.id)
    except Exception:
        pass
    return 1


def _withdrawal_fee_rate(role: str, speed: str) -> float:
    r = (role or "buyer").strip().lower()
    s = (speed or "standard").strip().lower()
    if r == "merchant":
        return 0.0
    if r in ("driver", "inspector"):
        return 0.01 if s == "instant" else 0.0
    # users/buyers
    return 0.015


@wallets_bp.get("")
def my_wallet():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    w = get_or_create_wallet(int(u.id))
    return jsonify({"ok": True, "wallet": w.to_dict()}), 200


@wallets_bp.get("/ledger")
def my_ledger():
    u = _current_user()
    if not u:
        return jsonify([]), 200
    w = get_or_create_wallet(int(u.id))
    rows = WalletTxn.query.filter_by(wallet_id=w.id).order_by(WalletTxn.created_at.desc()).limit(200).all()
    return jsonify([t.to_dict() for t in rows]), 200


@wallets_bp.post("/topup-demo")
def topup_demo():
    """Investor demo credit wallet without Paystack."""
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    try:
        amount = float(payload.get("amount") or 0.0)
    except Exception:
        amount = 0.0
    if amount <= 0:
        return jsonify({"message": "amount required"}), 400

    ref = f"demo_topup:{int(datetime.utcnow().timestamp())}"
    post_txn(user_id=int(u.id), direction="credit", amount=amount, kind="topup", reference=ref, note="Demo topup")
    w = get_or_create_wallet(int(u.id))
    return jsonify({"ok": True, "wallet": w.to_dict()}), 200


@wallets_bp.post("/payouts")
def request_payout():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_email_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403
    fraud_guard = should_block_withdrawal(int(u.id))
    if bool(fraud_guard.get("blocked")):
        return jsonify(
            {
                "ok": False,
                "code": "FRAUD_WITHDRAWAL_BLOCKED",
                "message": "Withdrawal blocked for review due to elevated fraud risk.",
                "fraud_score": int(fraud_guard.get("score") or 0),
            }
        ), 403
    payload = request.get_json(silent=True) or {}
    try:
        amount = float(payload.get("amount") or 0.0)
    except Exception:
        amount = 0.0
    if amount <= 0:
        return jsonify({"message": "amount required"}), 400

    bank_name = (payload.get("bank_name") or "").strip()
    account_number = (payload.get("account_number") or "").strip()
    account_name = (payload.get("account_name") or "").strip()
    if not account_number:
        try:
            record_account_flag(int(u.id), "SUSPICIOUS_SIGNAL", signal="missing_bank_account", details={
                "bank_name": bank_name,
                "account_name": account_name,
            })
        except Exception:
            pass
    if account_number:
        try:
            dup_users = flag_duplicate_bank(int(u.id), account_number, bank_name=bank_name, account_name=account_name)
            if dup_users:
                return jsonify({"message": "Bank account already in use by another account"}), 409
        except Exception:
            pass
    speed_raw = (payload.get("speed") or "").strip().lower()
    instant_flag = payload.get("instant")
    speed = "instant" if (speed_raw == "instant" or instant_flag is True) else "standard"

    role = _role(u)
    fee_rate = _withdrawal_fee_rate(role, speed)
    fee_amount = round(float(amount) * float(fee_rate), 2)
    if fee_amount < 0:
        fee_amount = 0.0
    net_amount = round(float(amount) - float(fee_amount), 2)
    if net_amount < 0:
        net_amount = 0.0

    w = get_or_create_wallet(int(u.id))
    if float(w.balance or 0.0) < amount:
        return jsonify({"message": "Insufficient wallet balance"}), 400

    pr = PayoutRequest(
        user_id=int(u.id),
        amount=float(amount),
        fee_amount=float(fee_amount),
        net_amount=float(net_amount),
        speed=speed,
        status="pending",
        bank_name=bank_name,
        account_number=account_number,
        account_name=account_name,
        updated_at=datetime.utcnow(),
    )

    try:
        db.session.add(pr)
        db.session.commit()
        log_event(
            "payout_requested",
            actor_user_id=int(u.id),
            subject_type="payout",
            subject_id=int(pr.id),
            request_id=get_request_id(),
            idempotency_key=f"payout_requested:{int(pr.id)}",
            metadata={"amount": float(pr.amount or 0.0), "speed": pr.speed or "standard"},
        )
        return jsonify({"ok": True, "payout": pr.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@wallets_bp.get("/payouts")
def list_payouts():
    u = _current_user()
    if not u:
        return jsonify([]), 200
    rows = PayoutRequest.query.filter_by(user_id=int(u.id)).order_by(PayoutRequest.created_at.desc()).limit(200).all()
    return jsonify([p.to_dict() for p in rows]), 200


@wallets_bp.post("/payouts/<int:payout_id>/admin/mark-paid")
def admin_mark_paid(payout_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    p = PayoutRequest.query.get(payout_id)
    if not p:
        return jsonify({"message": "Not found"}), 404

    if p.status == "paid":
        return jsonify({"ok": True, "payout": p.to_dict()}), 200

    # compute fees if missing (legacy payout requests)
    fee_amount = float(getattr(p, "fee_amount", 0.0) or 0.0)
    net_amount = float(getattr(p, "net_amount", 0.0) or 0.0)
    speed = (getattr(p, "speed", "standard") or "standard").strip().lower()
    try:
        pay_user = User.query.get(int(p.user_id))
    except Exception:
        pay_user = None
    if fee_amount <= 0.0 and net_amount <= 0.0:
        rate = _withdrawal_fee_rate(_role(pay_user), speed)
        fee_amount = round(float(p.amount or 0.0) * float(rate), 2)
        net_amount = round(float(p.amount or 0.0) - float(fee_amount), 2)

    # debit wallet (gross amount)
    ref = f"payout:{int(p.id)}"
    post_txn(
        user_id=int(p.user_id),
        direction="debit",
        amount=float(p.amount or 0.0),
        kind="payout",
        reference=ref,
        note="Payout paid",
    )

    # credit platform fee ledger (non-merchant fees only)
    try:
        if fee_amount > 0:
            post_txn(
                user_id=_platform_user_id(),
                direction="credit",
                amount=float(fee_amount),
                kind="withdrawal_fee",
                reference=ref,
                note="Withdrawal fee",
            )
    except Exception:
        pass

    p.status = "paid"
    try:
        p.fee_amount = float(fee_amount)
        p.net_amount = float(net_amount)
        p.speed = speed
    except Exception:
        pass
    p.updated_at = datetime.utcnow()

    try:
        db.session.add(p)
        db.session.commit()
        log_event(
            "payout_released",
            actor_user_id=int(u.id) if u is not None else None,
            subject_type="payout",
            subject_id=int(p.id),
            request_id=get_request_id(),
            idempotency_key=f"payout_released:{int(p.id)}",
            metadata={"amount": float(p.amount or 0.0), "fee_amount": float(fee_amount or 0.0)},
        )
        return jsonify({"ok": True, "payout": p.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@wallets_bp.get("/admin/payouts")
def admin_list_payouts():
    u = _current_user()
    if not _is_admin(u):
        return jsonify([]), 200
    status = (request.args.get("status") or "").strip()
    qry = PayoutRequest.query
    if status:
        qry = qry.filter_by(status=status)
    rows = qry.order_by(PayoutRequest.created_at.desc()).limit(300).all()
    return jsonify([p.to_dict() for p in rows]), 200


@wallets_bp.post("/payouts/<int:payout_id>/admin/approve")
def admin_approve(payout_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    p = PayoutRequest.query.get(payout_id)
    if not p:
        return jsonify({"message": "Not found"}), 404
    if p.status in ("paid", "rejected"):
        return jsonify({"ok": True, "payout": p.to_dict()}), 200
    p.status = "approved"
    p.updated_at = datetime.utcnow()
    try:
        db.session.add(p)
        db.session.commit()
        log_event(
            "payout_approved",
            actor_user_id=int(u.id) if u is not None else None,
            subject_type="payout",
            subject_id=int(p.id),
            request_id=get_request_id(),
            idempotency_key=f"payout_approved:{int(p.id)}",
            metadata={"status": p.status or "approved"},
        )
        return jsonify({"ok": True, "payout": p.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@wallets_bp.post("/payouts/<int:payout_id>/admin/reject")
def admin_reject(payout_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    p = PayoutRequest.query.get(payout_id)
    if not p:
        return jsonify({"message": "Not found"}), 404
    if p.status == "paid":
        return jsonify({"message": "Already paid"}), 400
    # Release reserved funds back to available
    try:
        release_reserved(int(p.user_id), float(p.amount or 0.0))
    except Exception:
        pass

    p.status = "rejected"
    p.updated_at = datetime.utcnow()
    try:
        db.session.add(p)
        db.session.commit()
        return jsonify({"ok": True, "payout": p.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500



@wallets_bp.post("/payouts/<int:payout_id>/admin/process")
def admin_process_payout(payout_id: int):
    """Simulated payout processing (demo): approve then mark paid."""
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    p = PayoutRequest.query.get(payout_id)
    if not p:
        return jsonify({"message": "Not found"}), 404

    if p.status not in ("pending", "approved"):
        return jsonify({"ok": True, "payout": p.to_dict()}), 200

    if p.status == "pending":
        p.status = "approved"
        p.updated_at = datetime.utcnow()

    try:
        db.session.add(p)
        db.session.commit()
    except Exception:
        db.session.rollback()

    # call mark-paid logic by reusing existing function flow
    # (simple: just flip status and debit wallet)
    # We'll do the same as admin_mark_paid route expects:
    # status paid + wallet debit happens there
    # easiest: set status approved then return and user can mark paid, but for demo we proceed:
    return admin_mark_paid(payout_id)


@wallets_bp.post("/payouts/<int:payout_id>/admin/pay")
def admin_pay_payout_alias(payout_id: int):
    """Compatibility alias used by older admin console clients."""
    return admin_process_payout(payout_id)
