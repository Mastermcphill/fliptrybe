from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import PricingBenchmark, User
from app.services.pricing import suggest_price
from app.utils.jwt_utils import decode_token, get_bearer_token


pricing_bp = Blueprint("pricing_bp", __name__, url_prefix="/api")


def _to_int(value, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def _current_user() -> User | None:
    token = get_bearer_token(request.headers.get("Authorization", ""))
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    try:
        uid = int(payload.get("sub") or 0)
    except Exception:
        return None
    try:
        return db.session.get(User, uid)
    except Exception:
        return None


def _is_admin(user: User | None) -> bool:
    if not user:
        return False
    role = (getattr(user, "role", None) or "").strip().lower()
    if role == "admin":
        return True
    try:
        return int(getattr(user, "id", 0) or 0) == 1
    except Exception:
        return False


@pricing_bp.post("/pricing/suggest")
def pricing_suggest():
    payload = request.get_json(silent=True) or {}
    category = (payload.get("category") or "").strip().lower()
    if category not in ("declutter", "shortlet"):
        return jsonify({"ok": False, "message": "category must be declutter|shortlet"}), 400
    city = (payload.get("city") or "").strip() or "Lagos"
    item_type = (payload.get("item_type") or "").strip()
    condition = (payload.get("condition") or "").strip()
    current_price_minor = _to_int(payload.get("current_price_minor"), 0)
    duration_nights = _to_int(payload.get("duration_nights"), 1)

    result = suggest_price(
        category=category,
        city=city,
        item_type=item_type,
        condition=condition,
        current_price_minor=current_price_minor,
        duration_nights=duration_nights,
    )
    return jsonify({"ok": True, **result}), 200


@pricing_bp.get("/admin/pricing/benchmarks")
def admin_pricing_benchmarks():
    user = _current_user()
    if not _is_admin(user):
        return jsonify({"message": "Forbidden"}), 403
    category = (request.args.get("category") or "").strip().lower()
    city = (request.args.get("city") or "").strip()
    try:
        limit = int(request.args.get("limit") or 100)
    except Exception:
        limit = 100
    limit = max(1, min(limit, 300))

    query = PricingBenchmark.query
    if category:
        query = query.filter(PricingBenchmark.category.ilike(category))
    if city:
        query = query.filter(PricingBenchmark.city.ilike(city))
    rows = query.order_by(PricingBenchmark.updated_at.desc(), PricingBenchmark.id.desc()).limit(limit).all()
    return jsonify({"ok": True, "items": [row.to_dict() for row in rows], "limit": int(limit)}), 200
