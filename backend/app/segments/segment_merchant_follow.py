from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, MerchantFollow
from app.utils.jwt_utils import decode_token, get_bearer_token

merchant_follow_bp = Blueprint("merchant_follow_bp", __name__, url_prefix="/api")

_INIT = False


@merchant_follow_bp.before_app_request
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
    return get_bearer_token(header)


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
    if _role(u) == "admin":
        return True
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


def _can_follow(u: User) -> bool:
    # Only buyers/sellers can follow merchants. Merchants cannot follow anyone.
    r = _role(u)
    return r in ("buyer", "seller")


def _is_merchant(user: User | None) -> bool:
    if not user:
        return False
    return _role(user) == "merchant"


@merchant_follow_bp.post("/merchants/<int:merchant_id>/follow")
def follow_merchant(merchant_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    if not _can_follow(u):
        return jsonify({"message": "Only buyers/sellers can follow merchants"}), 403

    target = User.query.get(merchant_id)
    if not target or not _is_merchant(target):
        return jsonify({"message": "Merchant not found"}), 404

    # Prevent weird self-follow
    if int(u.id) == int(merchant_id):
        return jsonify({"message": "Cannot follow yourself"}), 409

    existing = MerchantFollow.query.filter_by(follower_id=int(u.id), merchant_id=int(merchant_id)).first()
    if existing:
        return jsonify({"ok": True, "following": True}), 200

    row = MerchantFollow(follower_id=int(u.id), merchant_id=int(merchant_id))
    try:
        db.session.add(row)
        db.session.commit()
        return jsonify({"ok": True, "following": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@merchant_follow_bp.delete("/merchants/<int:merchant_id>/follow")
def unfollow_merchant(merchant_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    row = MerchantFollow.query.filter_by(follower_id=int(u.id), merchant_id=int(merchant_id)).first()
    if not row:
        return jsonify({"ok": True, "following": False}), 200

    try:
        db.session.delete(row)
        db.session.commit()
        return jsonify({"ok": True, "following": False}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@merchant_follow_bp.get("/merchants/<int:merchant_id>/follow-status")
def follow_status(merchant_id: int):
    u = _current_user()
    if not u:
        return jsonify({"following": False}), 200
    row = MerchantFollow.query.filter_by(follower_id=int(u.id), merchant_id=int(merchant_id)).first()
    return jsonify({"following": bool(row)}), 200


@merchant_follow_bp.get("/merchants/<int:merchant_id>/followers-count")
def followers_count(merchant_id: int):
    cnt = MerchantFollow.query.filter_by(merchant_id=int(merchant_id)).count()
    return jsonify({"merchant_id": int(merchant_id), "followers": int(cnt)}), 200


@merchant_follow_bp.get("/me/following-merchants")
def my_following_merchants():
    u = _current_user()
    if not u:
        return jsonify([]), 200
    rows = MerchantFollow.query.filter_by(follower_id=int(u.id)).order_by(MerchantFollow.id.desc()).limit(500).all()
    merchant_ids = [int(r.merchant_id) for r in rows]
    if not merchant_ids:
        return jsonify([]), 200
    merchants = User.query.filter(User.id.in_(merchant_ids)).all()
    # Keep order as stored
    by_id = {int(m.id): m for m in merchants}
    out = []
    for mid in merchant_ids:
        m = by_id.get(mid)
        if not m:
            continue
        out.append({
            "merchant_id": int(m.id),
            "name": getattr(m, "name", "") or "",
            "email": getattr(m, "email", "") or "",
        })
    return jsonify(out), 200
