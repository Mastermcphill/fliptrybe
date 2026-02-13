from __future__ import annotations

from datetime import datetime, timedelta
import math
import json

from app.extensions import db
from sqlalchemy.exc import IntegrityError
from app.models import MoneyBoxAccount, MoneyBoxLedger, User, MerchantProfile, DriverProfile, InspectorProfile
from app.models.merchant import DisabledUser
from app.utils.events import log_event

TIER_CONFIG = {
    1: {"lock_days": 30, "bonus_rate": 0.0},
    2: {"lock_days": 120, "bonus_rate": 0.03},
    3: {"lock_days": 210, "bonus_rate": 0.08},
    4: {"lock_days": 330, "bonus_rate": 0.15},
}

ELIGIBLE_COMMISSION_KINDS = {
    "top_tier_incentive",
    "delivery_fee",
    "inspection_fee",
    "commission_credit",
}


def _now() -> datetime:
    return datetime.utcnow()


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _is_allowed_role(u: User | None) -> bool:
    if not u:
        return False
    return _role(u) in ("merchant", "driver", "inspector")


def compute_penalty_rate(lock_days: int, elapsed_days: int) -> float:
    try:
        L = int(lock_days or 0)
    except Exception:
        L = 0
    if L <= 0:
        return 0.0

    try:
        elapsed = int(elapsed_days or 0)
    except Exception:
        elapsed = 0
    if elapsed < 0:
        elapsed = 0

    one_third = int(math.ceil(L * 0.3333))
    two_third = int(math.ceil(L * 0.6666))
    open_day = max(L - 1, 0)

    if elapsed <= one_third:
        return 0.07
    if elapsed <= two_third:
        return 0.05
    if elapsed <= open_day:
        return 0.02
    return 0.0


def get_or_create_account(user_id: int) -> MoneyBoxAccount:
    acct = MoneyBoxAccount.query.filter_by(user_id=int(user_id)).first()
    if acct:
        return acct
    acct = MoneyBoxAccount(
        user_id=int(user_id),
        tier=1,
        status="CLOSED",
        principal_balance=0.0,
        bonus_balance=0.0,
        lock_days=TIER_CONFIG[1]["lock_days"],
        autosave_enabled=False,
        autosave_percent=0.0,
        bonus_eligible=True,
        updated_at=_now(),
    )
    try:
        db.session.add(acct)
        db.session.commit()
        return acct
    except IntegrityError:
        db.session.rollback()
        acct = MoneyBoxAccount.query.filter_by(user_id=int(user_id)).first()
        if acct:
            return acct
        raise


def record_ledger(
    acct: MoneyBoxAccount,
    entry_type: str,
    amount: float,
    reference: str | None = None,
    meta: dict | None = None,
    idempotency_key: str | None = None,
) -> MoneyBoxLedger:
    if idempotency_key:
        existing = MoneyBoxLedger.query.filter_by(idempotency_key=str(idempotency_key)[:160]).first()
        if existing:
            return existing
    total = float(acct.principal_balance or 0.0) + float(acct.bonus_balance or 0.0)
    row = MoneyBoxLedger(
        account_id=int(acct.id),
        user_id=int(acct.user_id),
        entry_type=entry_type,
        amount=float(amount or 0.0),
        balance_after=float(total),
        reference=(reference or "")[:80] if reference else None,
        meta=json.dumps(meta) if meta else None,
        idempotency_key=str(idempotency_key)[:160] if idempotency_key else None,
        created_at=_now(),
    )
    db.session.add(row)
    return row


def set_account_cycle(acct: MoneyBoxAccount, *, tier: int, lock_days: int) -> None:
    now = _now()
    acct.tier = int(tier)
    acct.status = "ACTIVE"
    acct.lock_days = int(lock_days)
    acct.lock_start_at = now
    acct.auto_open_at = now + timedelta(days=max(int(lock_days) - 1, 0))
    acct.maturity_at = now + timedelta(days=max(int(lock_days), 0))
    acct.bonus_eligible = True
    acct.bonus_awarded_at = None
    acct.updated_at = now


def maybe_award_bonus(acct: MoneyBoxAccount) -> float:
    if acct.bonus_awarded_at is not None:
        return 0.0
    if not acct.maturity_at:
        return 0.0
    if _now() < acct.maturity_at:
        return 0.0
    if not bool(acct.bonus_eligible):
        return 0.0

    cfg = TIER_CONFIG.get(int(acct.tier or 1), None)
    if not cfg:
        return 0.0
    rate = float(cfg.get("bonus_rate", 0.0) or 0.0)
    if rate <= 0.0:
        return 0.0

    bonus = round(float(acct.principal_balance or 0.0) * rate, 2)
    if bonus <= 0.0:
        return 0.0

    acct.bonus_balance = float(acct.bonus_balance or 0.0) + bonus
    acct.bonus_awarded_at = _now()
    acct.status = "MATURED"
    acct.updated_at = _now()
    record_ledger(acct, "BONUS", bonus, reference=f"bonus:{int(acct.id)}", idempotency_key=f"bonus:{int(acct.id)}")
    return bonus


def autosave_from_commission(*, user_id: int, amount: float, kind: str, reference: str) -> float:
    try:
        amt = float(amount or 0.0)
    except Exception:
        return 0.0
    if amt <= 0:
        return 0.0

    if (kind or "") not in ELIGIBLE_COMMISSION_KINDS:
        return 0.0

    u = User.query.get(int(user_id))
    if not _is_allowed_role(u):
        return 0.0

    acct = get_or_create_account(int(user_id))
    if not bool(acct.autosave_enabled) or float(acct.autosave_percent or 0.0) <= 0.0:
        return 0.0

    if acct.status not in ("ACTIVE", "OPEN", "MATURED"):
        return 0.0

    # Idempotency: if ledger already has autosave for this reference, skip
    idem_key = f"autosave:{int(user_id)}:{reference}"
    existing = MoneyBoxLedger.query.filter_by(idempotency_key=idem_key[:160]).first()
    if not existing:
        existing = MoneyBoxLedger.query.filter_by(
            user_id=int(user_id),
            entry_type="AUTOSAVE",
            reference=reference,
        ).first()
    if existing:
        return 0.0

    percent = max(1.0, min(30.0, float(acct.autosave_percent or 0.0)))
    sweep = round(amt * (percent / 100.0), 2)
    if sweep <= 0:
        return 0.0
    if sweep > amt:
        sweep = amt

    acct.principal_balance = float(acct.principal_balance or 0.0) + float(sweep)
    acct.updated_at = _now()
    record_ledger(acct, "AUTOSAVE", sweep, reference=reference, meta={"kind": kind, "percent": percent}, idempotency_key=idem_key)

    try:
        db.session.add(acct)
        db.session.commit()
    except Exception:
        db.session.rollback()
        return 0.0

    log_event(
        "moneybox_autosave",
        actor_user_id=int(user_id),
        subject_type="moneybox_account",
        subject_id=int(acct.id),
        idempotency_key=f"moneybox_autosave:{int(user_id)}:{reference}",
        metadata={
            "amount": float(sweep),
            "percent": float(percent),
            "kind": kind,
            "reference": reference,
        },
    )

    return float(sweep)


def is_suspended_or_banned(user_id: int) -> bool:
    u = User.query.get(int(user_id))
    if not u:
        return False

    if DisabledUser.query.filter_by(user_id=int(user_id), disabled=True).first():
        return True

    role = _role(u)
    if role == "merchant":
        mp = MerchantProfile.query.filter_by(user_id=int(user_id)).first()
        if mp and bool(getattr(mp, "is_suspended", False)):
            return True
    if role == "driver":
        dp = DriverProfile.query.filter_by(user_id=int(user_id)).first()
        if dp and not bool(getattr(dp, "is_active", True)):
            return True
    if role == "inspector":
        ip = InspectorProfile.query.filter_by(user_id=int(user_id)).first()
        if ip and not bool(getattr(ip, "is_active", True)):
            return True

    return False


def liquidate_to_wallet(acct: MoneyBoxAccount, *, reason: str, reference: str | None = None, guilty: bool = False, target_user_id: int | None = None) -> dict:
    if not acct:
        return {"ok": False, "message": "account not found"}

    ref = reference or f"liquidate:{int(acct.id)}"

    # Idempotency: if already liquidated with reference
    existing = MoneyBoxLedger.query.filter_by(idempotency_key=f"liquidate:{int(acct.id)}:{ref}"[:160]).first()
    if not existing:
        existing = MoneyBoxLedger.query.filter_by(user_id=int(acct.user_id), entry_type="LIQUIDATE", reference=ref).first()
    if existing:
        return {"ok": True, "message": "already liquidated"}

    total = float(acct.principal_balance or 0.0) + float(acct.bonus_balance or 0.0)
    if total <= 0:
        acct.status = "CLOSED"
        acct.updated_at = _now()
        db.session.add(acct)
        db.session.commit()
        return {"ok": True, "message": "no funds"}

    principal = float(acct.principal_balance or 0.0)
    bonus = float(acct.bonus_balance or 0.0)

    penalty_amount = 0.0
    credit_target = None
    if guilty and target_user_id:
        penalty_amount = round(principal * 1.10, 2)
        if penalty_amount > total:
            penalty_amount = total
        credit_target = int(target_user_id)

    owner_credit = round(total - penalty_amount, 2)
    if owner_credit < 0:
        owner_credit = 0.0

    # Update account balances
    acct.principal_balance = 0.0
    acct.bonus_balance = 0.0
    acct.status = "CLOSED"
    acct.updated_at = _now()
    acct.last_withdraw_at = _now()

    record_ledger(acct, "LIQUIDATE", total, reference=ref, meta={"reason": reason}, idempotency_key=f"liquidate:{int(acct.id)}:{ref}")

    if penalty_amount > 0 and credit_target:
        record_ledger(acct, "DISPUTE_PENALTY", penalty_amount, reference=ref, meta={"target_user_id": credit_target}, idempotency_key=f"dispute_penalty:{int(acct.id)}:{ref}")

    try:
        db.session.add(acct)
        db.session.commit()
    except Exception:
        db.session.rollback()
        return {"ok": False, "message": "failed to update account"}

    # credit wallets (post_txn to avoid negative)
    try:
        from app.utils.wallets import post_txn
        if penalty_amount > 0 and credit_target:
            post_txn(user_id=int(credit_target), direction="credit", amount=float(penalty_amount), kind="moneybox_penalty", reference=ref, note="MoneyBox dispute penalty")
        if owner_credit > 0:
            post_txn(user_id=int(acct.user_id), direction="credit", amount=float(owner_credit), kind="moneybox_liquidation", reference=ref, note="MoneyBox liquidation")
    except Exception:
        pass

    if penalty_amount > 0 and credit_target:
        log_event(
            "moneybox_penalty_applied",
            actor_user_id=int(acct.user_id),
            subject_type="moneybox_account",
            subject_id=int(acct.id),
            idempotency_key=f"moneybox_penalty:{int(acct.id)}:{ref}",
            metadata={"penalty_amount": float(penalty_amount), "target_user_id": int(credit_target)},
        )

    return {"ok": True, "penalty": penalty_amount, "owner_credit": owner_credit}
