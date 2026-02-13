import os
import json
import hashlib
import time
import uuid
from datetime import datetime, date
from math import radians, sin, cos, sqrt, atan2

from flask import Blueprint, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename
from sqlalchemy import text

from app.extensions import db
from app.models.shortlet import Shortlet, ShortletBooking
from app.utils.commission import compute_commission, RATES
from app.utils.receipts import create_receipt
from app.utils.notify import queue_in_app, queue_sms, queue_whatsapp, mark_sent
from app.utils.wallets import post_txn
from app.models import User, PaymentIntent, ShortletMedia
from app.utils.jwt_utils import decode_token
from app.utils.listing_caps import enforce_listing_cap
from app.utils.autopilot import get_settings
from app.utils.feature_flags import is_enabled
from app.services.payment_intent_service import transition_intent, PaymentIntentStatus
from app.services.image_dedupe_service import ensure_image_unique, DuplicateImageError
from app.integrations.payments.factory import build_payments_provider
from app.integrations.payments.mock_provider import MockPaymentsProvider
from app.integrations.common import IntegrationDisabledError, IntegrationMisconfiguredError
from app.services.discovery_service import (
    ranking_for_shortlet,
    set_shortlet_favorite,
    record_shortlet_view,
    host_shortlet_metrics,
)
from app.utils.observability import get_request_id

shortlets_bp = Blueprint("shortlets_bp", __name__, url_prefix="/api")

# Upload folder (shared): backend/uploads
BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UPLOAD_DIR = os.path.join(BACKEND_ROOT, "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

_SHORTLETS_INIT_DONE = False


@shortlets_bp.before_app_request
def _ensure_tables_once():
    global _SHORTLETS_INIT_DONE
    if _SHORTLETS_INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _SHORTLETS_INIT_DONE = True


def _base_url():
    return request.host_url.rstrip("/")


def _platform_user_id() -> int:
    raw = (os.getenv("PLATFORM_USER_ID") or "").strip()
    if raw.isdigit():
        return int(raw)
    try:
        admin = User.query.filter_by(role="admin").order_by(User.id.asc()).first()
        if admin:
            return int(admin.id)
    except Exception:
        pass
    return 1


def _payments_mode(settings) -> str:
    mode = (getattr(settings, "payments_mode", None) or "").strip().lower()
    if mode in ("paystack_auto", "manual_company_account", "mock"):
        return mode
    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    return "mock" if provider == "mock" else "paystack_auto"


def _paystack_available(settings) -> bool:
    if not is_enabled("payments.paystack_enabled", default=bool(getattr(settings, "paystack_enabled", False)), settings=settings):
        return False
    mode = _payments_mode(settings)
    if mode == "mock":
        return True
    provider = (getattr(settings, "payments_provider", "mock") or "mock").strip().lower()
    enabled = bool(getattr(settings, "paystack_enabled", False))
    return mode == "paystack_auto" and provider != "mock" and enabled


def _manual_instructions(settings) -> dict:
    return {
        "bank_name": (getattr(settings, "manual_payment_bank_name", "") or "").strip() or (os.getenv("FLIPTRYBE_BANK_NAME") or "").strip(),
        "account_number": (getattr(settings, "manual_payment_account_number", "") or "").strip() or (os.getenv("FLIPTRYBE_BANK_ACCOUNT_NUMBER") or "").strip(),
        "account_name": (getattr(settings, "manual_payment_account_name", "") or "").strip() or (os.getenv("FLIPTRYBE_BANK_ACCOUNT_NAME") or "").strip(),
        "note": (getattr(settings, "manual_payment_note", "") or "").strip(),
        "sla_minutes": int(getattr(settings, "manual_payment_sla_minutes", 360) or 360),
    }


def _to_minor(value) -> int:
    try:
        return int(round(float(value or 0.0) * 100))
    except Exception:
        return 0


def _from_minor(value) -> float:
    try:
        return float(int(value or 0) / 100.0)
    except Exception:
        return 0.0


def _cloudinary_enabled() -> bool:
    settings = get_settings()
    if not is_enabled("media.cloudinary_enabled", default=False, settings=settings):
        return False
    return bool((os.getenv("CLOUDINARY_CLOUD_NAME") or "").strip()) and bool((os.getenv("CLOUDINARY_API_KEY") or "").strip()) and bool((os.getenv("CLOUDINARY_API_SECRET") or "").strip())


def _cloudinary_folder() -> str:
    return (os.getenv("CLOUDINARY_UPLOAD_FOLDER") or "fliptrybe/shortlets").strip()


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return r * c


def _normalize_ranking_reason(value) -> list[str]:
    if isinstance(value, list):
        return [str(x) for x in value if str(x).strip()]
    if isinstance(value, tuple):
        return [str(x) for x in list(value) if str(x).strip()]
    if value:
        return [str(value)]
    return []


def _shortlet_item_from_raw(raw: dict | None, *, ranking_score: int = 0, ranking_reason=None) -> dict:
    row = dict(raw or {})
    image = str(row.get("image") or row.get("image_path") or "").strip()
    reasons = _normalize_ranking_reason(ranking_reason if ranking_reason is not None else row.get("ranking_reason"))
    if not reasons:
        reasons = ["BASELINE"]
    created_at = row.get("created_at")
    if created_at is not None:
        created_at = str(created_at)
    return {
        "id": int(row.get("id") or 0),
        "owner_id": int(row.get("owner_id") or 0) if row.get("owner_id") is not None else None,
        "title": str(row.get("title") or ""),
        "description": str(row.get("description") or ""),
        "state": str(row.get("state") or ""),
        "city": str(row.get("city") or ""),
        "locality": str(row.get("locality") or ""),
        "lga": str(row.get("lga") or ""),
        "nightly_price": float(row.get("nightly_price") or row.get("final_price") or 0.0),
        "base_price": float(row.get("base_price") or row.get("nightly_price") or 0.0),
        "platform_fee": float(row.get("platform_fee") or 0.0),
        "final_price": float(row.get("final_price") or row.get("nightly_price") or 0.0),
        "image": image,
        "image_path": str(row.get("image_path") or ""),
        "views_count": int(row.get("views_count") or 0),
        "favorites_count": int(row.get("favorites_count") or 0),
        "heat_level": str(row.get("heat_level") or "normal"),
        "heat_score": int(row.get("heat_score") or 0),
        "created_at": created_at,
        "ranking_score": int(ranking_score if ranking_score is not None else row.get("ranking_score") or 0),
        "ranking_reason": reasons,
    }


@shortlets_bp.get("/shortlet_uploads/<path:filename>")
def get_shortlet_upload(filename):
    return send_from_directory(UPLOAD_DIR, filename)


@shortlets_bp.get("/shortlets")
def list_shortlets():
    # location filters
    state = (request.args.get("state") or "").strip()
    city = (request.args.get("city") or "").strip()
    locality = (request.args.get("locality") or "").strip()
    lga = (request.args.get("lga") or "").strip()

    # geo filters
    raw_lat = (request.args.get("lat") or "").strip()
    raw_lng = (request.args.get("lng") or "").strip()
    raw_r = (request.args.get("radius_km") or "10").strip()

    lat = None
    lng = None
    radius_km = 10.0

    try:
        lat = float(raw_lat) if raw_lat else None
    except Exception:
        lat = None
    try:
        lng = float(raw_lng) if raw_lng else None
    except Exception:
        lng = None
    try:
        radius_km = float(raw_r) if raw_r else 10.0
    except Exception:
        radius_km = 10.0

    raw_limit = (request.args.get("limit") or "").strip()
    limit = 50
    try:
        limit = int(raw_limit) if raw_limit else 50
    except Exception:
        limit = 50
    if limit <= 0:
        limit = 50
    if limit > 200:
        limit = 200

    q = Shortlet.query
    if state:
        q = q.filter(Shortlet.state.ilike(state))
    if city:
        q = q.filter(Shortlet.city.ilike(city))
    if locality:
        q = q.filter(Shortlet.locality.ilike(locality))
    if lga:
        q = q.filter(Shortlet.lga.ilike(lga))

    items = q.order_by(Shortlet.created_at.desc()).limit(limit).all()

    # radius filter in python (sqlite)
    if lat is not None and lng is not None:
        filtered = []
        for it in items:
            if it.latitude is None or it.longitude is None:
                continue
            try:
                d = _haversine_km(lat, lng, float(it.latitude), float(it.longitude))
            except Exception:
                continue
            if d <= max(radius_km, 0.1):
                filtered.append(it)
        items = filtered

    base = _base_url()
    payload = []
    for row in items:
        item = row.to_dict(base_url=base)
        score, reasons = ranking_for_shortlet(row, preferred_city=city, preferred_state=state)
        item["ranking_score"] = int(score)
        item["ranking_reason"] = reasons
        media_rows = (
            ShortletMedia.query.filter_by(shortlet_id=int(row.id))
            .order_by(ShortletMedia.position.asc(), ShortletMedia.id.asc())
            .limit(20)
            .all()
        )
        item["media"] = [
            {
                "id": int(m.id),
                "media_type": m.media_type or "image",
                "url": m.url or "",
                "thumbnail_url": m.thumbnail_url or "",
                "duration_seconds": int(m.duration_seconds or 0),
                "position": int(m.position or 0),
            }
            for m in media_rows
        ]
        payload.append(item)
    payload.sort(key=lambda row: (int(row.get("ranking_score", 0)), row.get("created_at") or ""), reverse=True)
    return jsonify(payload), 200


@shortlets_bp.get("/public/shortlets/recommended")
def recommended_shortlets():
    city = (request.args.get("city") or "").strip()
    state = (request.args.get("state") or "").strip()
    try:
        limit = max(1, min(int(request.args.get("limit") or 20), 60))
    except Exception:
        limit = 20
    try:
        rows = Shortlet.query.order_by(Shortlet.created_at.desc()).limit(500).all()
        base = _base_url()
        items = []
        for row in rows:
            score, reasons = ranking_for_shortlet(row, preferred_city=city, preferred_state=state)
            payload = _shortlet_item_from_raw(
                row.to_dict(base_url=base),
                ranking_score=int(score),
                ranking_reason=reasons,
            )
            items.append(payload)
        items.sort(key=lambda row: (int(row.get("ranking_score", 0)), row.get("created_at") or ""), reverse=True)
        return jsonify({"ok": True, "city": city, "state": state, "items": items[:limit], "limit": limit}), 200
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify({"ok": True, "city": city, "state": state, "items": [], "limit": limit}), 200


@shortlets_bp.get("/shortlets/<int:shortlet_id>")
def get_shortlet(shortlet_id: int):
    item = Shortlet.query.get(shortlet_id)
    if not item:
        return jsonify({"message": "Not found"}), 404
    payload = item.to_dict(base_url=_base_url())
    media_rows = (
        ShortletMedia.query.filter_by(shortlet_id=int(item.id))
        .order_by(ShortletMedia.position.asc(), ShortletMedia.id.asc())
        .limit(40)
        .all()
    )
    payload["media"] = [
        {
            "id": int(m.id),
            "media_type": m.media_type or "image",
            "url": m.url or "",
            "thumbnail_url": m.thumbnail_url or "",
            "duration_seconds": int(m.duration_seconds or 0),
            "position": int(m.position or 0),
        }
        for m in media_rows
    ]
    return jsonify({"ok": True, "shortlet": payload}), 200


@shortlets_bp.post("/shortlets/<int:shortlet_id>/favorite")
def favorite_shortlet(shortlet_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        payload = set_shortlet_favorite(shortlet_id=int(shortlet_id), user_id=int(u.id), is_favorite=True)
        if not payload.get("ok"):
            return jsonify(payload), 404
        return jsonify(payload), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "FAVORITE_FAILED", "message": str(exc)}), 500


@shortlets_bp.delete("/shortlets/<int:shortlet_id>/favorite")
def unfavorite_shortlet(shortlet_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    try:
        payload = set_shortlet_favorite(shortlet_id=int(shortlet_id), user_id=int(u.id), is_favorite=False)
        if not payload.get("ok"):
            return jsonify(payload), 404
        return jsonify(payload), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "UNFAVORITE_FAILED", "message": str(exc)}), 500


@shortlets_bp.post("/shortlets/<int:shortlet_id>/view")
def view_shortlet(shortlet_id: int):
    u = _current_user()
    session_key = (request.headers.get("X-Session-Key") or request.args.get("session_key") or "").strip()
    try:
        payload = record_shortlet_view(
            shortlet_id=int(shortlet_id),
            user_id=int(u.id) if u else None,
            session_key=session_key,
        )
        if not payload.get("ok"):
            return jsonify(payload), 404
        return jsonify(payload), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "VIEW_RECORD_FAILED", "message": str(exc)}), 500


@shortlets_bp.get("/host/shortlets/metrics")
def host_metrics():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    role = _role(u)
    if role not in ("merchant", "admin"):
        return jsonify({"message": "Forbidden"}), 403
    host_id = int(u.id)
    if role == "admin":
        try:
            host_id = int(request.args.get("host_id") or host_id)
        except Exception:
            host_id = int(u.id)
    items = host_shortlet_metrics(int(host_id))
    return jsonify({"ok": True, "host_id": int(host_id), "items": items}), 200


@shortlets_bp.get("/media/cloudinary/config")
def cloudinary_config():
    cloud = (os.getenv("CLOUDINARY_CLOUD_NAME") or "").strip()
    folder = _cloudinary_folder()
    return jsonify({"ok": True, "cloud_name": cloud, "folder": folder, "signed_upload": True}), 200


@shortlets_bp.post("/media/cloudinary/sign")
def cloudinary_sign():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if _role(u) not in ("merchant", "admin"):
        return jsonify({"message": "Forbidden"}), 403
    if not _cloudinary_enabled():
        return jsonify({"ok": False, "error": "INTEGRATION_MISCONFIGURED", "message": "Cloudinary keys missing"}), 500
    payload = request.get_json(silent=True) or {}
    timestamp = int(payload.get("timestamp") or int(time.time()))
    folder = str(payload.get("folder") or _cloudinary_folder()).strip()
    public_id = str(payload.get("public_id") or f"shortlet_{int(u.id)}_{timestamp}").strip()
    eager = str(payload.get("eager") or "").strip()
    sign_parts = [f"folder={folder}", f"public_id={public_id}", f"timestamp={timestamp}"]
    if eager:
        sign_parts.append(f"eager={eager}")
    sign_str = "&".join(sign_parts)
    secret = (os.getenv("CLOUDINARY_API_SECRET") or "").strip()
    signature = hashlib.sha1(f"{sign_str}{secret}".encode("utf-8")).hexdigest()
    return jsonify(
        {
            "ok": True,
            "signature": signature,
            "timestamp": timestamp,
            "api_key": (os.getenv("CLOUDINARY_API_KEY") or "").strip(),
            "cloud_name": (os.getenv("CLOUDINARY_CLOUD_NAME") or "").strip(),
            "folder": folder,
            "public_id": public_id,
            "resource_type": str(payload.get("resource_type") or "auto"),
        }
    ), 200


@shortlets_bp.post("/shortlets/<int:shortlet_id>/media")
def attach_shortlet_media(shortlet_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    shortlet = db.session.get(Shortlet, int(shortlet_id))
    if not shortlet:
        return jsonify({"message": "Not found"}), 404
    if not (_role(u) == "admin" or int(shortlet.owner_id or 0) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403
    payload = request.get_json(silent=True) or {}
    media_type = str(payload.get("media_type") or "image").strip().lower()
    if media_type not in ("image", "video"):
        return jsonify({"ok": False, "message": "media_type must be image|video"}), 400
    url = str(payload.get("url") or "").strip()
    if not url:
        return jsonify({"ok": False, "message": "url required"}), 400
    duration_seconds = int(payload.get("duration_seconds") or 0)
    if media_type == "video" and duration_seconds > 30:
        return jsonify({"ok": False, "message": "video duration must be <= 30 seconds"}), 400
    if media_type == "image":
        try:
            ensure_image_unique(
                image_url=url,
                source="shortlet_media",
                uploader_user_id=int(u.id),
                shortlet_id=int(shortlet_id),
                upload_dir=UPLOAD_DIR,
            )
        except DuplicateImageError as dup:
            payload = dup.to_payload()
            payload["trace_id"] = get_request_id()
            return jsonify(payload), 409
        except Exception:
            return jsonify(
                {
                    "ok": False,
                    "code": "IMAGE_FINGERPRINT_FAILED",
                    "message": "Could not validate image uniqueness.",
                    "trace_id": get_request_id(),
                }
            ), 400
    item = ShortletMedia(
        shortlet_id=int(shortlet_id),
        media_type=media_type,
        url=url[:1024],
        thumbnail_url=str(payload.get("thumbnail_url") or "").strip()[:1024] or None,
        duration_seconds=max(0, duration_seconds),
        position=int(payload.get("position") or 0),
    )
    db.session.add(item)
    db.session.commit()
    return jsonify({"ok": True, "media_id": int(item.id)}), 201


@shortlets_bp.post("/shortlets")
def create_shortlet():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    role = _role(u)
    ok, info = enforce_listing_cap(int(u.id), role, "shortlet")
    if not ok:
        return jsonify(info), 403

    title = ""
    description = ""
    image_rel = ""
    property_type = ""
    amenities = []
    house_rules = []
    verification_score = 20
    media_items = []
    uploaded_image_bytes = None
    image_source = "unknown"


    state = ""
    city = ""
    locality = ""
    lga = ""

    latitude = None
    longitude = None

    nightly_price = 0.0
    cleaning_fee = 0.0
    beds = 1
    baths = 1
    guests = 2

    available_from = None
    available_to = None

    # Multipart preferred
    if request.content_type and "multipart/form-data" in request.content_type:
        title = (request.form.get("title") or "").strip()
        description = (request.form.get("description") or "").strip()

        state = (request.form.get("state") or "").strip()
        city = (request.form.get("city") or "").strip()
        locality = (request.form.get("locality") or "").strip()
        lga = (request.form.get("lga") or "").strip()

        property_type = (request.form.get("property_type") or "").strip()
        amenities_raw = (request.form.get("amenities") or "").strip()
        rules_raw = (request.form.get("house_rules") or "").strip()
        if amenities_raw:
            try:
                import json
                amenities = json.loads(amenities_raw) if amenities_raw.strip().startswith("[") else [x.strip() for x in amenities_raw.split(",") if x.strip()]
            except Exception:
                amenities = []
        if rules_raw:
            try:
                import json
                house_rules = json.loads(rules_raw) if rules_raw.strip().startswith("[") else [x.strip() for x in rules_raw.split(",") if x.strip()]
            except Exception:
                house_rules = []

        # Simple MVP: verification score baseline
        try:
            verification_score = int((request.form.get("verification_score") or "20").strip())
        except Exception:
            verification_score = 20

        def _f(name, default=0.0):
            raw = request.form.get(name)
            try:
                return float(raw) if raw is not None and str(raw).strip() != "" else float(default)
            except Exception:
                return float(default)

        nightly_price = _f("nightly_price", 0.0)
        cleaning_fee = _f("cleaning_fee", 0.0)

        def _i(name, default=0):
            raw = request.form.get(name)
            try:
                return int(raw) if raw is not None and str(raw).strip() != "" else int(default)
            except Exception:
                return int(default)

        beds = _i("beds", 1)
        baths = _i("baths", 1)
        guests = _i("guests", 2)

        raw_lat = request.form.get("latitude")
        raw_lng = request.form.get("longitude")
        try:
            latitude = float(raw_lat) if raw_lat is not None and str(raw_lat).strip() != "" else None
        except Exception:
            latitude = None
        try:
            longitude = float(raw_lng) if raw_lng is not None and str(raw_lng).strip() != "" else None
        except Exception:
            longitude = None

        def _d(name):
            raw = (request.form.get(name) or "").strip()
            if not raw:
                return None
            try:
                return date.fromisoformat(raw)
            except Exception:
                return None

        available_from = _d("available_from")
        available_to = _d("available_to")

        file = request.files.get("image")
        if file and file.filename:
            original = secure_filename(os.path.basename(file.filename))
            ts = int(datetime.utcnow().timestamp())
            safe_name = f"{ts}_{original}" if original else f"{ts}_shortlet.jpg"
            save_path = os.path.join(UPLOAD_DIR, safe_name)
            uploaded_image_bytes = file.read()
            file.stream.seek(0)
            file.save(save_path)
            image_rel = f"/api/shortlet_uploads/{safe_name}"
            image_source = "upload"
    else:
        payload = request.get_json(silent=True) or {}
        title = (payload.get("title") or "").strip()
        description = (payload.get("description") or "").strip()

        state = (payload.get("state") or "").strip()
        city = (payload.get("city") or "").strip()
        locality = (payload.get("locality") or "").strip()
        lga = (payload.get("lga") or "").strip()

        property_type = (payload.get("property_type") or "").strip()
        amenities = payload.get("amenities") if isinstance(payload.get("amenities"), list) else []
        house_rules = payload.get("house_rules") if isinstance(payload.get("house_rules"), list) else []
        try:
            verification_score = int(payload.get("verification_score") or 20)
        except Exception:
            verification_score = 20

        try:
            nightly_price = float(payload.get("nightly_price") or 0.0)
        except Exception:
            nightly_price = 0.0
        try:
            cleaning_fee = float(payload.get("cleaning_fee") or 0.0)
        except Exception:
            cleaning_fee = 0.0

        try:
            beds = int(payload.get("beds") or 1)
        except Exception:
            beds = 1
        try:
            baths = int(payload.get("baths") or 1)
        except Exception:
            baths = 1
        try:
            guests = int(payload.get("guests") or 2)
        except Exception:
            guests = 2

        raw_lat = payload.get("latitude")
        raw_lng = payload.get("longitude")
        try:
            latitude = float(raw_lat) if raw_lat is not None and str(raw_lat).strip() != "" else None
        except Exception:
            latitude = None
        try:
            longitude = float(raw_lng) if raw_lng is not None and str(raw_lng).strip() != "" else None
        except Exception:
            longitude = None

        def _d_any(v):
            if v is None:
                return None
            s = str(v).strip()
            if not s:
                return None
            try:
                return date.fromisoformat(s)
            except Exception:
                return None

        available_from = _d_any(payload.get("available_from"))
        available_to = _d_any(payload.get("available_to"))

        image_rel = (payload.get("image_path") or payload.get("image") or "").strip()
        if image_rel:
            image_source = "url"
        media_payload = payload.get("media")
        if isinstance(media_payload, list):
            media_items = media_payload

    if not title:
        return jsonify({"message": "title is required"}), 400

    base_price = float(nightly_price or 0.0)
    if base_price < 0:
        base_price = 0.0
    platform_fee = round(base_price * 0.05, 2)
    final_price = round(base_price + platform_fee, 2)

    s = Shortlet(
        owner_id=int(u.id),
        title=title,
        description=description,
        state=state,
        city=city,
        locality=locality,
        lga=lga,
        latitude=latitude,
        longitude=longitude,
        nightly_price=final_price,
        base_price=base_price,
        platform_fee=platform_fee,
        final_price=final_price,
        cleaning_fee=cleaning_fee,
        beds=beds,
        baths=baths,
        guests=guests,
        available_from=available_from,
        available_to=available_to,
        image_path=image_rel,
        property_type=property_type,
        amenities=__import__('json').dumps(amenities or []),
        house_rules=__import__('json').dumps(house_rules or []),
        verification_score=verification_score,
    )

    try:
        db.session.add(s)
        db.session.flush()
        if image_rel:
            ensure_image_unique(
                image_url=image_rel,
                image_bytes=uploaded_image_bytes,
                source=image_source,
                uploader_user_id=int(u.id),
                shortlet_id=int(s.id),
                allow_same_entity=True,
                upload_dir=UPLOAD_DIR,
            )
        if media_items:
            for idx, raw in enumerate(media_items):
                if not isinstance(raw, dict):
                    continue
                media_type = str(raw.get("media_type") or "image").strip().lower()
                if media_type not in ("image", "video"):
                    continue
                duration = int(raw.get("duration_seconds") or 0)
                if media_type == "video" and duration > 30:
                    continue
                media_url = str(raw.get("url") or "").strip()
                if not media_url:
                    continue
                if media_type == "image":
                    ensure_image_unique(
                        image_url=media_url,
                        source="shortlet_media",
                        uploader_user_id=int(u.id),
                        shortlet_id=int(s.id),
                        upload_dir=UPLOAD_DIR,
                    )
                db.session.add(
                    ShortletMedia(
                        shortlet_id=int(s.id),
                        media_type=media_type,
                        url=media_url[:1024],
                        thumbnail_url=str(raw.get("thumbnail_url") or "").strip()[:1024] or None,
                        duration_seconds=max(0, duration),
                        position=int(raw.get("position") or idx),
                    )
                )
        db.session.commit()
        return jsonify({"ok": True, "shortlet": s.to_dict(base_url=_base_url())}), 201
    except DuplicateImageError as dup:
        db.session.rollback()
        payload = dup.to_payload()
        payload["trace_id"] = get_request_id()
        return jsonify(payload), 409
    except ValueError:
        db.session.rollback()
        return jsonify(
            {
                "ok": False,
                "code": "IMAGE_FINGERPRINT_FAILED",
                "message": "Could not validate image uniqueness.",
                "trace_id": get_request_id(),
            }
        ), 400
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to create shortlet", "error": str(e)}), 500



@shortlets_bp.get("/shortlets/popular")
def popular_shortlets():
    """Popular shortlets by booking count (investor demo)."""
    try:
        rows = db.session.execute(text("""
            SELECT s.id, s.title, s.state, s.city, COUNT(b.id) AS c
            FROM shortlets s
            LEFT JOIN shortlet_bookings b ON b.shortlet_id = s.id
            GROUP BY s.id, s.title, s.state, s.city
            ORDER BY c DESC, s.created_at DESC
            LIMIT 20
        """)).fetchall()
        items = []
        base = _base_url()
        for r in rows:
            sid = int(r[0])
            s = Shortlet.query.get(sid)
            if not s:
                continue
            d = s.to_dict(base_url=base)
            d["booking_count"] = int(r[4] or 0)
            items.append(d)
        return jsonify({"ok": True, "items": items}), 200
    except Exception:
        return jsonify({"ok": True, "items": []}), 200


@shortlets_bp.post("/shortlets/<int:shortlet_id>/book")
def book_shortlet(shortlet_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    check_in_raw = (payload.get("check_in") or "").strip()
    check_out_raw = (payload.get("check_out") or "").strip()

    try:
        check_in = date.fromisoformat(check_in_raw)
        check_out = date.fromisoformat(check_out_raw)
    except Exception:
        return jsonify({"message": "Invalid check_in/check_out (use YYYY-MM-DD)"}), 400

    if check_out <= check_in:
        return jsonify({"message": "check_out must be after check_in"}), 400

    shortlet = Shortlet.query.get(shortlet_id)
    if not shortlet:
        return jsonify({"message": "Not found"}), 404

    nights = (check_out - check_in).days

    # enforce min/max nights
    try:
        mn = int(shortlet.min_nights or 1)
    except Exception:
        mn = 1
    try:
        mx = int(shortlet.max_nights or 30)
    except Exception:
        mx = 30
    if nights < max(mn, 1):
        return jsonify({"message": f"Minimum stay is {max(mn,1)} nights"}), 400
    if nights > max(mx, 1):
        return jsonify({"message": f"Maximum stay is {max(mx,1)} nights"}), 400

    base_price = float(getattr(shortlet, "base_price", 0.0) or 0.0)
    if base_price <= 0.0:
        base_price = float(shortlet.nightly_price or 0.0)
    subtotal = float(base_price) * float(nights) + float(shortlet.cleaning_fee or 0.0)
    platform_fee = compute_commission(subtotal, RATES.get("shortlet_booking", 0.05))
    total = float(subtotal) + float(platform_fee)
    total_minor = _to_minor(total)
    payment_method = str(payload.get("payment_method") or "wallet").strip().lower()
    if payment_method == "paystack":
        payment_method = "paystack_card"
    if payment_method not in ("wallet", "paystack_card", "paystack_transfer", "bank_transfer_manual"):
        return jsonify(
            {
                "ok": False,
                "message": "payment_method must be wallet|paystack_card|paystack_transfer|bank_transfer_manual",
            }
        ), 400

    rec = create_receipt(
        user_id=int(u.id),
        kind="shortlet_booking",
        reference=f"shortlet:{shortlet_id}:{datetime.utcnow().isoformat()}",
        amount=subtotal,
        fee=platform_fee,
        total=total,
        description="Shortlet booking receipt (demo)",
        meta={"shortlet_id": shortlet_id, "nights": nights},
    )


    b = ShortletBooking(
        shortlet_id=shortlet_id,
        user_id=int(u.id),
        guest_name=(payload.get("guest_name") or "").strip(),
        guest_phone=(payload.get("guest_phone") or "").strip(),
        check_in=check_in,
        check_out=check_out,
        nights=nights,
        total_amount=total,
        amount_minor=int(total_minor),
        payment_method=payment_method,
        payment_status="pending",
        status="pending",
    )

    try:
        db.session.add(b)
        db.session.commit()
        if payment_method == "wallet":
            b.payment_status = "paid"
            b.status = "confirmed"
            db.session.add(b)
            db.session.commit()
            try:
                post_txn(
                    user_id=int(u.id),
                    direction="debit",
                    amount=float(total),
                    kind="shortlet_booking",
                    reference=f"shortlet:booking:{int(b.id)}",
                    note="Shortlet booking payment",
                )
                if platform_fee > 0:
                    post_txn(
                        user_id=_platform_user_id(),
                        direction="credit",
                        amount=float(platform_fee),
                        kind="platform_fee",
                        reference=f"shortlet:{int(shortlet_id)}:{int(b.id)}",
                        note="Shortlet platform fee",
                    )
            except Exception:
                pass
            return jsonify({"ok": True, "mode": "wallet", "payment_method": "wallet", "booking": b.to_dict(), "quote": {"nights": nights, "subtotal": subtotal, "platform_fee": platform_fee, "total": total}}), 201

        settings = get_settings()
        payments_mode = _payments_mode(settings)
        reference = f"FT-SHORTLET-{int(b.id)}-{int(datetime.utcnow().timestamp())}"
        if payment_method == "bank_transfer_manual" and _paystack_available(settings):
            return jsonify(
                {
                    "ok": False,
                    "error": "PAYMENT_METHOD_UNAVAILABLE",
                    "message": "Manual transfer is unavailable while Paystack auto mode is active.",
                }
            ), 409
        if payment_method == "bank_transfer_manual":
            pi = PaymentIntent(
                user_id=int(u.id),
                provider="manual_company_account",
                reference=reference,
                purpose="order",
                amount=float(total),
                amount_minor=int(total_minor),
                status=PaymentIntentStatus.INITIALIZED,
                updated_at=datetime.utcnow(),
                meta=json.dumps(
                    {
                        "purpose": "shortlet_booking",
                        "booking_id": int(b.id),
                        "shortlet_id": int(shortlet_id),
                        "payment_method": "bank_transfer_manual",
                        "order_ids": [],
                        "order_id": None,
                    }
                ),
            )
            db.session.add(pi)
            db.session.commit()
            transition_intent(
                pi,
                PaymentIntentStatus.MANUAL_PENDING,
                actor={"type": "user", "id": int(u.id)},
                idempotency_key=f"init:{pi.reference}:manual_pending",
                reason="manual_initialize_shortlet",
                metadata={"booking_id": int(b.id)},
            )
            b.payment_intent_id = int(pi.id)
            b.payment_status = "manual_pending"
            db.session.add(b)
            db.session.commit()
            return jsonify(
                {
                    "ok": True,
                    "mode": "bank_transfer_manual",
                    "payment_method": "bank_transfer_manual",
                    "booking": b.to_dict(),
                    "payment_intent_id": int(pi.id),
                    "reference": pi.reference,
                    "manual_instructions": _manual_instructions(settings),
                    "quote": {"nights": nights, "subtotal": subtotal, "platform_fee": platform_fee, "total": total},
                }
            ), 201

        if payments_mode == "manual_company_account":
            return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": "Paystack checkout disabled while manual mode is active"}), 503
        if not _paystack_available(settings):
            return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": "Paystack checkout is unavailable in current mode"}), 503
        provider = MockPaymentsProvider() if payments_mode == "mock" else None
        if provider is None:
            try:
                provider = build_payments_provider(settings)
            except IntegrationDisabledError as exc:
                return jsonify({"ok": False, "error": "INTEGRATION_DISABLED", "message": str(exc)}), 503
            except IntegrationMisconfiguredError as exc:
                return jsonify({"ok": False, "error": "INTEGRATION_MISCONFIGURED", "message": str(exc)}), 500

        pi = PaymentIntent(
            user_id=int(u.id),
            provider=provider.name,
            reference=reference,
            purpose="order",
            amount=float(total),
            amount_minor=int(total_minor),
            status=PaymentIntentStatus.INITIALIZED,
            updated_at=datetime.utcnow(),
            meta=json.dumps(
                {
                    "purpose": "shortlet_booking",
                    "booking_id": int(b.id),
                    "shortlet_id": int(shortlet_id),
                    "payment_method": payment_method,
                    "order_ids": [],
                    "order_id": None,
                }
            ),
        )
        db.session.add(pi)
        db.session.commit()
        transition_intent(
            pi,
            PaymentIntentStatus.INITIALIZED,
            actor={"type": "user", "id": int(u.id)},
            idempotency_key=f"init:{pi.reference}:initialized",
            reason="paystack_initialize_shortlet",
            metadata={"booking_id": int(b.id)},
        )
        init_result = provider.initialize(
            order_id=None,
            amount=float(total),
            email=(u.email or ""),
            reference=pi.reference,
            metadata={
                "booking_id": int(b.id),
                "shortlet_id": int(shortlet_id),
                "payment_method": payment_method,
            },
        )
        if init_result.reference and init_result.reference != pi.reference:
            pi.reference = init_result.reference
            db.session.add(pi)
        b.payment_intent_id = int(pi.id)
        b.payment_status = "awaiting_payment"
        db.session.add(b)
        db.session.commit()
        return jsonify(
            {
                "ok": True,
                "mode": "paystack",
                "payment_method": payment_method,
                "booking": b.to_dict(),
                "payment_intent_id": int(pi.id),
                "reference": pi.reference,
                "authorization_url": init_result.authorization_url,
                "quote": {"nights": nights, "subtotal": subtotal, "platform_fee": platform_fee, "total": total},
            }
        ), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Booking failed", "error": str(e)}), 500



@shortlets_bp.post("/shortlet_bookings/<int:booking_id>/confirm")
def confirm_booking(booking_id: int):
    b = ShortletBooking.query.get(booking_id)
    if not b:
        return jsonify({"message": "Not found"}), 404
    b.status = "confirmed"
    try:
        db.session.commit()
        return jsonify({"ok": True, "booking": b.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Confirm failed", "error": str(e)}), 500


@shortlets_bp.post("/shortlets/<int:shortlet_id>/review")
def review_shortlet(shortlet_id: int):
    payload = request.get_json(silent=True) or {}
    rating = payload.get("rating")
    try:
        r = float(rating)
    except Exception:
        r = 0.0
    r = max(0.0, min(5.0, r))

    s = Shortlet.query.get(shortlet_id)
    if not s:
        return jsonify({"message": "Not found"}), 404

    # Simple aggregate update
    try:
        current_count = int(s.reviews_count or 0)
        current_rating = float(s.rating or 0.0)
        new_count = current_count + 1
        new_rating = ((current_rating * current_count) + r) / max(new_count, 1)
        s.reviews_count = new_count
        s.rating = float(new_rating)
        db.session.commit()
        return jsonify({"ok": True, "shortlet": s.to_dict(base_url=_base_url())}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Review failed", "error": str(e)}), 500


@shortlets_bp.get("/shortlets_dashboard/summary")
def shortlets_dashboard_summary():
    """Investor-friendly summary counters."""
    try:
        total_shortlets = db.session.query(Shortlet).count()
        total_bookings = db.session.query(ShortletBooking).count()
        confirmed = db.session.query(ShortletBooking).filter(ShortletBooking.status == "confirmed").count()
        pending = db.session.query(ShortletBooking).filter(ShortletBooking.status == "pending").count()
        return jsonify({
            "ok": True,
            "total_shortlets": int(total_shortlets),
            "total_bookings": int(total_bookings),
            "confirmed_bookings": int(confirmed),
            "pending_bookings": int(pending),
        }), 200
    except Exception:
        return jsonify({"ok": True, "total_shortlets": 0, "total_bookings": 0, "confirmed_bookings": 0, "pending_bookings": 0}), 200

def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user_id() -> int | None:
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
        return int(sub)
    except Exception:
        return None


def _current_user() -> User | None:
    uid = _current_user_id()
    if not uid:
        return None
    return User.query.get(int(uid))


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()
