from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, RoleChangeRequest, MerchantProfile
from app.utils.jwt_utils import decode_token, get_bearer_token

role_change_bp = Blueprint("role_change_bp", __name__, url_prefix="/api")

_INIT = False


@role_change_bp.before_app_request
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
    return User.query.get(uid)


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    return _role(u) == "admin"


def _allowed_request(current_role: str, requested_role: str) -> bool:
    current = (current_role or "").strip().lower()
    requested = (requested_role or "").strip().lower()
    if requested not in ("merchant", "driver", "inspector"):
        return False
    # Only buyers can request role changes. Merchants cannot pivot to other roles via self-service.
    if current in ("buyer", "seller"):
        return True
    # Drivers/inspectors can request merchant upgrade (optional), but cannot request admin.
    if requested == "merchant" and current in ("driver", "inspector"):
        return True
    return False


@role_change_bp.post("/role-requests")
def request_role_change():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    requested_role = (payload.get("requested_role") or "merchant").strip().lower()
    reason = (payload.get("reason") or "").strip()

    current_role = _role(u)
    if not _allowed_request(current_role, requested_role):
        return jsonify({"message": "Role change not allowed"}), 403

    pending = RoleChangeRequest.query.filter_by(user_id=int(u.id), status="PENDING").first()
    if pending:
        return jsonify({"message": "Existing pending request"}), 409

    req = RoleChangeRequest(
        user_id=int(u.id),
        current_role=current_role,
        requested_role=requested_role,
        reason=reason,
        status="PENDING",
        created_at=datetime.utcnow(),
    )

    try:
        db.session.add(req)
        db.session.commit()
        return jsonify({"ok": True, "request": req.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@role_change_bp.get("/role-requests/me")
def my_role_request():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    row = (
        RoleChangeRequest.query
        .filter_by(user_id=int(u.id))
        .order_by(RoleChangeRequest.created_at.desc())
        .first()
    )
    if not row:
        return jsonify({"ok": True, "request": None}), 200
    return jsonify({"ok": True, "request": row.to_dict()}), 200


@role_change_bp.get("/admin/role-requests")
def list_role_requests():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"error": "ROLE_CHANGE_NOT_ALLOWED", "message": "Only admin can change roles"}), 403

    status = (request.args.get("status") or "").strip().upper()
    q = RoleChangeRequest.query
    if status in ("PENDING", "APPROVED", "REJECTED"):
        q = q.filter_by(status=status)

    rows = q.order_by(RoleChangeRequest.created_at.desc()).limit(200).all()
    return jsonify({"ok": True, "items": [r.to_dict() for r in rows]}), 200


@role_change_bp.post("/admin/role-requests/<int:req_id>/approve")
def approve_role_request(req_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"error": "ROLE_CHANGE_NOT_ALLOWED", "message": "Only admin can change roles"}), 403

    req = RoleChangeRequest.query.get(req_id)
    if not req:
        return jsonify({"message": "Not found"}), 404
    if req.status != "PENDING":
        return jsonify({"ok": True, "request": req.to_dict()}), 200

    if not _allowed_request(req.current_role, req.requested_role):
        req.status = "REJECTED"
        req.decided_at = datetime.utcnow()
        req.admin_user_id = int(u.id)
        db.session.add(req)
        db.session.commit()
        return jsonify({"message": "Role change not allowed", "request": req.to_dict()}), 400

    target = User.query.get(int(req.user_id))
    if not target:
        req.status = "REJECTED"
        req.decided_at = datetime.utcnow()
        req.admin_user_id = int(u.id)
        db.session.add(req)
        db.session.commit()
        return jsonify({"message": "User not found", "request": req.to_dict()}), 404

    target.role = req.requested_role
    payload = request.get_json(silent=True) or {}
    admin_note = (payload.get("admin_note") or "").strip()

    req.status = "APPROVED"
    req.decided_at = datetime.utcnow()
    req.admin_user_id = int(u.id)
    if admin_note:
        req.admin_note = admin_note

    try:
        db.session.add(target)
        db.session.add(req)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500

    try:
        if req.requested_role == "merchant":
            mp = MerchantProfile.query.filter_by(user_id=int(target.id)).first()
            if not mp:
                mp = MerchantProfile(user_id=int(target.id))
                db.session.add(mp)
                db.session.commit()
    except Exception:
        db.session.rollback()

    return jsonify({"ok": True, "request": req.to_dict(), "user": target.to_dict()}), 200


@role_change_bp.post("/admin/role-requests/<int:req_id>/reject")
def reject_role_request(req_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"error": "ROLE_CHANGE_NOT_ALLOWED", "message": "Only admin can change roles"}), 403

    req = RoleChangeRequest.query.get(req_id)
    if not req:
        return jsonify({"message": "Not found"}), 404

    if req.status != "PENDING":
        return jsonify({"ok": True, "request": req.to_dict()}), 200

    payload = request.get_json(silent=True) or {}
    admin_note = (payload.get("admin_note") or "").strip()
    if not admin_note:
        return jsonify({"message": "admin_note is required"}), 400

    req.status = "REJECTED"
    req.decided_at = datetime.utcnow()
    req.admin_user_id = int(u.id)
    req.admin_note = admin_note

    try:
        db.session.add(req)
        db.session.commit()
        return jsonify({"ok": True, "request": req.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500
