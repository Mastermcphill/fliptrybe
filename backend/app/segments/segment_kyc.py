from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, KycRequest
from app.utils.jwt_utils import decode_token

kyc_bp = Blueprint("kyc_bp", __name__, url_prefix="/api/kyc")

_INIT_DONE = False


@kyc_bp.before_app_request
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
        return None


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    if (getattr(u, "role", "") or "").strip().lower() == "admin":
        return True
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


@kyc_bp.get("/status")
def status():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    req = KycRequest.query.filter_by(user_id=u.id).first()
    if not req:
        req = KycRequest(user_id=u.id, status="unverified")
        try:
            db.session.add(req)
            db.session.commit()
        except Exception:
            db.session.rollback()
    return jsonify({"ok": True, "kyc": req.to_dict()}), 200


@kyc_bp.post("/submit")
def submit():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    full_name = (payload.get("full_name") or "").strip()
    id_type = (payload.get("id_type") or "").strip().lower()
    id_number = (payload.get("id_number") or "").strip()

    if not full_name or not id_type or not id_number:
        return jsonify({"message": "full_name, id_type, id_number are required"}), 400

    if id_type not in ("nin", "bvn", "passport", "drivers_license"):
        return jsonify({"message": "Invalid id_type"}), 400

    req = KycRequest.query.filter_by(user_id=u.id).first()
    if not req:
        req = KycRequest(user_id=u.id)

    req.full_name = full_name
    req.id_type = id_type
    req.id_number = id_number
    req.status = "pending"
    req.note = "Submitted. Demo review happens via admin action."
    req.updated_at = datetime.utcnow()

    try:
        db.session.add(req)
        db.session.commit()
        return jsonify({"ok": True, "kyc": req.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to submit", "error": str(e)}), 500


@kyc_bp.post("/admin/set")
def admin_set():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    user_id = payload.get("user_id")
    status = (payload.get("status") or "").strip().lower()
    note = (payload.get("note") or "").strip()

    try:
        uid = int(user_id)
    except Exception:
        return jsonify({"message": "user_id is required"}), 400

    if status not in ("unverified", "pending", "verified", "rejected"):
        return jsonify({"message": "Invalid status"}), 400

    req = KycRequest.query.filter_by(user_id=uid).first()
    if not req:
        req = KycRequest(user_id=uid, status=status)
    req.status = status
    req.note = note or req.note
    req.updated_at = datetime.utcnow()

    try:
        db.session.add(req)
        db.session.commit()
        return jsonify({"ok": True, "kyc": req.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to update", "error": str(e)}), 500


@kyc_bp.get("/admin/pending")
def admin_pending():
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    try:
        rows = (
            db.session.query(KycRequest, User)
            .outerjoin(User, User.id == KycRequest.user_id)
            .filter(KycRequest.status == "pending")
            .order_by(KycRequest.updated_at.desc())
            .limit(300)
            .all()
        )
    except Exception as e:
        db.session.rollback()
        return jsonify({"ok": False, "message": "Failed to fetch pending KYC", "error": str(e)}), 500

    items = []
    for req, user in rows:
        items.append(
            {
                "id": int(req.id),
                "user_id": int(req.user_id),
                "name": (req.full_name or (getattr(user, "name", "") if user else "") or "").strip(),
                "email": (getattr(user, "email", "") if user else "") or "",
                "id_type": req.id_type or "",
                "id_number": req.id_number or "",
                "status": req.status or "pending",
                "note": req.note or "",
                "updated_at": req.updated_at.isoformat() if req.updated_at else None,
            }
        )
    return jsonify({"ok": True, "items": items}), 200
