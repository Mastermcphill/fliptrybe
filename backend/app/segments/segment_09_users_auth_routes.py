import os
import json
from datetime import datetime
from flask import Blueprint, request, jsonify
from sqlalchemy.exc import IntegrityError

from app.extensions import db
from app.models import User, RoleChangeRequest
from app.utils.jwt_utils import create_token, decode_token
from app.utils.account_flags import record_account_flag, find_duplicate_phone_users, flag_duplicate_phone

auth_bp = Blueprint("auth_bp", __name__, url_prefix="/api/auth")

def _create_user(*, name: str, email: str, phone: str | None, password: str, role: str = "buyer") -> tuple[User | None, str | None, tuple[dict, int] | None]:
    """Create user, return (user, token, error_response)."""
    role = (role or "buyer").strip().lower()
    if role == "admin":
        return None, None, ({"message": "Admin signup is not allowed"}, 403)

    if not email or not password:
        return None, None, ({"message": "Email and password are required"}, 400)

    u = User(name=(name or "").strip(), email=email.strip().lower())
    try:
        if phone:
            setattr(u, "phone", (phone or "").strip())
    except Exception:
        pass

    u.set_password(password)

    try:
        db.session.add(u)
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        try:
            existing = User.query.filter_by(email=email.strip().lower()).first()
            if existing:
                record_account_flag(int(existing.id), "DUP_EMAIL", signal=email, details={"email": email})
        except Exception:
            pass
        return None, None, ({"message": "Email already exists"}, 409)

    token = create_token(u.id)
    return u, token, None


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
        return req, None
    except Exception as e:
        db.session.rollback()
        return None, ({"message": "Failed to create role request", "error": str(e)}, 500)


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "").strip()


@auth_bp.post("/register")
def register():
    # Backwards-compatible: treat as buyer/seller signup
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    phone = (data.get("phone") or "").strip() or None
    password = data.get("password") or ""
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403

    u, token, err = _create_user(name=name, email=email, phone=phone, password=password, role="buyer")
    if err:
        body, code = err
        return jsonify(body), code
    return jsonify({"user": u.to_dict(), "token": token}), 201


@auth_bp.post("/login")
def login():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    if not email or not password:
        return jsonify({"message": "Email and password are required"}), 400

    u = User.query.filter_by(email=email).first()
    if not u or not u.check_password(password):
        return jsonify({"message": "Invalid credentials"}), 401

    token = create_token(u.id)
    return jsonify({"user": u.to_dict(), "token": token}), 200


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

    u = User.query.get(user_id)
    if not u:
        return jsonify({"message": "User not found"}), 404

    # Return user dict directly (cleanest for frontend)
    return jsonify(u.to_dict()), 200


@auth_bp.post("/set-role")
def set_role():
    """Demo helper: set current user's role to buyer/merchant/driver/admin."""
    env = (os.getenv("FLIPTRYBE_ENV", "dev") or "dev").strip().lower()
    allow_override = (os.getenv("ALLOW_DEV_ROLE_SWITCH", "") or "").strip() == "1"
    if env not in ("dev", "development", "local", "test") or not allow_override:
        return jsonify({"message": "Not found"}), 404
    token = request.headers.get("Authorization", "")
    if not token.startswith("Bearer "):
        return jsonify({"message": "Not found"}), 404
    token = token.replace("Bearer ", "", 1).strip()
    payload = decode_token(token)
    if not payload:
        return jsonify({"message": "Not found"}), 404
    sub = payload.get("sub")
    if not sub:
        return jsonify({"message": "Not found"}), 404
    try:
        uid = int(sub)
    except Exception:
        return jsonify({"message": "Not found"}), 404

    u = User.query.get(uid)
    if not u:
        return jsonify({"message": "Not found"}), 404
    try:
        if int(u.id or 0) != 1:
            return jsonify({"message": "Not found"}), 404
    except Exception:
        return jsonify({"message": "Not found"}), 404

    data = request.get_json(silent=True) or {}
    role = (data.get("role") or "").strip().lower()
    if role not in ("buyer", "merchant", "driver", "admin"):
        return jsonify({"message": "role must be buyer|merchant|driver|admin"}), 400

    u.role = role
    try:
        db.session.add(u)
        db.session.commit()
        return jsonify({"ok": True, "user": u.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500



# ---------------------------
# Role-based registration (Phase 2.8)
# ---------------------------

def _register_common(name: str, email: str, password: str, role: str, extra: dict | None = None):
    name = (name or "").strip()
    email = (email or "").strip().lower()
    password = (password or "").strip()
    role = (role or "").strip().lower()

    if role == "admin":
        return None, (jsonify({"message": "Admin signup is not allowed"}), 403)

    if not name:
        return None, (jsonify({"message": "name is required"}), 400)
    if not email or "@" not in email:
        return None, (jsonify({"message": "valid email is required"}), 400)
    if len(password) < 4:
        return None, (jsonify({"message": "password is required"}), 400)

    existing = User.query.filter_by(email=email).first()
    if existing:
        try:
            record_account_flag(int(existing.id), "DUP_EMAIL", signal=email, details={"email": email})
        except Exception:
            pass
        return None, (jsonify({"message": "User already exists"}), 400)

    u = User(name=name, email=email, role=role)
    u.set_password(password)

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
    except Exception as e:
        db.session.rollback()
        return None, (jsonify({"message": "Failed to register", "error": str(e)}), 500)

    token = create_token(str(u.id))
    return {"token": token, "user": u.to_dict()}, None


@auth_bp.post("/register/buyer")
def register_buyer():
    data = request.get_json(silent=True) or {}
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403
    payload, err = _register_common(
        name=data.get("name") or "",
        email=data.get("email") or "",
        password=data.get("password") or "",
        role="buyer",
    )
    if err:
        return err
    return jsonify(payload), 201


@auth_bp.post("/register/merchant")
def register_merchant():
    data = request.get_json(silent=True) or {}
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403
    business_name = (data.get("business_name") or "").strip()
    phone = (data.get("phone") or "").strip()
    state = (data.get("state") or "").strip()
    city = (data.get("city") or "").strip()
    category = (data.get("category") or "").strip()
    reason = (data.get("reason") or "").strip()

    if not business_name:
        return jsonify({"message": "business_name is required"}), 400
    if not phone:
        return jsonify({"message": "phone is required"}), 400
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

    existing = User.query.filter_by(email=email).first()
    if existing:
        if not existing.check_password(password):
            return jsonify({"message": "Invalid credentials"}), 401
        user = existing
    else:
        user = User(name=(data.get("owner_name") or data.get("name") or business_name), email=email, role="buyer")
        user.set_password(password)
        try:
            db.session.add(user)
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            return jsonify({"message": "Failed to register", "error": str(e)}), 500

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
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create request", "error": str(e)}), 500

    token = create_token(str(user.id))
    return jsonify({"token": token, "user": user.to_dict(), "request": req.to_dict()}), 201


@auth_bp.post("/register/driver")
def register_driver():
    data = request.get_json(silent=True) or {}
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403

    # Admin-mediated activation: we still create the base user + a pending role-change request.
    name = (data.get("name") or "").strip() or (data.get("full_name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    password = (data.get("password") or "").strip()

    phone = (data.get("phone") or "").strip()
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
    payload, err = _register_common(
        name=name,
        email=email,
        password=password,
        role="buyer",
        extra={"phone": phone, "state": state, "city": city},
    )
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
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create request", "error": str(e)}), 500

    token = create_token(str(user.id))
    return jsonify({
        "token": token,
        "user": user.to_dict(),
        "request": req.to_dict(),
        "message": "Driver signup submitted. Activation is admin-mediated.",
    }), 201


@auth_bp.post("/register/inspector")
def register_inspector():
    data = request.get_json(silent=True) or {}
    role = (data.get("role") or "").strip().lower()
    if role == "admin":
        return jsonify({"message": "Admin signup is not allowed"}), 403

    name = (data.get("name") or "").strip() or (data.get("full_name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    password = (data.get("password") or "").strip()

    phone = (data.get("phone") or "").strip()
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

    payload, err = _register_common(
        name=name,
        email=email,
        password=password,
        role="buyer",
        extra={"phone": phone, "state": state, "city": city},
    )
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
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create request", "error": str(e)}), 500

    token = create_token(str(user.id))
    return jsonify({
        "token": token,
        "user": user.to_dict(),
        "request": req.to_dict(),
        "message": "Inspector signup submitted. Activation is admin-mediated.",
    }), 201
