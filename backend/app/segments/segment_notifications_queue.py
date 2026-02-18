from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, Notification, UserSettings
from app.utils.jwt_utils import decode_token

notify_bp = Blueprint("notify_bp", __name__, url_prefix="/api/notify")

_INIT = False


@notify_bp.before_app_request
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
        return int(u.id or 0) == 1
    except Exception:
        return False


@notify_bp.post("/enqueue")
def enqueue():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    user_id = payload.get("user_id")
    title = (payload.get("title") or "Notification").strip()
    body = (payload.get("body") or "").strip()
    channel = (payload.get("channel") or "in_app").strip().lower()

    try:
        uid = int(user_id)
    except Exception:
        uid = int(u.id)

    if uid != int(u.id) and not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    if not body:
        return jsonify({"message": "body required"}), 400

    n = Notification(user_id=uid, channel=channel, title=title, body=body, status="queued")

    try:
        db.session.add(n)
        db.session.commit()
        return jsonify({"ok": True, "notification": n.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@notify_bp.get("/inbox")
def inbox():
    u = _current_user()
    if not u:
        return jsonify([]), 200
    rows = Notification.query.filter_by(user_id=u.id).order_by(Notification.created_at.desc()).limit(200).all()
    return jsonify([x.to_dict() for x in rows]), 200
