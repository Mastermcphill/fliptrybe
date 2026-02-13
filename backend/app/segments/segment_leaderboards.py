from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import MerchantProfile, User

leaderboards_bp = Blueprint("leaderboards_bp", __name__, url_prefix="/api/leaderboards")

_INIT_DONE = False


@leaderboards_bp.before_app_request
def _ensure_tables_once():
    global _INIT_DONE
    if _INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT_DONE = True


def _sort(items):
    items.sort(key=lambda x: float(x.score()), reverse=True)
    return items


@leaderboards_bp.get("")
def ranked():
    raw_limit = (request.args.get("limit") or "").strip()
    try:
        limit = int(raw_limit) if raw_limit else 20
    except Exception:
        limit = 20
    if limit < 1:
        limit = 20
    if limit > 100:
        limit = 100

    state = (request.args.get("state") or "").strip()
    try:
        q = MerchantProfile.query.filter_by(is_suspended=False)
        if state and state.lower() != "all nigeria":
            q = q.filter(MerchantProfile.state.ilike(state))
        items = q.all()
        _sort(items)
    except Exception as e:
        db.session.rollback()
        return jsonify({"ok": False, "message": "Failed to load leaderboards", "error": str(e)}), 500

    out = []
    rank = 1
    for m in items[:limit]:
        row = m.to_dict()
        user = User.query.get(int(m.user_id)) if m.user_id is not None else None
        row["profile_image_url"] = (getattr(user, "profile_image_url", "") or "") if user else ""
        row["rank"] = rank
        out.append(row)
        rank += 1
    return jsonify({"ok": True, "items": out}), 200


@leaderboards_bp.get("/featured")
def featured():
    items = MerchantProfile.query.filter_by(is_featured=True, is_suspended=False).all()
    _sort(items)
    return jsonify({"ok": True, "items": [x.to_dict() for x in items[:30]]}), 200


@leaderboards_bp.get("/states")
def top_by_state():
    """Return { state: [top merchants] } for Nigeria."
    limit per state is configurable."
    """
    raw_limit = (request.args.get("limit") or "").strip()
    try:
        limit = int(raw_limit) if raw_limit else 10
    except Exception:
        limit = 10
    if limit < 1:
        limit = 10
    if limit > 30:
        limit = 30

    # Pull all merchants, group in python (simple, sqlite friendly)
    rows = MerchantProfile.query.filter_by(is_suspended=False).all()
    by_state = {}
    for m in rows:
        st = (m.state or "").strip() or "Unknown"
        by_state.setdefault(st, []).append(m)
    out = {}
    for st, items in by_state.items():
        _sort(items)
        rows = []
        for x in items[:limit]:
            row = x.to_dict()
            user = User.query.get(int(x.user_id)) if x.user_id is not None else None
            row["profile_image_url"] = (getattr(user, "profile_image_url", "") or "") if user else ""
            rows.append(row)
        out[st] = rows
    return jsonify({"ok": True, "items": out}), 200


@leaderboards_bp.get("/cities")
def top_by_city():
    """Return { 'State|City': [top merchants] }."
    """
    raw_limit = (request.args.get("limit") or "").strip()
    try:
        limit = int(raw_limit) if raw_limit else 10
    except Exception:
        limit = 10
    if limit < 1:
        limit = 10
    if limit > 30:
        limit = 30

    rows = MerchantProfile.query.filter_by(is_suspended=False).all()
    by_city = {}
    for m in rows:
        st = (m.state or "").strip() or "Unknown"
        ct = (m.city or "").strip() or "Unknown"
        key = f"{st}|{ct}"
        by_city.setdefault(key, []).append(m)
    out = {}
    for key, items in by_city.items():
        _sort(items)
        rows = []
        for x in items[:limit]:
            row = x.to_dict()
            user = User.query.get(int(x.user_id)) if x.user_id is not None else None
            row["profile_image_url"] = (getattr(user, "profile_image_url", "") or "") if user else ""
            rows.append(row)
        out[key] = rows
    return jsonify({"ok": True, "items": out}), 200
