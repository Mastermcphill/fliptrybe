from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, Notification
from app.utils.jwt_utils import decode_token
from app.utils.notify import queue_in_app, queue_sms, queue_whatsapp, mark_sent

notifications_bp = Blueprint("notifications_bp", __name__, url_prefix="/api")

_NOTIF_INIT_DONE = False


@notifications_bp.before_app_request
def _ensure_tables_once():
    global _NOTIF_INIT_DONE
    if _NOTIF_INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _NOTIF_INIT_DONE = True


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user():
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
        user_id = int(sub)
    except Exception:
        return None
    return User.query.get(user_id)


@notifications_bp.get("/notifications")
def list_notifications():
    user = _current_user()
    if not user:
        return jsonify({"message": "Unauthorized"}), 401

    rows = Notification.query.filter_by(user_id=user.id).order_by(Notification.created_at.desc()).limit(80).all()
    return jsonify({"ok": True, "items": [x.to_dict() for x in rows]}), 200


@notifications_bp.post("/notifications/<int:notification_id>/read")
def mark_notification_read(notification_id: int):
    user = _current_user()
    if not user:
        return jsonify({"message": "Unauthorized"}), 401

    row = Notification.query.filter_by(id=int(notification_id), user_id=int(user.id)).first()
    if not row:
        return jsonify({"message": "Not found"}), 404

    try:
        stamped = row.mark_read()
        db.session.add(row)
        db.session.commit()
        return jsonify(
            {
                "ok": True,
                "id": int(row.id),
                "is_read": True,
                "read_at": stamped.isoformat(),
            }
        ), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@notifications_bp.post("/notifications/test")
def test_notification():
    """Investor/demo: creates an in-app + sms + whatsapp notification (queued then marked sent)."""
    user = _current_user()
    if not user:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    title = (payload.get("title") or "FlipTrybe").strip()
    message = (payload.get("message") or "Test notification").strip()

    n1 = queue_in_app(user.id, title, message, meta={"demo": True})
    n2 = queue_sms(user.id, title, message, provider="stub", meta={"demo": True})
    n3 = queue_whatsapp(user.id, title, message, provider="stub", meta={"demo": True})

    # For demo: mark them as sent immediately (no external provider)
    mark_sent(n1, provider_ref="local:sent")
    mark_sent(n2, provider_ref="stub:sms")
    mark_sent(n3, provider_ref="stub:whatsapp")

    try:
        db.session.commit()
        return jsonify({"ok": True, "items": [n1.to_dict(), n2.to_dict(), n3.to_dict()]}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500
