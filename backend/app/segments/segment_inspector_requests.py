import os
import secrets
import hashlib
import hmac
import smtplib
from email.message import EmailMessage
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request, current_app
from sqlalchemy.exc import SQLAlchemyError

from app.extensions import db
from app.models import InspectorRequest, User, PasswordResetToken, AuditLog
from app.utils.jwt_utils import decode_token, get_bearer_token

inspector_req_bp = Blueprint("inspector_req_bp", __name__, url_prefix="/api/public")
inspector_req_admin_bp = Blueprint("inspector_req_admin_bp", __name__, url_prefix="/api/admin")


def _hash_token(value: str) -> str:
    secret = (current_app.config.get("SECRET_KEY") or os.getenv("SECRET_KEY") or "fliptrybe").encode("utf-8")
    return hmac.new(secret, value.encode("utf-8"), hashlib.sha256).hexdigest()


def _base_url() -> str:
    base = (os.getenv("PUBLIC_BASE_URL") or os.getenv("RENDER_EXTERNAL_URL") or os.getenv("BASE_URL") or "").strip()
    if base:
        return base.rstrip("/")
    try:
        return request.host_url.rstrip("/")
    except Exception:
        return ""


def _send_reset_email(email: str, token: str) -> None:
    if not email:
        return
    link = f"{_base_url()}/reset-password?token={token}"
    smtp_host = (os.getenv("SMTP_HOST") or "").strip()
    smtp_port = int((os.getenv("SMTP_PORT") or "587").strip() or 587)
    smtp_user = (os.getenv("SMTP_USER") or "").strip()
    smtp_pass = (os.getenv("SMTP_PASS") or "").strip()
    smtp_from = (os.getenv("SMTP_FROM") or smtp_user or "no-reply@fliptrybe.com").strip()
    smtp_reply_to = (os.getenv("SMTP_REPLY_TO") or "").strip()

    if smtp_host:
        msg = EmailMessage()
        msg["Subject"] = "Set your FlipTrybe password"
        msg["From"] = smtp_from
        msg["To"] = email
        if smtp_reply_to:
            msg["Reply-To"] = smtp_reply_to
        msg.set_content(f"Set your password by clicking:\n{link}\n\nIf you did not request this, ignore this email.")
        try:
            with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as server:
                server.ehlo()
                try:
                    server.starttls()
                except Exception:
                    pass
                if smtp_user and smtp_pass:
                    server.login(smtp_user, smtp_pass)
                server.send_message(msg)
            current_app.logger.info("inspector_reset_sent email=%s", email)
            return
        except Exception:
            current_app.logger.exception("inspector_reset_send_failed")

    current_app.logger.info("INSPECTOR_RESET_LINK: %s", link)


def _current_user() -> User | None:
    token = get_bearer_token(request.headers.get("Authorization", ""))
    payload = decode_token(token) if token else None
    sub = payload.get("sub") if isinstance(payload, dict) else None
    try:
        uid = int(sub) if sub is not None else None
    except Exception:
        uid = None
    if not uid:
        return None
    try:
        return User.query.get(int(uid))
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return None


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    role = (getattr(u, "role", None) or "").strip().lower()
    if role == "admin":
        return True
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


@inspector_req_bp.post("/inspector-requests")
def create_inspector_request():
    payload = request.get_json(silent=True) or {}
    token_user = _current_user()

    name = (payload.get("name") or getattr(token_user, "name", "") or "").strip()
    email = (payload.get("email") or getattr(token_user, "email", "") or "").strip().lower()
    phone = (payload.get("phone") or getattr(token_user, "phone", "") or "").strip()
    notes = (payload.get("notes") or "").strip()

    if not name or not email or not phone:
        return jsonify({"message": "name, email, phone required"}), 400

    existing = InspectorRequest.query.filter_by(email=email, status="pending").first()
    if existing:
        return jsonify({"ok": True, "message": "Request already submitted", "request": existing.to_dict()}), 200

    req = InspectorRequest(
        name=name,
        email=email,
        phone=phone,
        notes=notes,
        status="pending",
        created_at=datetime.utcnow(),
    )

    try:
        db.session.add(req)
        db.session.commit()
        return jsonify({"ok": True, "message": "Request submitted", "request": req.to_dict()}), 201
    except SQLAlchemyError:
        db.session.rollback()
        return jsonify({"message": "Failed to submit request"}), 500


@inspector_req_admin_bp.get("/inspector-requests")
def admin_list_inspector_requests():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    status = (request.args.get("status") or "pending").strip().lower()
    try:
        q = InspectorRequest.query
        if status:
            q = q.filter_by(status=status)
        rows = q.order_by(InspectorRequest.created_at.desc()).limit(500).all()
        return jsonify({"ok": True, "items": [r.to_dict() for r in rows]}), 200
    except Exception:
        db.session.rollback()
        current_app.logger.exception("inspector_requests_list_failed")
        return jsonify({"ok": True, "items": []}), 200


@inspector_req_admin_bp.post("/inspector-requests/<int:req_id>/approve")
def admin_approve_inspector(req_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    req = InspectorRequest.query.get(req_id)
    if not req:
        return jsonify({"message": "Not found"}), 404
    if req.status == "approved":
        try:
            existing_user = User.query.filter_by(email=(req.email or "").strip().lower()).first()
        except Exception:
            existing_user = None
        return jsonify({
            "ok": True,
            "request": {"id": int(req.id), "status": req.status},
            "user": {"id": int(existing_user.id), "email": existing_user.email, "role": getattr(existing_user, "role", "buyer")} if existing_user else None,
            "created": False,
        }), 200

    email = (req.email or "").strip().lower()
    phone = (req.phone or "").strip()
    name = (req.name or "").strip() or "Inspector"

    try:
        user = User.query.filter_by(email=email).first()
    except Exception:
        user = None

    try:
        created = False
        if not user:
            # Create user with random password; send reset link
            temp_password = secrets.token_urlsafe(12)
            user = User(name=name, email=email, phone=phone)
            user.set_password(temp_password)
            user.role = "inspector"
            user.is_verified = False
            db.session.add(user)
            db.session.flush()
            created = True

            token = secrets.token_urlsafe(32)
            rec = PasswordResetToken(
                user_id=int(user.id),
                token_hash=_hash_token(token),
                created_at=datetime.utcnow(),
                expires_at=datetime.utcnow() + timedelta(minutes=60),
                used_at=None,
            )
            db.session.add(rec)
            _send_reset_email(email, token)
        else:
            user.role = "inspector"

        req.status = "approved"
        req.decided_at = datetime.utcnow()
        req.decided_by = int(u.id)
        db.session.add(req)
        db.session.add(user)
        db.session.commit()

        try:
            db.session.add(AuditLog(
                actor_user_id=int(u.id),
                action="inspector_request_approve",
                target_user_id=int(user.id),
                details_json=f"req_id={int(req.id)}",
                created_at=datetime.utcnow(),
            ))
            db.session.commit()
        except Exception:
            db.session.rollback()

        return jsonify({
            "ok": True,
            "request": {"id": int(req.id), "status": req.status},
            "user": {"id": int(user.id), "email": user.email, "role": getattr(user, "role", "buyer")},
            "created": created,
        }), 200
    except SQLAlchemyError as e:
        db.session.rollback()
        msg = "Failed to approve"
        try:
            text = str(e).lower()
            if "users_email_key" in text or "email" in text:
                msg = "Email already in use"
            elif "users_phone_key" in text or "phone" in text:
                msg = "Phone already in use"
        except Exception:
            pass
        return jsonify({"message": msg}), 500


@inspector_req_admin_bp.post("/inspector-requests/<int:req_id>/reject")
def admin_reject_inspector(req_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    req = InspectorRequest.query.get(req_id)
    if not req:
        return jsonify({"message": "Not found"}), 404

    req.status = "rejected"
    req.decided_at = datetime.utcnow()
    req.decided_by = int(u.id)

    try:
        db.session.add(req)
        db.session.commit()
        return jsonify({"ok": True, "request": req.to_dict()}), 200
    except SQLAlchemyError:
        db.session.rollback()
        return jsonify({"message": "Failed to reject"}), 500
