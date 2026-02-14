from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User
from app.services.referral_service import (
    apply_referral_code,
    ensure_user_referral_code,
    referral_history_for_user,
    referral_stats_for_user,
)
from app.utils.jwt_utils import decode_token, get_bearer_token


referral_bp = Blueprint("referral_bp", __name__, url_prefix="/api/referral")


def _current_user() -> User | None:
    token = get_bearer_token(request.headers.get("Authorization", ""))
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    try:
        uid = int(payload.get("sub"))
    except Exception:
        return None
    try:
        return db.session.get(User, uid)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return None


@referral_bp.get("/code")
def referral_code():
    user = _current_user()
    if not user:
        return jsonify({"ok": False, "error": "UNAUTHORIZED", "message": "Unauthorized"}), 401
    code = ensure_user_referral_code(user)
    return jsonify({"ok": True, "referral_code": code}), 200


@referral_bp.get("/stats")
def referral_stats():
    user = _current_user()
    if not user:
        return jsonify({"ok": False, "error": "UNAUTHORIZED", "message": "Unauthorized"}), 401
    code = ensure_user_referral_code(user)
    stats = referral_stats_for_user(int(user.id))
    return jsonify(
        {
            **stats,
            "referral_code": code,
        }
    ), 200


@referral_bp.post("/apply")
def referral_apply():
    user = _current_user()
    if not user:
        return jsonify({"ok": False, "error": "UNAUTHORIZED", "message": "Unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    code = (
        payload.get("referral_code")
        or payload.get("code")
        or payload.get("referred_by")
        or ""
    )
    result = apply_referral_code(user=user, code=str(code))
    status = 200 if result.get("ok") else 400
    if result.get("error") == "REFERRAL_NOT_FOUND":
        status = 404
    if result.get("error") == "SELF_REFERRAL":
        status = 409
    return jsonify(result), status


@referral_bp.get("/history")
def referral_history():
    user = _current_user()
    if not user:
        return jsonify({"ok": False, "error": "UNAUTHORIZED", "message": "Unauthorized"}), 401
    try:
        limit = int(request.args.get("limit") or 50)
    except Exception:
        limit = 50
    try:
        offset = int(request.args.get("offset") or 0)
    except Exception:
        offset = 0
    data = referral_history_for_user(int(user.id), limit=limit, offset=offset)
    return jsonify(data), 200
