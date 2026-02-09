from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, SupportTicket
from app.utils.jwt_utils import decode_token, get_bearer_token

support_bp = Blueprint("support_bp", __name__, url_prefix="/api/support")

_INIT_DONE = False


@support_bp.before_app_request
def _ensure_tables_once():
    global _INIT_DONE
    if _INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT_DONE = True


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    return get_bearer_token(header)


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


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


@support_bp.get("/tickets")
def list_tickets():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    if _is_admin(u) and (request.args.get("all") == "1"):
        rows = SupportTicket.query.order_by(SupportTicket.created_at.desc()).limit(200).all()
    else:
        rows = SupportTicket.query.filter_by(user_id=u.id).order_by(SupportTicket.created_at.desc()).limit(200).all()

    return jsonify({"ok": True, "items": [t.to_dict() for t in rows]}), 200


@support_bp.post("/tickets")
def create_ticket():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    subject = (payload.get("subject") or "").strip()
    message = (payload.get("message") or "").strip()

    if not subject or not message:
        return jsonify({"message": "subject and message are required"}), 400

    t = SupportTicket(user_id=u.id, subject=subject, message=message, status="open")

    try:
        db.session.add(t)
        db.session.commit()
        return jsonify({"ok": True, "ticket": t.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create ticket", "error": str(e)}), 500


@support_bp.post("/tickets/<int:ticket_id>/status")
def update_status(ticket_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    status = (payload.get("status") or "").strip().lower()
    if status not in ("open", "in_progress", "resolved", "closed"):
        return jsonify({"message": "Invalid status"}), 400

    t = SupportTicket.query.get(ticket_id)
    if not t:
        return jsonify({"message": "Not found"}), 404

    t.status = status
    t.updated_at = datetime.utcnow()

    try:
        db.session.add(t)
        db.session.commit()
        return jsonify({"ok": True, "ticket": t.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to update", "error": str(e)}), 500
