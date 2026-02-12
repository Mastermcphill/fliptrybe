from __future__ import annotations

from flask import Blueprint, jsonify, request
from sqlalchemy import or_
from sqlalchemy.orm import aliased

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
    return db.session.get(User, uid)


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
    return _role(u) in ("buyer", "seller")


def _is_merchant(user: User | None) -> bool:
    return bool(user and _role(user) == "merchant")


def _pagination() -> tuple[int, int]:
    try:
        limit = int(request.args.get("limit") or 50)
    except Exception:
        limit = 50
    try:
        offset = int(request.args.get("offset") or 0)
    except Exception:
        offset = 0
    if limit < 1:
        limit = 1
    if limit > 100:
        limit = 100
    if offset < 0:
        offset = 0
    return limit, offset


@merchant_follow_bp.post("/merchants/<int:merchant_id>/follow")
def follow_merchant(merchant_id: int):
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401

    if not _can_follow(u):
        return jsonify({"ok": False, "message": "Only buyers/sellers can follow merchants"}), 403

    target = db.session.get(User, int(merchant_id))
    if not target or not _is_merchant(target):
        return jsonify({"ok": False, "message": "Merchant not found"}), 404

    if int(u.id) == int(merchant_id):
        return jsonify({"ok": False, "message": "Cannot follow yourself"}), 409

    existing = MerchantFollow.query.filter_by(
        follower_id=int(u.id),
        merchant_id=int(merchant_id),
    ).first()
    if existing:
        return jsonify({"ok": True, "following": True, "idempotent": True}), 200

    row = MerchantFollow(follower_id=int(u.id), merchant_id=int(merchant_id))
    try:
        db.session.add(row)
        db.session.commit()
        return jsonify({"ok": True, "following": True}), 201
    except Exception:
        db.session.rollback()
        row = MerchantFollow.query.filter_by(
            follower_id=int(u.id),
            merchant_id=int(merchant_id),
        ).first()
        if row:
            return jsonify({"ok": True, "following": True, "idempotent": True}), 200
        return jsonify({"ok": False, "error": "follow_failed"}), 500


@merchant_follow_bp.delete("/merchants/<int:merchant_id>/follow")
def unfollow_merchant(merchant_id: int):
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401

    row = MerchantFollow.query.filter_by(
        follower_id=int(u.id),
        merchant_id=int(merchant_id),
    ).first()
    if not row:
        return jsonify({"ok": True, "following": False, "idempotent": True}), 200

    try:
        db.session.delete(row)
        db.session.commit()
        return jsonify({"ok": True, "following": False}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"ok": False, "error": "unfollow_failed"}), 500


@merchant_follow_bp.get("/merchants/<int:merchant_id>/follow-status")
def follow_status(merchant_id: int):
    u = _current_user()
    if not u:
        return jsonify({"ok": True, "following": False}), 200
    row = MerchantFollow.query.filter_by(
        follower_id=int(u.id),
        merchant_id=int(merchant_id),
    ).first()
    return jsonify({"ok": True, "following": bool(row)}), 200


@merchant_follow_bp.get("/merchants/<int:merchant_id>/followers-count")
def followers_count(merchant_id: int):
    cnt = MerchantFollow.query.filter_by(merchant_id=int(merchant_id)).count()
    return jsonify({"ok": True, "merchant_id": int(merchant_id), "followers": int(cnt)}), 200


@merchant_follow_bp.get("/me/following-merchants")
def my_following_merchants():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401

    limit, offset = _pagination()
    base_query = MerchantFollow.query.filter_by(follower_id=int(u.id))
    total = base_query.count()
    rows = (
        base_query.order_by(MerchantFollow.created_at.desc(), MerchantFollow.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    merchant_ids = [int(r.merchant_id) for r in rows]
    merchants = User.query.filter(User.id.in_(merchant_ids)).all() if merchant_ids else []
    by_id = {int(m.id): m for m in merchants}
    out = []
    for rel in rows:
        m = by_id.get(int(rel.merchant_id))
        if not m:
            continue
        out.append(
            {
                "merchant_id": int(m.id),
                "name": getattr(m, "name", "") or "",
                "email": getattr(m, "email", "") or "",
                "followed_at": rel.created_at.isoformat() if rel.created_at else None,
            }
        )
    return jsonify({"ok": True, "items": out, "total": total, "limit": limit, "offset": offset}), 200


@merchant_follow_bp.get("/merchant/followers")
def merchant_followers():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    if _role(u) != "merchant" and not _is_admin(u):
        return jsonify({"ok": False, "message": "Forbidden"}), 403

    if _is_admin(u):
        try:
            merchant_id = int(request.args.get("merchant_id"))
        except Exception:
            return jsonify({"ok": False, "message": "merchant_id required for admin"}), 400
    else:
        merchant_id = int(u.id)
    limit, offset = _pagination()
    base_query = MerchantFollow.query.filter_by(merchant_id=merchant_id)
    total = base_query.count()
    rows = (
        base_query.order_by(MerchantFollow.created_at.desc(), MerchantFollow.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    follower_ids = [int(r.follower_id) for r in rows]
    users = User.query.filter(User.id.in_(follower_ids)).all() if follower_ids else []
    by_id = {int(x.id): x for x in users}
    items = []
    for rel in rows:
        follower = by_id.get(int(rel.follower_id))
        if not follower:
            continue
        items.append(
            {
                "follower_id": int(follower.id),
                "name": getattr(follower, "name", "") or "",
                "email": getattr(follower, "email", "") or "",
                "role": _role(follower),
                "followed_at": rel.created_at.isoformat() if rel.created_at else None,
            }
        )
    return jsonify({"ok": True, "items": items, "total": total, "limit": limit, "offset": offset}), 200


@merchant_follow_bp.get("/merchant/followers/count")
def merchant_followers_count():
    u = _current_user()
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized"}), 401
    if _role(u) != "merchant" and not _is_admin(u):
        return jsonify({"ok": False, "message": "Forbidden"}), 403
    if _is_admin(u):
        try:
            merchant_id = int(request.args.get("merchant_id"))
        except Exception:
            return jsonify({"ok": False, "message": "merchant_id required for admin"}), 400
    else:
        merchant_id = int(u.id)
    cnt = MerchantFollow.query.filter_by(merchant_id=int(merchant_id)).count()
    return jsonify({"ok": True, "merchant_id": int(merchant_id), "followers": int(cnt)}), 200


@merchant_follow_bp.get("/admin/follows/search")
def admin_follow_search():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"ok": False, "message": "Forbidden"}), 403

    limit, offset = _pagination()
    q_text = (request.args.get("q") or "").strip()

    follower_alias = aliased(User)
    merchant_alias = aliased(User)

    query = (
        db.session.query(MerchantFollow, follower_alias, merchant_alias)
        .join(follower_alias, follower_alias.id == MerchantFollow.follower_id)
        .join(merchant_alias, merchant_alias.id == MerchantFollow.merchant_id)
    )

    if q_text:
        like = f"%{q_text.lower()}%"
        filters = [
            db.func.lower(follower_alias.email).like(like),
            db.func.lower(follower_alias.name).like(like),
            db.func.lower(merchant_alias.email).like(like),
            db.func.lower(merchant_alias.name).like(like),
        ]
        try:
            q_int = int(q_text)
            filters.append(MerchantFollow.follower_id == q_int)
            filters.append(MerchantFollow.merchant_id == q_int)
        except Exception:
            pass
        query = query.filter(or_(*filters))

    total = query.count()
    rows = (
        query.order_by(MerchantFollow.created_at.desc(), MerchantFollow.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    items = []
    for rel, follower, merchant in rows:
        items.append(
            {
                "id": int(rel.id),
                "follower_id": int(rel.follower_id),
                "follower_email": getattr(follower, "email", "") or "",
                "follower_name": getattr(follower, "name", "") or "",
                "merchant_id": int(rel.merchant_id),
                "merchant_email": getattr(merchant, "email", "") or "",
                "merchant_name": getattr(merchant, "name", "") or "",
                "followed_at": rel.created_at.isoformat() if rel.created_at else None,
            }
        )
    return jsonify({"ok": True, "items": items, "total": total, "limit": limit, "offset": offset}), 200
