from __future__ import annotations

from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request, current_app
from sqlalchemy import or_

from app.extensions import db
from app.models import User, SupportMessage
from app.utils.jwt_utils import decode_token, get_bearer_token
from app.utils.autopilot import get_settings
from app.utils.rate_limit import check_limit
from app.services.risk_engine_service import record_event

support_bp = Blueprint("support_chat_bp", __name__, url_prefix="/api/support")
support_admin_bp = Blueprint("support_admin_bp", __name__, url_prefix="/api/admin/support")


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
    try:
        return User.query.get(uid)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        try:
            return User.query.get(uid)
        except Exception:
            try:
                db.session.rollback()
            except Exception:
                pass
            return None


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    return _role(u) == "admin"


def _rate_limit_response(action: str, *, user: User | None, limit: int, window_seconds: int):
    try:
        settings = get_settings()
        enabled = bool(getattr(settings, "rate_limit_enabled", True))
    except Exception:
        enabled = True
    if not enabled:
        return None
    ip = (request.headers.get("X-Forwarded-For") or request.remote_addr or "unknown").split(",")[0].strip()
    uid = int(getattr(user, "id", 0) or 0) if user else 0
    key = f"{action}:ip:{ip}:u:{uid}"
    ok, retry_after = check_limit(key, limit=limit, window_seconds=window_seconds)
    if ok:
        return None
    try:
        record_event(
            "support_message_spam",
            user=user,
            context={"rate_limited": True, "reason_code": "SUPPORT_RATE_LIMIT", "retry_after": retry_after},
            request_id=request.headers.get("X-Request-Id"),
        )
    except Exception:
        db.session.rollback()
    return jsonify({"ok": False, "error": "RATE_LIMITED", "message": "Too many messages. Please wait and retry.", "retry_after": retry_after}), 429


def _spam_body_response(user: User, body: str):
    if _is_admin(user):
        return None
    now = datetime.utcnow()
    rows = (
        SupportMessage.query
        .filter_by(user_id=int(user.id), sender_role="user")
        .filter(SupportMessage.created_at >= now - timedelta(minutes=1))
        .order_by(SupportMessage.created_at.desc())
        .limit(10)
        .all()
    )
    duplicates = [row for row in rows if (row.body or "").strip().lower() == body.strip().lower()]
    if len(duplicates) >= 2:
        try:
            record_event(
                "support_message_spam",
                user=user,
                context={"repeated_body": True, "reason_code": "REPEATED_BODY"},
                request_id=request.headers.get("X-Request-Id"),
            )
        except Exception:
            db.session.rollback()
        return jsonify({"ok": False, "error": "SPAM_THROTTLED", "message": "Repeated message blocked. Please wait before sending again."}), 429
    return None


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
    rl = _rate_limit_response("support_message_send", user=u, limit=20, window_seconds=60)
    if rl is not None:
        return rl

    payload = request.get_json(silent=True) or {}
    body = (payload.get("body") or "").strip()
    target_raw = payload.get("user_id") or payload.get("recipient_id") or payload.get("target_user_id")
    if not body:
        return jsonify({"message": "body required"}), 400
    spam = _spam_body_response(u, body)
    if spam is not None:
        return spam

    # Non-admins can only chat with admin.
    if target_raw is not None and not _is_admin(u):
        try:
            target_id = int(target_raw)
        except Exception:
            return jsonify({"message": "Invalid user_id"}), 400
        try:
            target = User.query.get(int(target_id))
        except Exception:
            try:
                db.session.rollback()
            except Exception:
                pass
            target = None
        if not target:
            return jsonify({"message": "Not found"}), 404
        if not _is_admin(target):
            return jsonify({
                "error": "CHAT_NOT_ALLOWED",
                "message": "Direct messaging between users is not allowed",
            }), 403

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
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        try:
            current_app.logger.info("support_admin_forbidden role=%s", _role(u))
        except Exception:
            pass
        return jsonify({"message": "Forbidden"}), 403

    try:
        db.session.rollback()
        q = db.session.query(
            SupportMessage.user_id,
            db.func.max(SupportMessage.created_at).label("last_at"),
            db.func.count(SupportMessage.id).label("count"),
            User.name,
            User.email,
        ).outerjoin(User, User.id == SupportMessage.user_id).group_by(
            SupportMessage.user_id,
            User.name,
            User.email,
        ).order_by(db.text("last_at desc")).limit(200)
        rows = q.all()
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("support_threads_error")
        except Exception:
            pass
        return jsonify({"ok": True, "threads": []}), 200
    out = []
    for user_id, last_at, count, name, email in rows:
        out.append({
            "user_id": int(user_id),
            "name": name or "",
            "email": email or "",
            "last_at": last_at.isoformat() if last_at else None,
            "count": int(count or 0),
        })
    return jsonify({"ok": True, "threads": out}), 200


@support_admin_bp.get("/messages/<int:user_id>")
def admin_get_thread(user_id: int):
    u = _current_user()
    if not _is_admin(u):
        try:
            current_app.logger.info("support_admin_forbidden role=%s", _role(u))
        except Exception:
            pass
        return jsonify({"message": "Forbidden"}), 403

    try:
        db.session.rollback()
        rows = SupportMessage.query.filter_by(user_id=int(user_id)).order_by(SupportMessage.created_at.asc()).limit(1000).all()
        return jsonify({"ok": True, "items": [r.to_dict() for r in rows]}), 200
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("support_admin_thread_error")
        except Exception:
            pass
        return jsonify({"ok": True, "items": []}), 200


@support_admin_bp.post("/messages/<int:user_id>")
def admin_send(user_id: int):
    u = _current_user()
    if not _is_admin(u):
        try:
            current_app.logger.info("support_admin_forbidden role=%s", _role(u))
        except Exception:
            pass
        return jsonify({"message": "Forbidden"}), 403

    try:
        db.session.rollback()
        target = User.query.get(int(user_id))
        if not target:
            return jsonify({"message": "Not found"}), 404
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("support_admin_target_error")
        except Exception:
            pass
        return jsonify({"ok": True, "message": "Not found"}), 404

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
