from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, CommissionRule, CommissionPolicy, CommissionPolicyRule
from app.services.commission_policy_service import (
    activate_policy,
    add_policy_rule,
    archive_policy,
    compute_fee_minor,
    create_policy,
    resolve_commission_policy,
)
from app.utils.jwt_utils import decode_token

commission_bp = Blueprint("commission_bp", __name__, url_prefix="/api/admin/commission")

_INIT = False


@commission_bp.before_app_request
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
    try:
        return "admin" in (u.email or "").lower()
    except Exception:
        return False


def _parse_dt(value):
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text)
    except Exception:
        return None


@commission_bp.get("")
def list_rules():
    u = _current_user()
    if not _is_admin(u):
        return jsonify([]), 200

    kind = (request.args.get("kind") or "").strip()
    state = (request.args.get("state") or "").strip()
    category = (request.args.get("category") or "").strip()

    q = CommissionRule.query.filter_by(is_active=True)
    if kind:
        q = q.filter(CommissionRule.kind.ilike(kind))
    if state:
        q = q.filter(CommissionRule.state.ilike(state))
    if category:
        q = q.filter(CommissionRule.category.ilike(category))

    rows = q.order_by(CommissionRule.kind.asc(), CommissionRule.state.asc(), CommissionRule.category.asc()).all()
    return jsonify([r.to_dict() for r in rows]), 200


@commission_bp.post("")
def upsert_rule():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}

    kind = (payload.get("kind") or "").strip()
    if not kind:
        return jsonify({"message": "kind is required"}), 400

    state = (payload.get("state") or "").strip()
    category = (payload.get("category") or "").strip()

    raw_rate = payload.get("rate")
    try:
        rate = float(raw_rate)
    except Exception:
        rate = 0.0

    if rate < 0:
        rate = 0.0

    # Find existing rule (kind+state+category)
    q = CommissionRule.query.filter_by(kind=kind, is_active=True)
    q = q.filter(CommissionRule.state == (state or None), CommissionRule.category == (category or None))
    r = q.first()
    if not r:
        r = CommissionRule(kind=kind, state=state or None, category=category or None)

    r.rate = rate
    r.updated_at = datetime.utcnow()
    r.is_active = True

    try:
        db.session.add(r)
        db.session.commit()
        return jsonify({"ok": True, "rule": r.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@commission_bp.post("/<int:rule_id>/disable")
def disable_rule(rule_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    r = CommissionRule.query.get(rule_id)
    if not r:
        return jsonify({"message": "Not found"}), 404

    r.is_active = False
    r.updated_at = datetime.utcnow()

    try:
        db.session.add(r)
        db.session.commit()
        return jsonify({"ok": True, "rule": r.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@commission_bp.get("/policies")
def list_policies():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    status = (request.args.get("status") or "").strip().lower()
    query = CommissionPolicy.query
    if status:
        query = query.filter_by(status=status)
    rows = query.order_by(CommissionPolicy.created_at.desc(), CommissionPolicy.id.desc()).limit(200).all()
    policy_ids = [int(row.id) for row in rows]
    rules_by_policy = {}
    if policy_ids:
        rules = CommissionPolicyRule.query.filter(CommissionPolicyRule.policy_id.in_(policy_ids)).all()
        for row in rules:
            rules_by_policy.setdefault(int(row.policy_id), []).append(row.to_dict())
    return jsonify(
        {
            "ok": True,
            "items": [
                {
                    **row.to_dict(),
                    "rules": rules_by_policy.get(int(row.id), []),
                }
                for row in rows
            ],
        }
    ), 200


@commission_bp.post("/policies")
def create_policy_draft():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    payload = request.get_json(silent=True) or {}
    name = (payload.get("name") or "").strip()
    notes = (payload.get("notes") or "").strip()
    if not name:
        return jsonify({"message": "name is required"}), 400
    try:
        row = create_policy(name=name, created_by_admin_id=int(u.id), notes=notes)
        return jsonify({"ok": True, "policy": row.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@commission_bp.post("/policies/<int:policy_id>/rules")
def create_policy_rule(policy_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    policy = db.session.get(CommissionPolicy, int(policy_id))
    if not policy:
        return jsonify({"message": "Policy not found"}), 404
    payload = request.get_json(silent=True) or {}
    try:
        row = add_policy_rule(
            policy_id=int(policy.id),
            applies_to=(payload.get("applies_to") or "all"),
            seller_type=(payload.get("seller_type") or "all"),
            city=(payload.get("city") or ""),
            base_rate_bps=int(payload.get("base_rate_bps") or 0),
            min_fee_minor=int(payload["min_fee_minor"]) if payload.get("min_fee_minor") is not None else None,
            max_fee_minor=int(payload["max_fee_minor"]) if payload.get("max_fee_minor") is not None else None,
            promo_discount_bps=int(payload["promo_discount_bps"]) if payload.get("promo_discount_bps") is not None else None,
            starts_at=_parse_dt(payload.get("starts_at")),
            ends_at=_parse_dt(payload.get("ends_at")),
        )
        return jsonify({"ok": True, "rule": row.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@commission_bp.post("/policies/<int:policy_id>/activate")
def activate_policy_endpoint(policy_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    try:
        row = activate_policy(int(policy_id))
        if not row:
            return jsonify({"message": "Policy not found"}), 404
        return jsonify({"ok": True, "policy": row.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@commission_bp.post("/policies/<int:policy_id>/archive")
def archive_policy_endpoint(policy_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    try:
        row = archive_policy(int(policy_id))
        if not row:
            return jsonify({"message": "Policy not found"}), 404
        return jsonify({"ok": True, "policy": row.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@commission_bp.get("/preview")
def preview_policy():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    applies_to = (request.args.get("applies_to") or "declutter").strip().lower()
    seller_type = (request.args.get("seller_type") or "all").strip().lower()
    city = (request.args.get("city") or "").strip()
    try:
        amount_minor = int(request.args.get("amount_minor") or 0)
    except Exception:
        amount_minor = 0
    resolved = resolve_commission_policy(
        applies_to=applies_to,
        seller_type=seller_type,
        city=city,
    )
    fee = compute_fee_minor(
        amount_minor=int(max(0, amount_minor)),
        applies_to=applies_to,
        seller_type=seller_type,
        city=city,
    )
    return jsonify(
        {
            "ok": True,
            "applies_to": applies_to,
            "seller_type": seller_type,
            "city": city,
            "amount_minor": int(max(0, amount_minor)),
            "commission_fee_minor": int(fee["fee_minor"]),
            "policy": resolved.to_dict(),
        }
    ), 200
