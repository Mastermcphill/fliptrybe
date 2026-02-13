from __future__ import annotations

from datetime import datetime
import json

from flask import Blueprint, jsonify, request

from app.extensions import db
from sqlalchemy.exc import IntegrityError
from app.models import User, MoneyBoxAccount, MoneyBoxLedger, RoleChangeRequest
from app.utils.jwt_utils import decode_token
from app.utils.moneybox import (
    TIER_CONFIG,
    get_or_create_account,
    set_account_cycle,
    compute_penalty_rate,
    maybe_award_bonus,
    record_ledger,
    is_suspended_or_banned,
    liquidate_to_wallet,
)

moneybox_bp = Blueprint("moneybox_bp", __name__, url_prefix="/api/moneybox")
moneybox_system_bp = Blueprint("moneybox_system_bp", __name__, url_prefix="/api/system/moneybox")

_INIT = False


@moneybox_bp.before_app_request
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


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    r = _role(u)
    if r == "admin":
        return True
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


def _allowed_role(u: User | None) -> bool:
    if not u:
        return False
    return _role(u) in ("merchant", "driver", "inspector")


def _is_email_verified(u: User | None) -> bool:
    if not u:
        return False
    return bool(getattr(u, "is_verified", False))


def _status_reasons(u: User | None) -> list[str]:
    reasons: list[str] = []
    if not u:
        return reasons
    if not _is_email_verified(u):
        reasons.append("EMAIL_NOT_VERIFIED")
    try:
        if int(getattr(u, "kyc_tier", 0) or 0) < 1:
            reasons.append("KYC_REQUIRED")
    except Exception:
        reasons.append("KYC_REQUIRED")
    if not _allowed_role(u):
        reasons.append("ROLE_NOT_ELIGIBLE")
    return reasons


def _account_response(acct: MoneyBoxAccount) -> dict:
    data = acct.to_dict()
    return {"ok": True, "account": data}


def _autosave_settings_payload(acct: MoneyBoxAccount, *, role_eligible: bool) -> dict:
    percent = float(acct.autosave_percent or 0.0)
    if percent < 0:
        percent = 0.0
    return {
        "ok": True,
        "autosave_enabled": bool(acct.autosave_enabled),
        "autosave_percent": int(round(percent)),
        "min_percent": 1,
        "max_percent": 30,
        "role_eligible": bool(role_eligible),
    }


def _apply_autosave_settings(*, acct: MoneyBoxAccount, enabled, percent) -> tuple[dict, int] | None:
    if enabled is False:
        acct.autosave_enabled = False
        acct.autosave_percent = 0.0
        return None

    try:
        pct = int(round(float(percent if percent is not None else acct.autosave_percent or 0.0)))
    except Exception:
        pct = int(round(float(acct.autosave_percent or 0.0)))
    if pct < 1 or pct > 30:
        return {"ok": False, "message": "autosave_percent must be between 1 and 30"}, 400
    acct.autosave_enabled = True
    acct.autosave_percent = float(pct)
    return None


@moneybox_bp.get("/status")
def status():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _allowed_role(u):
        reasons = _status_reasons(u)
        try:
            pending = RoleChangeRequest.query.filter_by(user_id=int(u.id), status="PENDING").first()
            if pending and pending.requested_role in ("merchant", "driver", "inspector"):
                return jsonify({"status": "pending_approval", "reasons": reasons + ["ROLE_REQUEST_PENDING"]}), 200
        except Exception:
            pass
        return jsonify({"status": "not_eligible", "reasons": reasons}), 200

    acct = get_or_create_account(int(u.id))
    data = acct.to_dict()
    return jsonify({"ok": True, **data}), 200


@moneybox_bp.get("/me")
def me():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _allowed_role(u):
        return jsonify({"message": "MoneyBox is only for merchants, drivers, inspectors"}), 403

    acct = get_or_create_account(int(u.id))
    return jsonify(_account_response(acct)), 200


@moneybox_bp.post("/open")
def open_moneybox():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _allowed_role(u):
        return jsonify({"message": "MoneyBox is only for merchants, drivers, inspectors"}), 403

    payload = request.get_json(silent=True) or {}
    try:
        tier = int(payload.get("tier") or 1)
    except Exception:
        tier = 1
    if tier not in (1, 2, 3, 4):
        return jsonify({"message": "Invalid tier"}), 400
    if tier > 1 and not _is_email_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    acct = get_or_create_account(int(u.id))
    try:
        locked = MoneyBoxAccount.query.filter_by(user_id=int(u.id)).with_for_update().first()
        if locked:
            acct = locked
    except Exception:
        pass
    if acct.status in ("ACTIVE", "OPEN", "MATURED"):
        return jsonify({"message": "MoneyBox is active; withdraw or relock after closing"}), 409

    pre_key = acct.updated_at.isoformat() if acct.updated_at else "0"
    lock_days = int(TIER_CONFIG[tier]["lock_days"])
    if tier == 1:
        raw_days = payload.get("lock_days") or payload.get("duration_days")
        if raw_days is not None:
            try:
                custom = int(raw_days)
            except Exception:
                custom = lock_days
            custom = max(1, min(30, custom))
            lock_days = custom

    set_account_cycle(acct, tier=tier, lock_days=lock_days)
    open_key = f"open:{int(acct.id)}:{pre_key}"
    record_ledger(
        acct,
        "OPEN",
        0.0,
        reference=f"open:{int(acct.id)}",
        meta={"tier": tier, "lock_days": lock_days},
        idempotency_key=open_key,
    )

    try:
        db.session.add(acct)
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        # likely concurrent open; return current account state
        acct = MoneyBoxAccount.query.filter_by(user_id=int(u.id)).first()
        if acct and acct.status in ("ACTIVE", "OPEN", "MATURED"):
            return jsonify({"message": "MoneyBox is active; withdraw or relock after closing"}), 409
        return jsonify({"message": "MoneyBox open conflict"}), 409
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500

    return jsonify(_account_response(acct)), 200


@moneybox_bp.post("/relock")
def relock_moneybox():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _allowed_role(u):
        return jsonify({"message": "MoneyBox is only for merchants, drivers, inspectors"}), 403

    payload = request.get_json(silent=True) or {}
    try:
        tier = int(payload.get("tier") or 1)
    except Exception:
        tier = 1
    if tier not in (1, 2, 3, 4):
        return jsonify({"message": "Invalid tier"}), 400
    if tier > 1 and not _is_email_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    acct = get_or_create_account(int(u.id))
    try:
        if acct.status not in ("ACTIVE", "OPEN", "MATURED"):
            return open_moneybox()
    except Exception:
        pass

    acct = get_or_create_account(int(u.id))
    try:
        locked = MoneyBoxAccount.query.filter_by(user_id=int(u.id)).with_for_update().first()
        if locked:
            acct = locked
    except Exception:
        pass
    if acct.status in ("ACTIVE", "OPEN", "MATURED"):
        return jsonify({"message": "MoneyBox is active; withdraw or relock after closing"}), 409

    pre_key = acct.updated_at.isoformat() if acct.updated_at else "0"
    lock_days = int(TIER_CONFIG[tier]["lock_days"])
    if tier == 1:
        raw_days = payload.get("lock_days") or payload.get("duration_days")
        if raw_days is not None:
            try:
                custom = int(raw_days)
            except Exception:
                custom = lock_days
            custom = max(1, min(30, custom))
            lock_days = custom

    set_account_cycle(acct, tier=tier, lock_days=lock_days)
    relock_key = f"relock:{int(acct.id)}:{pre_key}"
    record_ledger(
        acct,
        "RELOCK",
        0.0,
        reference=f"relock:{int(acct.id)}",
        meta={"tier": tier, "lock_days": lock_days},
        idempotency_key=relock_key,
    )

    try:
        db.session.add(acct)
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        acct = MoneyBoxAccount.query.filter_by(user_id=int(u.id)).first()
        if acct and acct.status in ("ACTIVE", "OPEN", "MATURED"):
            return jsonify({"message": "MoneyBox is active; withdraw or relock after closing"}), 409
        return jsonify({"message": "MoneyBox relock conflict"}), 409
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500

    return jsonify(_account_response(acct)), 200


@moneybox_bp.get("/autosave/settings")
def autosave_settings_get():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    role_eligible = _allowed_role(u)
    acct = get_or_create_account(int(u.id))
    if not role_eligible:
        return jsonify(_autosave_settings_payload(acct, role_eligible=False)), 200
    return jsonify(_autosave_settings_payload(acct, role_eligible=True)), 200


@moneybox_bp.post("/autosave/settings")
def autosave_settings_post():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    if not _allowed_role(u):
        return jsonify({"ok": False, "message": "MoneyBox autosave is only for merchants, drivers, inspectors"}), 403

    payload = request.get_json(silent=True) or {}
    enabled = payload.get("autosave_enabled", payload.get("enabled"))
    percent = payload.get("autosave_percent", payload.get("percent"))

    acct = get_or_create_account(int(u.id))
    settings_error = _apply_autosave_settings(acct=acct, enabled=enabled, percent=percent)
    if settings_error is not None:
        body, status_code = settings_error
        return jsonify(body), status_code

    acct.updated_at = datetime.utcnow()

    try:
        db.session.add(acct)
        db.session.commit()
        return jsonify(_autosave_settings_payload(acct, role_eligible=True)), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"ok": False, "message": "Failed", "error": str(e)}), 500


@moneybox_bp.post("/autosave")
def autosave():
    return autosave_settings_post()


@moneybox_bp.post("/withdraw")
def withdraw():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _allowed_role(u):
        return jsonify({"message": "MoneyBox is only for merchants, drivers, inspectors"}), 403
    if not _is_email_verified(u):
        return jsonify({"error": "EMAIL_NOT_VERIFIED", "message": "Your email must be verified to perform this action"}), 403

    acct = get_or_create_account(int(u.id))

    # award bonus if matured
    try:
        maybe_award_bonus(acct)
    except Exception:
        pass

    total = float(acct.principal_balance or 0.0) + float(acct.bonus_balance or 0.0)
    if total <= 0:
        return jsonify({"message": "No funds to withdraw"}), 400

    lock_days = int(acct.lock_days or 0)
    start_at = acct.lock_start_at or datetime.utcnow()
    elapsed_days = (datetime.utcnow() - start_at).days
    penalty_rate = compute_penalty_rate(lock_days, elapsed_days)
    penalty_amount = round(float(acct.principal_balance or 0.0) * float(penalty_rate), 2)
    if penalty_amount < 0:
        penalty_amount = 0.0

    payout_amount = round(float(total) - float(penalty_amount), 2)
    if payout_amount < 0:
        payout_amount = 0.0

    # update account
    acct.principal_balance = 0.0
    acct.bonus_balance = 0.0
    acct.status = "CLOSED"
    acct.bonus_eligible = False
    acct.last_withdraw_at = datetime.utcnow()
    acct.updated_at = datetime.utcnow()

    ref = f"moneybox:{int(acct.id)}:{int(datetime.utcnow().timestamp())}"
    record_ledger(acct, "WITHDRAW", payout_amount, reference=ref, idempotency_key=f"withdraw:{int(acct.id)}:{ref}")
    if penalty_amount > 0:
        record_ledger(acct, "PENALTY", penalty_amount, reference=ref, meta={"rate": penalty_rate}, idempotency_key=f"penalty:{int(acct.id)}:{ref}")

    try:
        db.session.add(acct)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500

    try:
        from app.utils.wallets import post_txn
        post_txn(user_id=int(u.id), direction="credit", amount=float(payout_amount), kind="moneybox_withdraw", reference=ref, note="MoneyBox withdrawal")
        if float(penalty_amount) > 0:
            # Penalty is platform revenue: credit admin/system wallet (id=1).
            post_txn(user_id=1, direction="credit", amount=float(penalty_amount), kind="moneybox_penalty", reference=ref, note="MoneyBox early-withdraw penalty", idempotency_key=f"platform_penalty:{ref}")
    except Exception:
        pass

    return jsonify({
        "ok": True,
        "payout_amount": float(payout_amount),
        "penalty_rate": float(penalty_rate),
        "penalty_amount": float(penalty_amount),
        "account": acct.to_dict(),
    }), 200


@moneybox_bp.get("/ledger")
def ledger():
    u = _current_user()
    if not u:
        return jsonify({"items": []}), 200
    if not _allowed_role(u):
        return jsonify({"items": []}), 200
    rows = MoneyBoxLedger.query.filter_by(user_id=int(u.id)).order_by(MoneyBoxLedger.created_at.desc()).limit(200).all()
    items = []
    for r in rows:
        d = r.to_dict()
        d["type"] = d.pop("entry_type", "")
        items.append(d)
    return jsonify({"ok": True, "items": items}), 200


@moneybox_bp.post("/tier")
def set_tier():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _allowed_role(u):
        return jsonify({"message": "MoneyBox is only for merchants, drivers, inspectors"}), 403
    acct = get_or_create_account(int(u.id))
    try:
        if acct.status in ("ACTIVE", "OPEN", "MATURED"):
            return relock_moneybox()
    except Exception:
        pass
    return open_moneybox()


@moneybox_system_bp.post("/process-maturity")
def process_maturity():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    processed = 0
    auto_opened = 0
    bonuses = 0

    rows = MoneyBoxAccount.query.all()
    now = datetime.utcnow()

    for acct in rows:
        if acct.status in ("CLOSED",):
            continue
        processed += 1

        if acct.auto_open_at and now >= acct.auto_open_at and acct.status == "ACTIVE":
            acct.status = "OPEN"
            auto_key = f"auto_open:{int(acct.id)}:{int(acct.auto_open_at.timestamp()) if acct.auto_open_at else ''}"
            record_ledger(acct, "AUTO_OPEN", 0.0, reference=f"auto_open:{int(acct.id)}", idempotency_key=auto_key)
            auto_opened += 1

        try:
            bonus = maybe_award_bonus(acct)
            if bonus > 0:
                bonuses += 1
        except Exception:
            pass

        if acct.maturity_at and now >= acct.maturity_at and acct.status not in ("CLOSED", "MATURED"):
            acct.status = "MATURED"

        acct.updated_at = now
        db.session.add(acct)

    try:
        db.session.commit()
    except Exception:
        db.session.rollback()

    return jsonify({"ok": True, "processed": processed, "auto_opened": auto_opened, "bonuses": bonuses}), 200


@moneybox_system_bp.post("/liquidate-on-suspension")
def liquidate_on_suspension():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    user_id = payload.get("user_id")
    guilty = bool(payload.get("guilty") is True)
    target_user_id = payload.get("target_user_id")
    reference = (payload.get("reference") or "").strip() or None

    results = []

    if user_id and str(user_id).isdigit():
        acct = MoneyBoxAccount.query.filter_by(user_id=int(user_id)).first()
        if not acct:
            return jsonify({"message": "account not found"}), 404
        res = liquidate_to_wallet(acct, reason="suspension", reference=reference, guilty=guilty, target_user_id=int(target_user_id) if target_user_id else None)
        results.append(res)
    else:
        rows = MoneyBoxAccount.query.all()
        for acct in rows:
            if not is_suspended_or_banned(int(acct.user_id)):
                continue
            res = liquidate_to_wallet(acct, reason="suspension")
            results.append(res)

    return jsonify({"ok": True, "results": results}), 200
