from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, DriverProfile, Order, Listing, MoneyBoxAccount
from app.utils.jwt_utils import decode_token
from app.utils.account_flags import flag_duplicate_phone
from app.utils.moneybox import liquidate_to_wallet

driver_profile_bp = Blueprint("driver_profile_bp", __name__, url_prefix="/api")


_INIT = False


@driver_profile_bp.before_app_request
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


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    try:
        if int(u.id or 0) == 1:
            return True
    except Exception:
        pass
    try:
        return "admin" in (u.email or "").lower()
    except Exception:
        return False


@driver_profile_bp.route("/driver/profile", methods=["GET", "POST"])
def driver_profile():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    if request.method == "GET":
        p = DriverProfile.query.filter_by(user_id=u.id).first()
        if not p:
            return jsonify({"ok": True, "profile": None}), 200
        return jsonify({"ok": True, "profile": p.to_dict()}), 200

    payload = request.get_json(silent=True) or {}

    p = DriverProfile.query.filter_by(user_id=u.id).first()
    if not p:
        p = DriverProfile(user_id=u.id)

    incoming_phone = (payload.get("phone") or p.phone or "").strip()
    if incoming_phone:
        try:
            dup_users = flag_duplicate_phone(int(u.id), incoming_phone)
            if dup_users:
                return jsonify({"message": "Phone already in use by another account"}), 409
        except Exception:
            pass
    p.phone = incoming_phone
    p.vehicle_type = (payload.get("vehicle_type") or p.vehicle_type or "").strip()
    p.plate_number = (payload.get("plate_number") or p.plate_number or "").strip()
    p.state = (payload.get("state") or p.state or "").strip()
    p.city = (payload.get("city") or p.city or "").strip()
    p.locality = (payload.get("locality") or p.locality or "").strip()

    is_active = payload.get("is_active")
    if is_active is not None:
        if isinstance(is_active, bool):
            p.is_active = is_active
        else:
            p.is_active = str(is_active).lower() in ("1", "true", "yes", "y", "on")

    p.updated_at = datetime.utcnow()

    try:
        db.session.add(p)
        db.session.commit()
        return jsonify({"ok": True, "profile": p.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@driver_profile_bp.get("/merchant/drivers")
def list_drivers_for_merchants():
    """Merchants/Admin can see active drivers directory.

    Optional query params:
      - state
      - city
      - locality

    If none provided, we try to infer merchant location from the caller's latest listing.
    """
    u = _current_user()
    if not u:
        return jsonify([]), 200

    q_state = (request.args.get("state") or "").strip()
    q_city = (request.args.get("city") or "").strip()
    q_locality = (request.args.get("locality") or "").strip()

    # Infer from merchant's latest listing if no filters passed
    if not (q_state or q_city or q_locality):
        try:
            last_listing = (
                Listing.query.filter_by(user_id=u.id)
                .order_by(Listing.created_at.desc())
                .first()
            )
            if last_listing:
                q_state = (last_listing.state or "").strip()
                q_city = (last_listing.city or "").strip()
                q_locality = (last_listing.locality or "").strip()
        except Exception:
            pass

    qry = DriverProfile.query.filter_by(is_active=True)

    if q_state:
        qry = qry.filter(DriverProfile.state.ilike(q_state))
    if q_city:
        qry = qry.filter(DriverProfile.city.ilike(q_city))
    if q_locality:
        qry = qry.filter(DriverProfile.locality.ilike(q_locality))

    rows = qry.limit(200).all()

    out = []
    for p in rows:
        usr = User.query.get(p.user_id)
        out.append({
            "user_id": int(p.user_id),
            "name": (usr.name if usr else "") or "",
            "email": (usr.email if usr else "") or "",
            **p.to_dict(),
        })

    return jsonify(out), 200


@driver_profile_bp.get("/driver/active")
def driver_active_job():
    u = _current_user()
    if not u:
        return jsonify({"ok": True, "job": None}), 200

    # latest active job for this driver
    o = (
        Order.query.filter(Order.driver_id == u.id, Order.status.in_(["driver_assigned", "picked_up"]))
        .order_by(Order.updated_at.desc())
        .first()
    )
    if not o:
        return jsonify({"ok": True, "job": None}), 200

    return jsonify({"ok": True, "job": o.to_dict()}), 200


@driver_profile_bp.post("/admin/drivers/<int:user_id>/suspend")
def admin_suspend_driver(user_id: int):
    u = _current_user()
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    active = payload.get("is_active")
    if active is None:
        active = False
    if isinstance(active, bool):
        is_active = active
    else:
        is_active = str(active).strip().lower() in ("1", "true", "yes", "y", "on")

    dp = DriverProfile.query.filter_by(user_id=int(user_id)).first()
    if not dp:
        dp = DriverProfile(user_id=int(user_id))
    dp.is_active = bool(is_active)
    dp.updated_at = datetime.utcnow()

    try:
        db.session.add(dp)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500

    if not dp.is_active:
        try:
            acct = MoneyBoxAccount.query.filter_by(user_id=int(user_id)).first()
            if acct:
                liquidate_to_wallet(acct, reason="driver_suspended", reference=f"driver_suspended:{int(user_id)}")
        except Exception:
            pass

    return jsonify({"ok": True, "profile": dp.to_dict()}), 200
