from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request, current_app
from sqlalchemy import or_

from app.extensions import db
from app.models import User
from app.utils.jwt_utils import decode_token

support_bp = Blueprint("support_chat_bp", __name__, url_prefix="/api/support")
support_admin_bp = Blueprint("support_admin_bp", __name__, url_prefix="/api/admin/support")

_INIT = False


@support_bp.before_app_request
def _ensure_tables_once():
    global _INIT
    if _INIT:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT = True


class SupportMessage(db.Model):
    __tablename__ = "support_messages"
    __table_args__ = {"extend_existing": True}

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, nullable=False, index=True)      # the non-admin user
    sender_role = db.Column(db.String(16), nullable=False)           # user/admin
    sender_id = db.Column(db.Integer, nullable=False)                # who sent

    body = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            "id": int(self.id),
            "user_id": int(self.user_id),
            "sender_role": self.sender_role,
            "sender_id": int(self.sender_id),
            "body": self.body,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


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


@support_bp.get("/messages")
def my_messages():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    # Users can only see their own thread with admin
    rows = SupportMessage.query.filter_by(user_id=int(u.id)).order_by(SupportMessage.created_at.asc()).limit(500).all()
    return jsonify({"ok": True, "items": [r.to_dict() for r in rows]}), 200


@support_bp.post("/messages")
def send_to_admin():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    body = (payload.get("body") or "").strip()
    target_raw = payload.get("user_id") or payload.get("recipient_id") or payload.get("target_user_id")
    if not body:
        return jsonify({"message": "body required"}), 400

    # Non-admins can only chat with admin.
    if target_raw is not None and not _is_admin(u):
        return jsonify({"error": "chat_not_allowed", "message": "You can only chat with Admin."}), 403

    if target_raw is not None and _is_admin(u):
        try:
            target_id = int(target_raw)
        except Exception:
            return jsonify({"message": "Invalid user_id"}), 400
        target = User.query.get(int(target_id))
        if not target:
            return jsonify({"message": "Not found"}), 404

        msg = SupportMessage(
            user_id=int(target_id),
            sender_role="admin",
            sender_id=int(u.id),
            body=body[:2000],
            created_at=datetime.utcnow(),
        )

        try:
            db.session.add(msg)
            db.session.commit()
            return jsonify({"ok": True, "message": msg.to_dict()}), 201
        except Exception as e:
            db.session.rollback()
            return jsonify({"message": "Failed", "error": str(e)}), 500

    # Users can only message admin (support). Never other users.
    msg = SupportMessage(
        user_id=int(u.id),
        sender_role="user",
        sender_id=int(u.id),
        body=body[:2000],
        created_at=datetime.utcnow(),
    )

    try:
        db.session.add(msg)
        db.session.commit()
        return jsonify({"ok": True, "message": msg.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@support_admin_bp.get("/threads")
def admin_threads():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    # Basic list: users with recent activity
    try:
        db.session.rollback()
        q = db.session.query(
            SupportMessage.user_id,
            db.func.max(SupportMessage.created_at).label("last_at"),
            db.func.count(SupportMessage.id).label("count"),
        ).group_by(SupportMessage.user_id).order_by(db.text("last_at desc")).limit(200)
        rows = q.all()
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("support_threads_error")
        except Exception:
            pass
        return jsonify({"ok": True, "threads": []}), 200
    out = []
    for user_id, last_at, count in rows:
        user = User.query.get(int(user_id))
        out.append({
            "user_id": int(user_id),
            "name": getattr(user, "name", "") if user else "",
            "email": getattr(user, "email", "") if user else "",
            "last_at": last_at.isoformat() if last_at else None,
            "count": int(count or 0),
        })
    return jsonify({"ok": True, "threads": out}), 200


@support_admin_bp.get("/messages/<int:user_id>")
def admin_get_thread(user_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    rows = SupportMessage.query.filter_by(user_id=int(user_id)).order_by(SupportMessage.created_at.asc()).limit(1000).all()
    return jsonify({"ok": True, "items": [r.to_dict() for r in rows]}), 200


@support_admin_bp.post("/messages/<int:user_id>")
def admin_send(user_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    target = User.query.get(int(user_id))
    if not target:
        return jsonify({"message": "Not found"}), 404

    payload = request.get_json(silent=True) or {}
    body = (payload.get("body") or "").strip()
    if not body:
        return jsonify({"message": "body required"}), 400

    msg = SupportMessage(
        user_id=int(user_id),
        sender_role="admin",
        sender_id=int(u.id),
        body=body[:2000],
        created_at=datetime.utcnow(),
    )

    try:
        db.session.add(msg)
        db.session.commit()
        return jsonify({"ok": True, "message": msg.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500
