import os
import json
import secrets
import hashlib
import hmac
import smtplib
from email.message import EmailMessage
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify, current_app
from sqlalchemy.exc import IntegrityError, SQLAlchemyError, InternalError

from app.extensions import db
from app.models import User, RoleChangeRequest, EmailVerificationToken, PasswordResetToken, RefreshToken, AuditLog
from app.utils.jwt_utils import create_token, decode_token, get_bearer_token
from app.utils.account_flags import record_account_flag, find_duplicate_phone_users, flag_duplicate_phone
from app.utils.notify import queue_email
from app.utils.autopilot import get_settings
from app.utils.rate_limit import check_limit
from app.utils.events import log_event
from app.utils.observability import get_request_id
from app.services.risk_engine_service import record_event
from app.services.referral_service import (
    apply_referral_code as apply_referral_code_service,
    ensure_user_referral_code,
)


def _conflict_message(email_user: User | None, phone_user: User | None) -> str | None:
    if email_user and phone_user and getattr(email_user, "id", None) != getattr(phone_user, "id", None):
        return "Email or phone already in use"
    if phone_user:
        return "Phone already in use"
    if email_user:
        return "Email already in use"
    return None


def _conflict_message_from_integrity(err: Exception) -> str:
    msg = str(err)
    if "users_phone_key" in msg or "phone" in msg:
        if "users_email_key" in msg or "email" in msg:
            return "Email or phone already in use"
        return "Phone already in use"
    if "users_email_key" in msg or "email" in msg:
        return "Email already in use"
    return "Email or phone already in use"

auth_bp = Blueprint("auth_bp", __name__, url_prefix="/api/auth")


def _hash_token(value: str) -> str:
    secret = (current_app.config.get("SECRET_KEY") or os.getenv("SECRET_KEY") or "fliptrybe").encode("utf-8")
    return hmac.new(secret, value.encode("utf-8"), hashlib.sha256).hexdigest()


def _access_token_ttl_seconds() -> int:
    raw = (os.getenv("ACCESS_TOKEN_TTL_SECONDS") or "").strip()
    if raw:
        try:
            parsed = int(raw)
            if parsed > 0:
                return parsed
        except Exception:
            pass
    return 60 * 60 * 24 * 7


def _refresh_token_ttl_days() -> int:
    raw = (os.getenv("REFRESH_TOKEN_TTL_DAYS") or "").strip()
    if raw:
        try:
            parsed = int(raw)
            if parsed > 0:
                return parsed
        except Exception:
            pass
    return 45


def _iso_utc(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat() + "Z"


def _issue_access_token(user_id: int) -> tuple[str, datetime]:
    ttl_seconds = _access_token_ttl_seconds()
    expires_at = datetime.utcnow() + timedelta(seconds=ttl_seconds)
    token = create_token(int(user_id), ttl_seconds=ttl_seconds)
    return token, expires_at


def _issue_refresh_token_record(*, user_id: int, device_id: str | None = None) -> tuple[RefreshToken, str]:
    now = datetime.utcnow()
    refresh_token = secrets.token_urlsafe(48)
    rec = RefreshToken(
        user_id=int(user_id),
        token_hash=_hash_token(refresh_token),
        created_at=now,
        expires_at=now + timedelta(days=_refresh_token_ttl_days()),
        revoked_at=None,
        device_id=(device_id or "").strip() or None,
    )
    db.session.add(rec)
    return rec, refresh_token


def _revoke_refresh_token_record(rec: RefreshToken | None, *, when: datetime | None = None) -> None:
    if not rec:
        return
    if getattr(rec, "revoked_at", None):
        return
    rec.revoked_at = when or datetime.utcnow()
    db.session.add(rec)


def _revoke_all_refresh_tokens_for_user(user_id: int, *, when: datetime | None = None) -> int:
    ts = when or datetime.utcnow()
    try:
        q = RefreshToken.query.filter(
            RefreshToken.user_id == int(user_id),
            RefreshToken.revoked_at.is_(None),
        )
        count = q.update({"revoked_at": ts}, synchronize_session=False)
        return int(count or 0)
    except Exception:
        return 0


def _session_payload(user: User, *, access_token: str, access_expires_at: datetime, refresh_token: str) -> dict:
    payload = {
        "user": _user_payload_with_role_status(user),
        "token": access_token,
        "refresh_token": refresh_token,
        "expires_at": _iso_utc(access_expires_at),
    }
    return payload


def _verification_base_url() -> str:
    base = (
        os.getenv("PUBLIC_BASE_URL")
        or os.getenv("RENDER_EXTERNAL_URL")
        or os.getenv("BASE_URL")
        or ""
    ).strip()
    if base:
        return base.rstrip("/")
    try:
        return request.host_url.rstrip("/")
    except Exception:
        return ""


def _integration_mode() -> str:
    env_mode = (os.getenv("INTEGRATIONS_MODE") or "").strip().lower()
    if env_mode in ("disabled", "sandbox", "live"):
        return env_mode
    try:
        settings = get_settings()
        db_mode = (getattr(settings, "integrations_mode", "") or "").strip().lower()
        if db_mode in ("disabled", "sandbox", "live"):
            return db_mode
    except Exception:
        pass
    return "disabled"


def _send_verification_email(user: User, token: str) -> dict:
    email = (getattr(user, "email", "") or "").strip().lower()
    if not email:
        return {"ok": False, "error": "EMAIL_REQUIRED", "message": "User email is missing", "mode": _integration_mode()}
    link = f"{_verification_base_url()}/api/auth/verify-email?token={token}"
    mode = _integration_mode()
    delivery = "smtp" if mode == "live" else ("mock" if mode == "sandbox" else "disabled")
    smtp_host = (os.getenv("SMTP_HOST") or "").strip()
    smtp_port = int((os.getenv("SMTP_PORT") or "587").strip() or 587)
    smtp_user = (os.getenv("SMTP_USER") or "").strip()
    smtp_pass = (os.getenv("SMTP_PASS") or "").strip()
    smtp_from = (os.getenv("SMTP_FROM") or smtp_user or "no-reply@fliptrybe.com").strip()
    smtp_reply_to = (os.getenv("SMTP_REPLY_TO") or "").strip()

    if mode == "live":
        missing = []
        if not smtp_host:
            missing.append("SMTP_HOST")
        if not ((os.getenv("SMTP_FROM") or "").strip() or smtp_user):
            missing.append("SMTP_FROM")
        if missing:
            message = f"missing {', '.join(missing)}"
            current_app.logger.warning("email_verify_misconfigured %s", message)
            return {
                "ok": False,
                "error": "INTEGRATION_MISCONFIGURED",
                "message": message,
                "mode": mode,
                "delivery": delivery,
                "link": link,
            }

        msg = EmailMessage()
        msg["Subject"] = "Verify your FlipTrybe email"
        msg["From"] = smtp_from
        msg["To"] = email
        if smtp_reply_to:
            msg["Reply-To"] = smtp_reply_to
        msg.set_content(f"Verify your email by clicking:\n{link}\n\nIf you did not request this, ignore this email.")
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
            current_app.logger.info("email_verify_sent email=%s", email)
            return {
                "ok": True,
                "mode": mode,
                "delivery": delivery,
                "message": "Verification email sent",
            }
        except Exception:
            current_app.logger.exception("email_verify_send_failed")
            return {
                "ok": False,
                "error": "EMAIL_SEND_FAILED",
                "message": "Failed to send verification email",
                "mode": mode,
                "delivery": delivery,
                "link": link,
            }

    # Non-live fallback: log link for dev/sandbox/disabled environments.
    current_app.logger.info("EMAIL_VERIFY_LINK: %s", link)
    try:
        queue_email(
            user_id=int(user.id),
            title="Verify your FlipTrybe email",
            message=f"Verification link: {link}",
            provider="stub",
            meta={"purpose": "verify_email"},
        )
        db.session.commit()
    except Exception:
        db.session.rollback()
    return {
        "ok": True,
        "mode": mode,
        "delivery": delivery,
        "message": "Verification link generated",
        "link": link,
    }


def _issue_verification_token(user: User, ttl_minutes: int = 30) -> str | None:
    if not user:
        return None
    now = datetime.utcnow()
    token = secrets.token_urlsafe(32)
    try:
        # invalidate older unused tokens
        EmailVerificationToken.query.filter_by(user_id=int(user.id), used_at=None).update({"used_at": now})
    except Exception:
        pass
    rec = EmailVerificationToken(
        user_id=int(user.id),
        token_hash=_hash_token(token),
        created_at=now,
        expires_at=now + timedelta(minutes=ttl_minutes),
        used_at=None,
    )
    db.session.add(rec)
    db.session.commit()
    return token

def _get_request_payload(label: str) -> dict:
    data_json = request.get_json(silent=True)
    data_form = request.form.to_dict() if request.form else {}
    data = data_json if isinstance(data_json, dict) and data_json else data_form
    raw_len = 0
    if not data:
        raw_text = request.get_data(cache=True, as_text=True) or ""
        raw_len = len(raw_text)
        try:
            data = json.loads(raw_text) if raw_text else {}
        except Exception:
            data = {}
    try:
        json_keys = list(data_json.keys()) if isinstance(data_json, dict) else []
        form_keys = list(data_form.keys()) if isinstance(data_form, dict) else []
        current_app.logger.info(
            "%s_payload_keys content_type=%s json_keys=%s form_keys=%s raw_len=%s",
            label,
            request.content_type,
            json_keys,
            form_keys,
            raw_len,
        )
    except Exception:
        pass
    return data if isinstance(data, dict) else {}


def _rate_limit_enabled() -> bool:
    try:
        settings = get_settings()
        return bool(getattr(settings, "rate_limit_enabled", True))
    except Exception:
        return True


def _rate_limit_response(action: str, *, limit: int, window_seconds: int, user_id: int | None = None):
    if not _rate_limit_enabled():
        return None
    ip = (request.headers.get("X-Forwarded-For") or request.remote_addr or "unknown").split(",")[0].strip()
    key = f"{action}:ip:{ip}"
    if user_id is not None:
        key = f"{key}:u:{int(user_id)}"
    ok, retry_after = check_limit(key, limit=limit, window_seconds=window_seconds)
    if ok:
        return None
    try:
        record_event(
            action,
            user=None,
            context={"rate_limited": True, "reason_code": "RATE_LIMIT_EXCEEDED", "retry_after": retry_after},
            request_id=request.headers.get("X-Request-Id"),
        )
    except Exception:
        db.session.rollback()
    return jsonify({"ok": False, "error": "RATE_LIMITED", "message": "Too many requests. Please retry later.", "retry_after": retry_after}), 429

def _create_user(*, name: str, email: str, phone: str | None, password: str, role: str = "buyer") -> tuple[User | None, tuple[dict, int] | None]:
    """Create user, return (user, error_response)."""
    role = (role or "buyer").strip().lower()
    if role == "admin":
        return None, ({"message": "Admin signup is not allowed"}, 403)

    if not email or not password:
        return None, ({"message": "Email and password are required"}, 400)

    try:
        db.session.rollback()
    except Exception:
        pass

    email = email.strip().lower()
    phone = (phone or "").strip() or None

    try:
        existing_email = User.query.filter_by(email=email).first()
    except Exception:
        existing_email = None
    try:
        existing_phone = User.query.filter_by(phone=phone).first() if phone else None
    except Exception:
        existing_phone = None
    conflict_msg = _conflict_message(existing_email, existing_phone)
    if conflict_msg:
        try:
            current_app.logger.info("register_conflict route=/api/auth/register type=%s", conflict_msg)
        except Exception:
            pass
        return None, ({"message": conflict_msg}, 409)

    u = User(name=(name or "").strip(), email=email)
    try:
        if phone:
            setattr(u, "phone", (phone or "").strip())
    except Exception:
        pass
    try:
        u.is_verified = False
    except Exception:
        pass

    u.set_password(password)

    try:
        db.session.add(u)
        db.session.commit()
    except IntegrityError as e:
        db.session.rollback()
        try:
            current_app.logger.exception("create_user_integrity_error")
        except Exception:
            pass
        try:
            existing = User.query.filter_by(email=email).first()
            if existing:
                record_account_flag(int(existing.id), "DUP_EMAIL", signal=email, details={"email": email})
        except Exception:
            pass
        return None, ({"message": _conflict_message_from_integrity(e)}, 409)
    except SQLAlchemyError as e:
        db.session.rollback()
        try:
            current_app.logger.exception("create_user_db_error")
        except Exception:
            pass
        return None, ({"message": "Failed to create user"}, 500)

    try:
        ensure_user_referral_code(u)
    except Exception:
        db.session.rollback()

    try:
        vtoken = _issue_verification_token(u, ttl_minutes=30)
        if vtoken:
            _send_verification_email(u, vtoken)
    except Exception:
        pass
    return u, None


def _create_role_request(*, user: User, requested_role: str, meta: dict | None = None) -> tuple[RoleChangeRequest | None, tuple[dict, int] | None]:
    requested_role = (requested_role or "").strip().lower()
    if requested_role not in ("merchant", "driver", "inspector"):
        return None, ({"message": "Invalid requested_role"}, 400)

    pending = RoleChangeRequest.query.filter_by(user_id=int(user.id), status="PENDING").first()
    if pending:
        return pending, None

    req = RoleChangeRequest(
        user_id=int(user.id),
        current_role=(getattr(user, "role", None) or "buyer"),
        requested_role=requested_role,
        reason="signup",
        status="PENDING",
        created_at=datetime.utcnow(),
        meta_json=json.dumps(meta or {})[:2000],
    )
    try:
        db.session.add(req)
        db.session.commit()
        log_event(
            "role_request_submitted",
            actor_user_id=int(user.id),
            subject_type="role_request",
            subject_id=int(req.id),
            request_id=get_request_id(),
            idempotency_key=f"role_request_submitted:{int(req.id)}",
            metadata={"requested_role": req.requested_role or "", "current_role": req.current_role or ""},
        )
        return req, None
    except SQLAlchemyError:
        db.session.rollback()
        try:
            current_app.logger.exception("role_request_db_error")
        except Exception:
            pass
        return None, ({"message": "Failed to create role request"}, 500)


def _latest_role_request(user_id: int) -> RoleChangeRequest | None:
    try:
        return (
            RoleChangeRequest.query.filter_by(user_id=int(user_id))
            .order_by(RoleChangeRequest.created_at.desc())
            .first()
        )
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return None


def _user_payload_with_role_status(user: User) -> dict:
    payload = user.to_dict()
    current_role = (str(payload.get("role") or "buyer")).strip().lower()
    if not current_role:
        current_role = "buyer"
    payload["role"] = current_role
    payload["role_status"] = "approved"
    payload["requested_role"] = current_role
    payload["role_request_status"] = "none"

    req = _latest_role_request(int(user.id))
    if not req:
        return payload

    status = (getattr(req, "status", "") or "").strip().lower()
    requested_role = (getattr(req, "requested_role", "") or "").strip().lower()
    if requested_role:
        payload["requested_role"] = requested_role

    if status == "pending" and requested_role and requested_role != current_role:
        payload["role_status"] = "pending"
    elif status == "rejected" and requested_role and requested_role != current_role:
        payload["role_status"] = "rejected"
    else:
        payload["role_status"] = "approved"

    payload["role_request_status"] = status or "none"
    return payload


def _maybe_apply_referral_from_payload(user: User | None, payload: dict | None) -> dict | None:
    if not user or not isinstance(payload, dict):
        return None
    code = (
        payload.get("referral_code")
        or payload.get("ref_code")
        or payload.get("invite_code")
        or payload.get("referred_by")
        or ""
    )
    code = str(code or "").strip()
    if not code:
        return None
    try:
        return apply_referral_code_service(user=user, code=code)
    except Exception:
        db.session.rollback()
        return {"ok": False, "error": "REFERRAL_APPLY_FAILED", "message": "Failed to apply referral code"}


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    return get_bearer_token(header)


@auth_bp.post("/register")
def register():
    rl = _rate_limit_response("register", limit=25, window_seconds=300)
    if rl is not None:
        return rl
    # Backwards-compatible: treat as buyer/seller signup
    data_json = request.get_json(silent=True)
    data_form = request.form.to_dict() if request.form else {}
    raw_text = ""
    raw_len = 0
    if not data_json and not data_form:
        raw_text = request.get_data(cache=True, as_text=True) or ""
        raw_len = len(raw_text)
    try:
        json_keys = list(data_json.keys()) if isinstance(data_json, dict) else []
        form_keys = list(data_form.keys()) if isinstance(data_form, dict) else []
        current_app.logger.info(
            "register_payload_debug content_type=%s content_length=%s json_keys=%s form_keys=%s raw_len=%s",
            request.content_type,
            request.content_length,
            json_keys,
            form_keys,
            raw_len,
        )
    except Exception:
        pass

    data = data_json if isinstance(data_json, dict) and data_json else data_form
    if not data and raw_text:
        try:
            data = json.loads(raw_text)
        except Exception:
            data = {}
    if not isinstance(data, dict):
        data = {}

    name = (data.get("name") or data.get("full_name") or data.get("fullname") or "").strip()
    email = (data.get("email") or "").strip().lower()
    phone = (data.get("phone") or "").strip() or None
    password = data.get("password") or ""
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403

    u, err = _create_user(name=name, email=email, phone=phone, password=password, role="buyer")
    if err:
        body, code = err
        return jsonify(body), code
    referral_apply = _maybe_apply_referral_from_payload(u, data)
    try:
        access_token, access_expires_at = _issue_access_token(int(u.id))
        _refresh_rec, refresh_token = _issue_refresh_token_record(user_id=int(u.id), device_id=request.headers.get("X-Device-Id"))
        db.session.commit()
        body = _session_payload(
            u,
            access_token=access_token,
            access_expires_at=access_expires_at,
            refresh_token=refresh_token,
        )
        if referral_apply is not None:
            body["referral_apply"] = referral_apply
        return jsonify(body), 201
    except Exception:
        db.session.rollback()
        current_app.logger.exception("register_session_issue_failed")
        return jsonify({"message": "Failed to issue session"}), 500


@auth_bp.post("/login")
def login():
    rl = _rate_limit_response("login", limit=30, window_seconds=300)
    if rl is not None:
        return rl
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    if not email or not password:
        return jsonify({"message": "Email and password are required"}), 400

    try:
        db.session.rollback()
    except Exception:
        pass

    def _lookup_user():
        return User.query.filter_by(email=email).first()

    try:
        u = _lookup_user()
    except InternalError as e:
        if "InFailedSqlTransaction" in str(e):
            try:
                db.session.rollback()
                db.session.remove()
            except Exception:
                pass
            try:
                u = _lookup_user()
            except Exception:
                try:
                    current_app.logger.exception("login_aborted_retry_failed")
                except Exception:
                    pass
                return jsonify({"message": "Database error"}), 500
        else:
            try:
                db.session.rollback()
            except Exception:
                pass
            try:
                current_app.logger.exception("login_internal_error")
            except Exception:
                pass
            return jsonify({"message": "Database error"}), 500
    if not u or not u.check_password(password):
        return jsonify({"message": "Invalid credentials"}), 401

    try:
        access_token, access_expires_at = _issue_access_token(int(u.id))
        _refresh_rec, refresh_token = _issue_refresh_token_record(user_id=int(u.id), device_id=request.headers.get("X-Device-Id"))
        db.session.commit()
        return jsonify(_session_payload(
            u,
            access_token=access_token,
            access_expires_at=access_expires_at,
            refresh_token=refresh_token,
        )), 200
    except Exception:
        db.session.rollback()
        current_app.logger.exception("login_session_issue_failed")
        return jsonify({"message": "Failed to issue session"}), 500


@auth_bp.get("/me")
def me():
    token = _bearer_token()
    if not token:
        return jsonify({"message": "Missing Bearer token"}), 401

    payload = decode_token(token)
    if not payload or "sub" not in payload:
        return jsonify({"message": "Invalid or expired token"}), 401

    try:
        user_id = int(payload.get("sub"))
    except Exception:
        return jsonify({"message": "Invalid token payload"}), 401
    try:
        db.session.rollback()
    except Exception:
        pass

    def _lookup_user():
        return db.session.get(User, user_id)

    try:
        u = _lookup_user()
    except InternalError as e:
        if "InFailedSqlTransaction" in str(e):
            try:
                db.session.rollback()
                db.session.remove()
            except Exception:
                pass
            try:
                u = _lookup_user()
            except Exception:
                try:
                    current_app.logger.exception("me_aborted_retry_failed")
                except Exception:
                    pass
                return jsonify({"message": "Database error"}), 500
        else:
            try:
                db.session.rollback()
            except Exception:
                pass
            try:
                current_app.logger.exception("me_internal_error")
            except Exception:
                pass
            return jsonify({"message": "Database error"}), 500
    if not u:
        return jsonify({"message": "User not found"}), 404

    # Return user dict directly (cleanest for frontend)
    return jsonify(_user_payload_with_role_status(u)), 200


@auth_bp.post("/refresh")
def refresh():
    data = request.get_json(silent=True) or {}
    refresh_token = (data.get("refresh_token") or "").strip()
    if not refresh_token:
        return jsonify({"message": "refresh_token is required"}), 400

    now = datetime.utcnow()
    token_hash = _hash_token(refresh_token)
    rec = RefreshToken.query.filter_by(token_hash=token_hash).first()
    if not rec:
        return jsonify({"message": "Invalid refresh token"}), 401
    if rec.revoked_at is not None:
        return jsonify({"message": "Refresh token revoked"}), 401
    if rec.expires_at and rec.expires_at <= now:
        return jsonify({"message": "Refresh token expired"}), 401

    user = db.session.get(User, int(rec.user_id or 0))
    if not user:
        return jsonify({"message": "Invalid refresh token"}), 401

    try:
        _revoke_refresh_token_record(rec, when=now)
        access_token, access_expires_at = _issue_access_token(int(user.id))
        _new_rec, next_refresh_token = _issue_refresh_token_record(
            user_id=int(user.id),
            device_id=(data.get("device_id") or request.headers.get("X-Device-Id") or "").strip() or None,
        )
        db.session.commit()
        return jsonify(_session_payload(
            user,
            access_token=access_token,
            access_expires_at=access_expires_at,
            refresh_token=next_refresh_token,
        )), 200
    except Exception:
        db.session.rollback()
        current_app.logger.exception("refresh_token_rotation_failed")
        return jsonify({"message": "Failed to refresh session"}), 500


@auth_bp.post("/logout")
def logout():
    token = _bearer_token()
    payload = decode_token(token) if token else None
    sub = payload.get("sub") if isinstance(payload, dict) else None
    try:
        uid = int(sub) if sub is not None else None
    except Exception:
        uid = None
    if not uid:
        return jsonify({"message": "Unauthorized"}), 401

    data = request.get_json(silent=True) or {}
    refresh_token = (data.get("refresh_token") or "").strip()
    now = datetime.utcnow()
    revoked = 0
    try:
        if refresh_token:
            token_hash = _hash_token(refresh_token)
            rec = RefreshToken.query.filter_by(token_hash=token_hash, user_id=int(uid)).first()
            if rec and rec.revoked_at is None:
                _revoke_refresh_token_record(rec, when=now)
                revoked += 1
        revoked += _revoke_all_refresh_tokens_for_user(int(uid), when=now)
        db.session.commit()
    except Exception:
        db.session.rollback()
        current_app.logger.exception("logout_revoke_refresh_failed")
        return jsonify({"message": "Failed to logout"}), 500

    return jsonify({"ok": True, "revoked_refresh_tokens": int(revoked)}), 200


@auth_bp.post("/set-role")
def set_role():
    """Demo helper: set current user's role to buyer/merchant/driver."""
    env = (os.getenv("FLIPTRYBE_ENV", "dev") or "dev").strip().lower()
    allow_override = (os.getenv("ALLOW_DEV_ROLE_SWITCH", "") or "").strip() == "1"
    token = get_bearer_token(request.headers.get("Authorization", ""))
    if not token:
        return jsonify({"message": "Unauthorized"}), 401
    payload = decode_token(token)
    if not payload:
        return jsonify({"message": "Unauthorized"}), 401
    sub = payload.get("sub")
    if not sub:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        uid = int(sub)
    except Exception:
        return jsonify({"message": "Unauthorized"}), 401

    u = User.query.get(uid)
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        is_admin = (getattr(u, "role", "") or "").lower() == "admin"
    except Exception:
        is_admin = False

    if not is_admin:
        return jsonify({"error": "ROLE_CHANGE_NOT_ALLOWED", "message": "Only admin can change roles"}), 403
    if env not in ("dev", "development", "local", "test") or not allow_override:
        return jsonify({"error": "ROLE_CHANGE_NOT_ALLOWED", "message": "Role change is disabled on this environment"}), 403

    data = request.get_json(silent=True) or {}
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"error": "ROLE_CHANGE_NOT_ALLOWED", "message": "Admin role cannot be set via this endpoint"}), 403
    if role not in ("buyer", "merchant", "driver"):
        return jsonify({"message": "role must be buyer|merchant|driver"}), 400

    u.role = role
    try:
        db.session.add(u)
        try:
            db.session.add(AuditLog(actor_user_id=int(u.id), action="set_role", target_type="user", target_id=int(u.id), meta=f"role={role}"))
        except Exception:
            pass
        db.session.commit()
        return jsonify({"ok": True, "user": _user_payload_with_role_status(u)}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500



# ---------------------------
# Role-based registration (Phase 2.8)
# ---------------------------

def _register_common(payload: dict, role: str, extra: dict | None = None):
    try:
        try:
            db.session.rollback()
        except Exception:
            pass

        name = (payload.get("name") or payload.get("full_name") or payload.get("fullname") or "").strip()
        email = (payload.get("email") or "").strip().lower()
        password = (payload.get("password") or "").strip()
        raw_phone = (
            payload.get("phone") or
            payload.get("phone_number") or
            payload.get("phoneNumber") or
            payload.get("mobile") or
            payload.get("mobile_number") or
            ""
        )
        phone = "".join([c for c in str(raw_phone) if c not in [" ", "\t", "\n", "\r"]])
        role = (role or "").strip().lower()

        if role == "admin":
            return None, (jsonify({"message": "Admin signup is not allowed"}), 403)

        if not name:
            return None, (jsonify({"message": "name is required"}), 400)
        if not email or "@" not in email:
            return None, (jsonify({"message": "valid email is required"}), 400)
        if len(password) < 4:
            return None, (jsonify({"message": "password is required"}), 400)
        if not phone:
            return None, (jsonify({"message": "phone is required"}), 400)

        def _lookup_email():
            return User.query.filter_by(email=email).first()

        def _lookup_phone():
            return User.query.filter_by(phone=phone).first()

        try:
            existing_phone = _lookup_phone()
        except InternalError as e:
            if "InFailedSqlTransaction" in str(e):
                try:
                    db.session.rollback()
                    db.session.remove()
                except Exception:
                    pass
                try:
                    existing_phone = _lookup_phone()
                except Exception:
                    try:
                        current_app.logger.exception("register_common_aborted_retry_failed")
                    except Exception:
                        pass
                    return None, (jsonify({"message": "Database error"}), 500)
            else:
                try:
                    db.session.rollback()
                except Exception:
                    pass
                try:
                    current_app.logger.exception("register_common_internal_error")
                except Exception:
                    pass
                return None, (jsonify({"message": "Database error"}), 500)

        try:
            existing = _lookup_email()
        except InternalError as e:
            if "InFailedSqlTransaction" in str(e):
                try:
                    db.session.rollback()
                    db.session.remove()
                except Exception:
                    pass
                try:
                    existing = _lookup_email()
                except Exception:
                    try:
                        current_app.logger.exception("register_common_aborted_retry_failed")
                    except Exception:
                        pass
                    return None, (jsonify({"message": "Database error"}), 500)
            else:
                try:
                    db.session.rollback()
                except Exception:
                    pass
                try:
                    current_app.logger.exception("register_common_internal_error")
                except Exception:
                    pass
                return None, (jsonify({"message": "Database error"}), 500)

        conflict_msg = _conflict_message(existing, existing_phone)
        if conflict_msg:
            try:
                if existing_phone:
                    record_account_flag(int(existing_phone.id), "DUP_PHONE", signal=phone, details={"phone": phone})
                if existing:
                    record_account_flag(int(existing.id), "DUP_EMAIL", signal=email, details={"email": email})
            except Exception:
                pass
            try:
                current_app.logger.info("register_conflict route=/api/auth/register/%s type=%s", role, conflict_msg)
            except Exception:
                pass
            return None, (jsonify({"message": conflict_msg}), 409)

        u = User(name=name, email=email, role=role, phone=phone)
        u.set_password(password)
        try:
            u.is_verified = False
        except Exception:
            pass

        try:
            if extra:
                if hasattr(u, "profile_json"):
                    u.profile_json = json.dumps(extra)
                else:
                    setattr(u, "profile_json", json.dumps(extra))
        except Exception:
            pass

        try:
            db.session.add(u)
            db.session.commit()
        except IntegrityError as e:
            db.session.rollback()
            try:
                current_app.logger.exception("register_common_integrity_error")
            except Exception:
                pass
            try:
                if User.query.filter_by(phone=phone).first():
                    return None, (jsonify({"message": "Phone already in use"}), 409)
            except Exception:
                pass
            return None, (jsonify({"message": _conflict_message_from_integrity(e)}), 409)
        except SQLAlchemyError:
            db.session.rollback()
            try:
                current_app.logger.exception("register_common_db_error")
            except Exception:
                pass
            return None, (jsonify({"message": "Failed to register"}), 500)

        try:
            ensure_user_referral_code(u)
        except Exception:
            db.session.rollback()

        try:
            vtoken = _issue_verification_token(u, ttl_minutes=30)
            if vtoken:
                _send_verification_email(u, vtoken)
        except Exception:
            pass

        return {"user": _user_payload_with_role_status(u)}, None
    finally:
        try:
            db.session.remove()
        except Exception:
            pass


@auth_bp.post("/register/buyer")
def register_buyer():
    rl = _rate_limit_response("register", limit=25, window_seconds=300)
    if rl is not None:
        return rl
    data = _get_request_payload("register_buyer")
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403
    payload, err = _register_common(data, role="buyer")
    if err:
        return err
    user_payload = payload.get("user") if isinstance(payload, dict) else {}
    user_id = int((user_payload or {}).get("id") or 0)
    user = User.query.get(user_id) if user_id else None
    if not user:
        return jsonify({"message": "Failed to load user after signup"}), 500
    referral_apply = _maybe_apply_referral_from_payload(user, data)
    try:
        access_token, access_expires_at = _issue_access_token(int(user.id))
        _refresh_rec, refresh_token = _issue_refresh_token_record(user_id=int(user.id), device_id=request.headers.get("X-Device-Id"))
        db.session.commit()
        body = _session_payload(
            user,
            access_token=access_token,
            access_expires_at=access_expires_at,
            refresh_token=refresh_token,
        )
        if referral_apply is not None:
            body["referral_apply"] = referral_apply
        return jsonify(body), 201
    except Exception:
        db.session.rollback()
        current_app.logger.exception("register_buyer_session_issue_failed")
        return jsonify({"message": "Failed to issue session"}), 500


@auth_bp.post("/register/merchant")
def register_merchant():
    rl = _rate_limit_response("register", limit=25, window_seconds=300)
    if rl is not None:
        return rl
    data = _get_request_payload("register_merchant")
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403
    business_name = (data.get("business_name") or "").strip()
    phone = (
        data.get("phone") or
        data.get("phone_number") or
        data.get("phoneNumber") or
        data.get("mobile") or
        data.get("mobile_number") or
        ""
    )
    phone = "".join([c for c in str(phone) if c not in [" ", "\t", "\n", "\r"]])
    state = (data.get("state") or "").strip()
    city = (data.get("city") or "").strip()
    category = (data.get("category") or "").strip()
    reason = (data.get("reason") or "").strip()

    if not business_name:
        return jsonify({"message": "business_name is required"}), 400
    if not phone:
        return jsonify({"ok": False, "error": "PHONE_REQUIRED", "message": "Phone is required"}), 400
    if not state or not city:
        return jsonify({"message": "state and city are required"}), 400
    if not category:
        return jsonify({"message": "category is required"}), 400
    if not reason:
        return jsonify({"message": "reason is required"}), 400

    email = (data.get("email") or "").strip().lower()
    password = (data.get("password") or "").strip()
    if not email or "@" not in email:
        return jsonify({"message": "valid email is required"}), 400
    if len(password) < 4:
        return jsonify({"message": "password is required"}), 400

    try:
        existing_phone = User.query.filter_by(phone=phone).first()
    except InternalError as e:
        if "InFailedSqlTransaction" in str(e):
            try:
                db.session.rollback()
                db.session.remove()
            except Exception:
                pass
            try:
                existing_phone = User.query.filter_by(phone=phone).first()
            except Exception:
                return jsonify({"message": "Database error"}), 500
        else:
            try:
                db.session.rollback()
            except Exception:
                pass
            return jsonify({"message": "Database error"}), 500

    try:
        dup_users = find_duplicate_phone_users(0, phone)
        if dup_users:
            for uid in dup_users:
                try:
                    record_account_flag(int(uid), "DUP_PHONE", signal=phone, details={"phone": phone, "applicant_email": email})
                except Exception:
                    pass
            return jsonify({"message": "Phone already in use by another account"}), 409
    except Exception:
        pass

    try:
        existing = User.query.filter_by(email=email).first()
    except InternalError as e:
        if "InFailedSqlTransaction" in str(e):
            try:
                db.session.rollback()
                db.session.remove()
            except Exception:
                pass
            try:
                existing = User.query.filter_by(email=email).first()
            except Exception:
                return jsonify({"message": "Database error"}), 500
        else:
            try:
                db.session.rollback()
            except Exception:
                pass
            return jsonify({"message": "Database error"}), 500

    conflict_msg = _conflict_message(existing, existing_phone)
    if conflict_msg:
        try:
            current_app.logger.info("register_conflict route=/api/auth/register/merchant type=%s", conflict_msg)
        except Exception:
            pass
        return jsonify({"message": conflict_msg}), 409
    else:
        user = User(
            name=(data.get("owner_name") or data.get("name") or business_name),
            email=email,
            role="buyer",
            phone=phone,
        )
        user.set_password(password)
        try:
            user.is_verified = False
        except Exception:
            pass
        try:
            db.session.add(user)
            db.session.commit()
        except IntegrityError as e:
            db.session.rollback()
            try:
                current_app.logger.exception("register_merchant_integrity_error")
            except Exception:
                pass
            emsg = str(e).lower()
            if "phone" in emsg and ("not null" in emsg or "null value" in emsg):
                return jsonify({"ok": False, "error": "PHONE_REQUIRED", "message": "Phone is required"}), 400
            if "unique" in emsg or "duplicate key" in emsg:
                return jsonify({"ok": False, "error": "CONFLICT", "message": _conflict_message_from_integrity(e)}), 409
            return jsonify({"ok": False, "error": "REGISTER_FAILED", "message": "Failed to register"}), 500
        except SQLAlchemyError:
            db.session.rollback()
            try:
                current_app.logger.exception("register_merchant_db_error")
            except Exception:
                pass
            return jsonify({"ok": False, "error": "REGISTER_FAILED", "message": "Failed to register"}), 500
        try:
            vtoken = _issue_verification_token(user, ttl_minutes=30)
            if vtoken:
                _send_verification_email(user, vtoken)
        except Exception:
            pass

    if user.role not in ("buyer", "driver", "inspector"):
        return jsonify({"message": "Role change not allowed"}), 403

    # Phone already validated above; still log against this user for auditing
    try:
        flag_duplicate_phone(int(user.id), phone)
    except Exception:
        pass

    pending = RoleChangeRequest.query.filter_by(user_id=int(user.id), status="PENDING").first()
    if pending:
        return jsonify({"message": "Existing pending request"}), 409

    req = RoleChangeRequest(
        user_id=int(user.id),
        current_role=(user.role or "buyer"),
        requested_role="merchant",
        reason=f"{reason} | business_name={business_name}; phone={phone}; state={state}; city={city}; category={category}",
        status="PENDING",
        created_at=datetime.utcnow(),
    )
    try:
        db.session.add(req)
        db.session.commit()
        log_event(
            "role_request_submitted",
            actor_user_id=int(user.id),
            subject_type="role_request",
            subject_id=int(req.id),
            request_id=get_request_id(),
            idempotency_key=f"role_request_submitted:{int(req.id)}",
            metadata={"requested_role": req.requested_role or "", "current_role": req.current_role or ""},
        )
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create request", "error": str(e)}), 500

    referral_apply = _maybe_apply_referral_from_payload(user, data)
    try:
        access_token, access_expires_at = _issue_access_token(int(user.id))
        _refresh_rec, refresh_token = _issue_refresh_token_record(user_id=int(user.id), device_id=request.headers.get("X-Device-Id"))
        db.session.commit()
    except Exception:
        db.session.rollback()
        current_app.logger.exception("register_merchant_session_issue_failed")
        return jsonify({"message": "Failed to issue session"}), 500
    body = _session_payload(
        user,
        access_token=access_token,
        access_expires_at=access_expires_at,
        refresh_token=refresh_token,
    )
    body["request"] = req.to_dict()
    if referral_apply is not None:
        body["referral_apply"] = referral_apply
    return jsonify(body), 201


@auth_bp.post("/register/driver")
def register_driver():
    rl = _rate_limit_response("register", limit=25, window_seconds=300)
    if rl is not None:
        return rl
    data = _get_request_payload("register_driver")
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403

    # Admin-mediated activation: we still create the base user + a pending role-change request.
    name = (data.get("name") or data.get("full_name") or data.get("fullname") or "").strip()
    email = (data.get("email") or "").strip().lower()
    password = (data.get("password") or "").strip()

    phone = (
        data.get("phone") or
        data.get("phone_number") or
        data.get("phoneNumber") or
        data.get("mobile") or
        data.get("mobile_number") or
        ""
    )
    phone = "".join([c for c in str(phone) if c not in [" ", "\t", "\n", "\r"]])
    state = (data.get("state") or "").strip()
    city = (data.get("city") or "").strip()
    vehicle_type = (data.get("vehicle_type") or "").strip()
    plate_number = (data.get("plate_number") or "").strip()

    if not phone:
        return jsonify({"message": "phone is required"}), 400
    if not state or not city:
        return jsonify({"message": "state and city are required"}), 400
    if not vehicle_type:
        return jsonify({"message": "vehicle_type is required"}), 400
    if not plate_number:
        return jsonify({"message": "plate_number is required"}), 400

    if not email or "@" not in email:
        return jsonify({"message": "valid email is required"}), 400
    if len(password) < 4:
        return jsonify({"message": "password is required"}), 400
    if not name:
        return jsonify({"message": "name is required"}), 400

    # Create base account as buyer (safe default) then queue role change.
    base_payload = {
        "name": name,
        "email": email,
        "password": password,
        "phone": phone,
    }
    payload, err = _register_common(base_payload, role="buyer", extra={"phone": phone, "state": state, "city": city})
    if err:
        return err

    user = User.query.get(int(payload["user"]["id"]))
    if not user:
        return jsonify({"message": "Failed to load user after signup"}), 500

    req = RoleChangeRequest(
        user_id=int(user.id),
        current_role=(user.role or "buyer"),
        requested_role="driver",
        reason=f"driver_signup | phone={phone}; state={state}; city={city}; vehicle_type={vehicle_type}; plate_number={plate_number}",
        status="PENDING",
        created_at=datetime.utcnow(),
    )
    try:
        db.session.add(req)
        db.session.commit()
        log_event(
            "role_request_submitted",
            actor_user_id=int(user.id),
            subject_type="role_request",
            subject_id=int(req.id),
            request_id=get_request_id(),
            idempotency_key=f"role_request_submitted:{int(req.id)}",
            metadata={"requested_role": req.requested_role or "", "current_role": req.current_role or ""},
        )
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create request", "error": str(e)}), 500

    referral_apply = _maybe_apply_referral_from_payload(user, data)
    try:
        access_token, access_expires_at = _issue_access_token(int(user.id))
        _refresh_rec, refresh_token = _issue_refresh_token_record(user_id=int(user.id), device_id=request.headers.get("X-Device-Id"))
        db.session.commit()
    except Exception:
        db.session.rollback()
        current_app.logger.exception("register_driver_session_issue_failed")
        return jsonify({"message": "Failed to issue session"}), 500
    body = _session_payload(
        user,
        access_token=access_token,
        access_expires_at=access_expires_at,
        refresh_token=refresh_token,
    )
    body["request"] = req.to_dict()
    body["message"] = "Driver signup submitted. Activation is admin-mediated."
    if referral_apply is not None:
        body["referral_apply"] = referral_apply
    return jsonify(body), 201


@auth_bp.post("/register/inspector")
def register_inspector():
    rl = _rate_limit_response("register", limit=25, window_seconds=300)
    if rl is not None:
        return rl
    data = _get_request_payload("register_inspector")
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403

    name = (data.get("name") or data.get("full_name") or data.get("fullname") or "").strip()
    email = (data.get("email") or "").strip().lower()
    password = (data.get("password") or "").strip()

    phone = (
        data.get("phone") or
        data.get("phone_number") or
        data.get("phoneNumber") or
        data.get("mobile") or
        data.get("mobile_number") or
        ""
    )
    phone = "".join([c for c in str(phone) if c not in [" ", "\t", "\n", "\r"]])
    state = (data.get("state") or "").strip()
    city = (data.get("city") or "").strip()
    region = (data.get("region") or "").strip()
    reason = (data.get("reason") or "").strip()

    if not phone:
        return jsonify({"message": "phone is required"}), 400
    if not state or not city:
        return jsonify({"message": "state and city are required"}), 400
    if not reason:
        return jsonify({"message": "reason is required"}), 400

    if not email or "@" not in email:
        return jsonify({"message": "valid email is required"}), 400
    if len(password) < 4:
        return jsonify({"message": "password is required"}), 400
    if not name:
        return jsonify({"message": "name is required"}), 400

    base_payload = {
        "name": name,
        "email": email,
        "password": password,
        "phone": phone,
    }
    payload, err = _register_common(base_payload, role="buyer", extra={"phone": phone, "state": state, "city": city})
    if err:
        return err

    user = User.query.get(int(payload["user"]["id"]))
    if not user:
        return jsonify({"message": "Failed to load user after signup"}), 500

    req = RoleChangeRequest(
        user_id=int(user.id),
        current_role=(user.role or "buyer"),
        requested_role="inspector",
        reason=f"inspector_signup | phone={phone}; state={state}; city={city}; region={region}; reason={reason}",
        status="PENDING",
        created_at=datetime.utcnow(),
    )
    try:
        db.session.add(req)
        db.session.commit()
        log_event(
            "role_request_submitted",
            actor_user_id=int(user.id),
            subject_type="role_request",
            subject_id=int(req.id),
            request_id=get_request_id(),
            idempotency_key=f"role_request_submitted:{int(req.id)}",
            metadata={"requested_role": req.requested_role or "", "current_role": req.current_role or ""},
        )
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create request", "error": str(e)}), 500

    referral_apply = _maybe_apply_referral_from_payload(user, data)
    try:
        access_token, access_expires_at = _issue_access_token(int(user.id))
        _refresh_rec, refresh_token = _issue_refresh_token_record(user_id=int(user.id), device_id=request.headers.get("X-Device-Id"))
        db.session.commit()
    except Exception:
        db.session.rollback()
        current_app.logger.exception("register_inspector_session_issue_failed")
        return jsonify({"message": "Failed to issue session"}), 500
    body = _session_payload(
        user,
        access_token=access_token,
        access_expires_at=access_expires_at,
        refresh_token=refresh_token,
    )
    body["request"] = req.to_dict()
    body["message"] = "Inspector signup submitted. Activation is admin-mediated."
    if referral_apply is not None:
        body["referral_apply"] = referral_apply
    return jsonify(body), 201


@auth_bp.get("/verify-email")
def verify_email():
    try:
        db.session.rollback()
    except Exception:
        pass
    token = (request.args.get("token") or "").strip()
    if not token:
        return jsonify({"message": "token required"}), 400

    now = datetime.utcnow()
    rec = None
    try:
        rec = EmailVerificationToken.query.filter_by(
            token_hash=_hash_token(token)
        ).filter(EmailVerificationToken.used_at.is_(None)).first()
    except Exception:
        rec = None
    if not rec or (rec.expires_at and rec.expires_at < now):
        return jsonify({"message": "Invalid or expired token"}), 400

    try:
        u = User.query.get(int(rec.user_id))
    except Exception:
        u = None
    if not u:
        return jsonify({"message": "Invalid or expired token"}), 400

    u.is_verified = True
    rec.used_at = now
    try:
        db.session.add(u)
        db.session.add(rec)
        db.session.commit()
        current_app.logger.info("email_verify_confirmed user_id=%s", u.id)
        return jsonify({"ok": True, "message": "Email verified"}), 200
    except Exception:
        db.session.rollback()
        current_app.logger.exception("email_verify_confirm_failed")
        return jsonify({"message": "Failed"}), 500


@auth_bp.post("/verify-email/resend")
def resend_verify_email():
    try:
        db.session.rollback()
    except Exception:
        pass
    mode = _integration_mode()
    token = _bearer_token()
    payload = decode_token(token) if token else None
    sub = payload.get("sub") if isinstance(payload, dict) else None
    try:
        uid = int(sub) if sub is not None else None
    except Exception:
        uid = None
    if not uid:
        return jsonify({"ok": False, "message": "Unauthorized", "mode": mode}), 401

    u = User.query.get(int(uid))
    if not u:
        return jsonify({"ok": False, "message": "Unauthorized", "mode": mode}), 401
    if bool(getattr(u, "is_verified", False)):
        return jsonify({"ok": True, "message": "Already verified", "mode": mode}), 200

    debug_requested = (request.headers.get("X-Debug", "").strip() == "1")
    now = datetime.utcnow()
    try:
        last = EmailVerificationToken.query.filter_by(user_id=int(u.id)).order_by(EmailVerificationToken.created_at.desc()).first()
        if last and (now - last.created_at).total_seconds() < 60:
            wait_seconds = int(max(0, 60 - (now - last.created_at).total_seconds()))
            body = {
                "ok": True,
                "message": "Please wait before resending",
                "mode": mode,
                "retry_after_seconds": wait_seconds,
            }
            return jsonify(body), 200
    except Exception:
        pass

    try:
        vtoken = _issue_verification_token(u, ttl_minutes=30)
        if not vtoken:
            return jsonify({"ok": False, "error": "TOKEN_ISSUE_FAILED", "message": "Failed to issue verification token", "mode": mode}), 500
        send_result = _send_verification_email(u, vtoken)
        effective_mode = (send_result.get("mode") or mode or "disabled").strip().lower()
        if not bool(send_result.get("ok")):
            code = (send_result.get("error") or "VERIFY_SEND_FAILED").strip()
            message = (send_result.get("message") or "Failed to send verification email").strip()
            status = 503 if code == "INTEGRATION_DISABLED" else 500
            body = {"ok": False, "error": code, "message": message, "mode": effective_mode}
            if debug_requested and effective_mode != "live":
                body["verification_link"] = send_result.get("link")
            return jsonify(body), status
        current_app.logger.info("email_verify_resend user_id=%s", u.id)
        body = {
            "ok": True,
            "message": "Verification email sent",
            "mode": effective_mode,
            "delivery": send_result.get("delivery"),
        }
        if debug_requested and effective_mode != "live":
            body["verification_link"] = send_result.get("link")
        return jsonify(body), 200
    except Exception:
        db.session.rollback()
        current_app.logger.exception("email_verify_resend_failed")
        return jsonify({"ok": False, "error": "VERIFY_SEND_FAILED", "message": "Failed to send verification email", "mode": mode}), 500


@auth_bp.get("/verify-email/status")
def verify_email_status():
    token = _bearer_token()
    payload = decode_token(token) if token else None
    sub = payload.get("sub") if isinstance(payload, dict) else None
    try:
        uid = int(sub) if sub is not None else None
    except Exception:
        uid = None
    if not uid:
        return jsonify({"message": "Unauthorized"}), 401
    u = User.query.get(int(uid))
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    return jsonify({"ok": True, "verified": bool(getattr(u, "is_verified", False))}), 200


@auth_bp.post("/password/forgot")
def password_forgot():
    try:
        db.session.rollback()
    except Exception:
        pass
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    if not email:
        return jsonify({"ok": True, "message": "If account exists, we sent a reset email."}), 200

    try:
        u = User.query.filter_by(email=email).first()
    except Exception:
        u = None
    if not u:
        return jsonify({"ok": True, "message": "If account exists, we sent a reset email."}), 200

    now = datetime.utcnow()
    token = secrets.token_urlsafe(32)
    rec = PasswordResetToken(
        user_id=int(u.id),
        token_hash=_hash_token(token),
        created_at=now,
        expires_at=now + timedelta(minutes=30),
        used_at=None,
    )
    try:
        db.session.add(rec)
        db.session.commit()
        # Send email or log link
        reset_link = f"{_verification_base_url()}/reset-password?token={token}"
        current_app.logger.info("PASSWORD_RESET_LINK: %s", reset_link)
        current_app.logger.info("password_reset_requested email=%s", email)
    except Exception:
        db.session.rollback()
        current_app.logger.exception("password_reset_request_failed")

    return jsonify({"ok": True, "message": "If account exists, we sent a reset email."}), 200


@auth_bp.post("/password/reset")
def password_reset():
    try:
        db.session.rollback()
    except Exception:
        pass
    data = request.get_json(silent=True) or {}
    token = (data.get("token") or "").strip()
    new_password = (data.get("new_password") or "").strip()

    if not new_password or len(new_password) < 4:
        return jsonify({"message": "new_password is required"}), 400
    if not token:
        return jsonify({"message": "token required"}), 400

    now = datetime.utcnow()
    rec = None
    try:
        rec = PasswordResetToken.query.filter_by(
            token_hash=_hash_token(token)
        ).filter(PasswordResetToken.used_at.is_(None)).first()
    except Exception:
        rec = None
    if not rec or (rec.expires_at and rec.expires_at < now):
        return jsonify({"message": "Invalid or expired token"}), 400

    try:
        u = User.query.get(int(rec.user_id))
    except Exception:
        u = None
    if not u:
        return jsonify({"message": "Invalid or expired token"}), 400

    u.set_password(new_password)
    rec.used_at = now
    try:
        _revoke_all_refresh_tokens_for_user(int(u.id), when=now)
        db.session.add(u)
        db.session.add(rec)
        db.session.commit()
        current_app.logger.info("password_reset_completed user_id=%s", u.id)
        return jsonify({"ok": True}), 200
    except Exception:
        db.session.rollback()
        current_app.logger.exception("password_reset_failed")
        return jsonify({"message": "Failed"}), 500
