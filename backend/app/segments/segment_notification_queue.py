from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, NotificationQueue
from app.utils.jwt_utils import decode_token

notifq_bp = Blueprint("notifq_bp", __name__, url_prefix="/api/admin/notify-queue")

_INIT = False


@notifq_bp.before_app_request
def _ensure_tables_once():
    global _INIT
    if _INIT:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT = True


def _bearer_token():
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip()


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
        uid = int(sub)
    except Exception:
        return None
    return User.query.get(uid)


def _is_admin(u):
    if not u:
        return False
    try:
        if int(u.id or 0) == 1:
            return True
    except Exception:
        pass
    return (u.role or "").strip().lower() == "admin"


@notifq_bp.get("")
def list_queue():
    u = _current_user()
    if not _is_admin(u):
        return jsonify([]), 200
    channel = (request.args.get("channel") or "").strip()
    status = (request.args.get("status") or "").strip()
    q = NotificationQueue.query
    if channel:
        q = q.filter(NotificationQueue.channel.ilike(channel))
    if status:
        q = q.filter(NotificationQueue.status.ilike(status))
    rows = q.order_by(NotificationQueue.created_at.desc()).limit(300).all()
    return jsonify([x.to_dict() for x in rows]), 200


@notifq_bp.post("/<int:msg_id>/mark-sent")
def mark_sent(msg_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    row = NotificationQueue.query.get(msg_id)
    if not row:
        return jsonify({"message": "Not found"}), 404
    row.status = "sent"
    row.sent_at = datetime.utcnow()
    db.session.add(row)
    db.session.commit()
    return jsonify({"ok": True, "row": row.to_dict()}), 200


@notifq_bp.post("/<int:msg_id>/requeue")
def requeue(msg_id: int):
    """Reset a dead/failed message back into the queue."""
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    row = NotificationQueue.query.get(msg_id)
    if not row:
        return jsonify({"message": "Not found"}), 404

    row.status = "queued"
    row.attempt_count = 0
    row.next_attempt_at = datetime.utcnow()
    row.last_error = None
    row.dead_lettered_at = None

    db.session.add(row)
    db.session.commit()
    return jsonify({"ok": True, "row": row.to_dict()}), 200


@notifq_bp.post("/<int:msg_id>/retry-now")
def retry_now(msg_id: int):
    """Bump a message to run immediately (without resetting attempts)."""
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403
    row = NotificationQueue.query.get(msg_id)
    if not row:
        return jsonify({"message": "Not found"}), 404
    if (row.status or "").lower() == "sent":
        return jsonify({"message": "Already sent"}), 409

    row.status = "queued"
    row.next_attempt_at = datetime.utcnow()
    db.session.add(row)
    db.session.commit()
    return jsonify({"ok": True, "row": row.to_dict()}), 200


@notifq_bp.post("/requeue-dead")
def requeue_dead():
    """Bulk requeue dead-lettered messages (optionally filter by channel)."""
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    channel = (request.args.get("channel") or "").strip()
    q = NotificationQueue.query.filter(NotificationQueue.dead_lettered_at.isnot(None))
    if channel:
        q = q.filter(NotificationQueue.channel.ilike(channel))

    rows = q.order_by(NotificationQueue.created_at.desc()).limit(300).all()
    count = 0
    now = datetime.utcnow()
    for row in rows:
        row.status = "queued"
        row.attempt_count = 0
        row.next_attempt_at = now
        row.last_error = None
        row.dead_lettered_at = None
        db.session.add(row)
        count += 1
    db.session.commit()
    return jsonify({"ok": True, "requeued": int(count)}), 200

