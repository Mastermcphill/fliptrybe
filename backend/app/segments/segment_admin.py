import uuid
import inspect
import re
from datetime import datetime, timezone
from sqlalchemy import String, Text, Integer, Float, Numeric, Boolean, DateTime, Enum, inspect as sa_inspect
from flask import Blueprint, jsonify, request, current_app
from app.extensions import db
from app.models.user import User
from app.models.listing import Listing
from app.models.shortlet import Shortlet
from app.models.merchant import MerchantProfile
from app.models.merchant_follow import MerchantFollow
from app.utils.jwt_utils import decode_token, get_bearer_token

admin_bp = Blueprint("admin_bp", __name__, url_prefix="/api/admin")

def _current_user():
    header = request.headers.get("Authorization", "")
    token = get_bearer_token(header)
    if not token and header.lower().startswith("token "):
        token = header.replace("Token ", "", 1).strip()
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    sub = payload.get("sub")
    try:
        uid = int(sub)
    except Exception:
        return None
    try:
        return db.session.get(User, uid)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        try:
            return db.session.get(User, uid)
        except Exception:
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

def _debug_detail(e, u):
    try:
        if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
            return f"{type(e).__name__}: {e}"
    except Exception:
        pass
    return None


def _debug_error_payload(e, u):
    detail = _debug_detail(e, u)
    if not detail:
        return None
    out = {
        "detail": detail,
        "exception_type": type(e).__name__,
    }
    try:
        msg = str(e) or ""
        # Helps pinpoint NOT NULL/UndefinedColumn quickly in debug responses.
        m = re.search(r'column "?([a-zA-Z0-9_]+)"?', msg)
        if m:
            out["column"] = m.group(1)
    except Exception:
        pass
    return out


@admin_bp.get("/summary")
def admin_summary():
    return jsonify({
        "ok": True,
        "stats": {
            "users": User.query.count(),
            "listings": Listing.query.count(),
            "orders": 0,
            "reports": 0,
        }
    }), 200


@admin_bp.post("/listings/<int:listing_id>/disable")
def disable_listing(listing_id: int):
    # Placeholder without soft-delete column. For demo, just confirms action.
    return jsonify({"ok": True, "listing_id": listing_id, "action": "disabled"}), 200


@admin_bp.post("/users/<int:user_id>/disable")
def disable_user(user_id: int):
    return jsonify({"ok": True, "user_id": user_id, "action": "disabled"}), 200


@admin_bp.post("/demo/seed-listing")
def seed_listing():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    target_merchant_raw = payload.get("merchant_id")
    if target_merchant_raw is None:
        target_merchant_raw = payload.get("user_id")

    target_merchant_id = None
    if target_merchant_raw is not None:
        try:
            target_merchant_id = int(target_merchant_raw)
        except Exception:
            return jsonify({"ok": False, "error": "invalid_merchant_id"}), 400

    target_merchant = None
    if target_merchant_id is not None:
        try:
            target_merchant = db.session.get(User, int(target_merchant_id))
        except Exception:
            db.session.rollback()
            target_merchant = None
        if not target_merchant:
            return jsonify({"ok": False, "error": "merchant_not_found"}), 404

    try:
        if target_merchant_id is not None:
            listing = Listing.query.filter_by(user_id=int(target_merchant_id)).order_by(Listing.id.asc()).first()
        else:
            listing = Listing.query.order_by(Listing.id.asc()).first()
    except Exception:
        db.session.rollback()
        listing = None

    if listing:
        merchant_id = getattr(listing, "user_id", None)
        if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
            return jsonify({
                "ok": True,
                "merchant_id": merchant_id,
                "listing_id": listing.id,
                "listing": listing.to_dict(),
                "listing_module": getattr(Listing, "__module__", None),
                "listing_file": inspect.getfile(Listing),
            }), 200
        return jsonify({"ok": True, "merchant_id": merchant_id, "listing_id": listing.id}), 200

    merchant = target_merchant
    if not merchant:
        try:
            merchant = User.query.filter_by(role="merchant").order_by(User.id.asc()).first()
        except Exception:
            db.session.rollback()
            merchant = None

    if not merchant:
        email = "merchant@fliptrybe.com"
        try:
            exists = User.query.filter_by(email=email).first()
        except Exception:
            db.session.rollback()
            exists = None
        if exists:
            email = f"merchant_seed_{uuid.uuid4().hex[:8]}@t.com"
        phone = f"+234801{str(uuid.uuid4().int % 10000000).zfill(7)}"
        merchant = User(
            name="Seed Merchant",
            email=email,
            phone=phone,
            role="merchant",
            is_verified=True,
            kyc_tier=1,
            is_available=True,
        )
        merchant.set_password("TempPass123!")
        try:
            db.session.add(merchant)
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            try:
                current_app.logger.exception("seed_listing_create_merchant_failed")
            except Exception:
                pass
            debug_payload = _debug_error_payload(e, u)
            if debug_payload:
                return jsonify({"ok": False, "error": "db_error", **debug_payload}), 500
            return jsonify({"ok": False, "error": "db_error"}), 500

    listing = Listing(
        user_id=int(merchant.id),
        title="Seed Listing",
        description="Auto-seeded listing for order creation smoke tests.",
        state="Lagos",
        city="Ikeja",
        locality="",
        category="declutter",
        price=10000.0,
        base_price=10000.0,
        platform_fee=300.0,
        final_price=10300.0,
        image_path="",
        image_filename="seed.jpg",
        is_active=True,
        created_at=datetime.utcnow(),
        date_posted=datetime.utcnow(),
        seed_key=uuid.uuid4().hex,
    )
    # Seed safety: fill any NOT NULL columns that are still None.
    try:
        for col in Listing.__table__.columns:
            if col.primary_key:
                continue
            if col.nullable:
                continue
            key = col.name
            try:
                val = getattr(listing, key, None)
            except Exception:
                val = None
            if val is not None:
                continue
            ctype = col.type
            try:
                if isinstance(ctype, (String, Text)):
                    setattr(listing, key, "")
                elif isinstance(ctype, (Integer, Float, Numeric)):
                    setattr(listing, key, 0)
                elif isinstance(ctype, Boolean):
                    setattr(listing, key, True)
                elif isinstance(ctype, DateTime):
                    setattr(listing, key, datetime.now(timezone.utc))
                elif isinstance(ctype, Enum) and getattr(ctype, "enums", None):
                    setattr(listing, key, ctype.enums[0])
            except Exception:
                pass
    except Exception:
        pass
    try:
        db.session.add(listing)
        db.session.commit()
        if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
            return jsonify({
                "ok": True,
                "merchant_id": int(merchant.id),
                "listing_id": int(listing.id),
                "category": getattr(listing, "category", None),
                "price": getattr(listing, "price", None),
                "listing": listing.to_dict(),
                "listing_module": getattr(Listing, "__module__", None),
                "listing_file": inspect.getfile(Listing),
            }), 201
        return jsonify({"ok": True, "merchant_id": int(merchant.id), "listing_id": int(listing.id)}), 201
    except Exception as e:
        db.session.rollback()
        try:
            current_app.logger.exception("seed_listing_create_listing_failed")
        except Exception:
            pass
        debug_payload = _debug_error_payload(e, u)
        if debug_payload:
            return jsonify({"ok": False, "error": "db_error", **debug_payload}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500


@admin_bp.post("/demo/seed-nationwide")
def seed_nationwide():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    target_merchant_raw = payload.get("merchant_id")
    if target_merchant_raw is None:
        target_merchant_raw = payload.get("user_id")

    target_merchant = None
    if target_merchant_raw is not None:
        try:
            target_merchant = db.session.get(User, int(target_merchant_raw))
        except Exception:
            db.session.rollback()
            target_merchant = None
        if not target_merchant:
            return jsonify({"ok": False, "error": "merchant_not_found"}), 404

    merchant = target_merchant
    if not merchant:
        try:
            merchant = User.query.filter_by(role="merchant").order_by(User.id.asc()).first()
        except Exception:
            db.session.rollback()
            merchant = None

    if not merchant:
        email = f"merchant_seed_{uuid.uuid4().hex[:8]}@t.com"
        phone = f"+234801{str(uuid.uuid4().int % 10000000).zfill(7)}"
        merchant = User(
            name="Nationwide Seed Merchant",
            email=email,
            phone=phone,
            role="merchant",
            is_verified=True,
            kyc_tier=1,
            is_available=True,
        )
        merchant.set_password("TempPass123!")
        try:
            db.session.add(merchant)
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            try:
                current_app.logger.exception("seed_nationwide_create_merchant_failed")
            except Exception:
                pass
            debug_payload = _debug_error_payload(e, u)
            if debug_payload:
                return jsonify({"ok": False, "error": "db_error", **debug_payload}), 500
            return jsonify({"ok": False, "error": "db_error"}), 500

    listing_targets = [
        ("Lagos", "Ikeja", ""),
        ("Abuja", "Wuse", ""),
        ("Rivers", "Port Harcourt", ""),
        ("Kano", "Nassarawa", ""),
        ("Oyo", "Ibadan", ""),
        ("Kaduna", "Kaduna North", ""),
        ("Enugu", "Enugu", ""),
        ("Delta", "Asaba", ""),
        ("Ogun", "Abeokuta", ""),
        ("Akwa Ibom", "Uyo", ""),
        ("Plateau", "Jos", ""),
        ("Edo", "Benin City", ""),
    ]
    shortlet_targets = [
        ("Lagos", "Lekki", "Chevron"),
        ("Abuja", "Gwarinpa", "Life Camp"),
        ("Rivers", "Port Harcourt", "GRA"),
        ("Kano", "Nassarawa", "Tarauni"),
        ("Oyo", "Ibadan", "Bodija"),
        ("Kaduna", "Kaduna", "Barnawa"),
        ("Enugu", "Enugu", "Independence Layout"),
        ("Delta", "Warri", "DSC"),
        ("Ogun", "Abeokuta", "Ibara"),
        ("Akwa Ibom", "Uyo", "Ewet Housing"),
    ]

    listing_created = 0
    listing_existing = 0
    shortlet_created = 0
    shortlet_existing = 0
    listing_ids = []
    shortlet_ids = []

    try:
        for idx, (state, city, locality) in enumerate(listing_targets):
            seed_key = f"nationwide_listing_{state.lower().replace(' ', '_')}"
            existing = Listing.query.filter_by(seed_key=seed_key).first()
            if existing:
                listing_existing += 1
                listing_ids.append(int(existing.id))
                continue

            base_price = float(10000 + (idx * 750))
            platform_fee = round(base_price * 0.03, 2)
            final_price = round(base_price + platform_fee, 2)
            listing = Listing(
                user_id=int(merchant.id),
                title=f"{state} Declutter Deal",
                description=f"Seeded listing for {state} marketplace coverage.",
                state=state,
                city=city,
                locality=locality,
                category="declutter",
                price=final_price,
                base_price=base_price,
                platform_fee=platform_fee,
                final_price=final_price,
                image_path="",
                image_filename="seed.jpg",
                is_active=True,
                created_at=datetime.utcnow(),
                date_posted=datetime.utcnow(),
                seed_key=seed_key,
            )

            # Defensive fill for evolving NOT NULL columns.
            for col in Listing.__table__.columns:
                if col.primary_key or col.nullable:
                    continue
                key = col.name
                val = getattr(listing, key, None)
                if val is not None:
                    continue
                ctype = col.type
                if isinstance(ctype, (String, Text)):
                    setattr(listing, key, "")
                elif isinstance(ctype, (Integer, Float, Numeric)):
                    setattr(listing, key, 0)
                elif isinstance(ctype, Boolean):
                    setattr(listing, key, True)
                elif isinstance(ctype, DateTime):
                    setattr(listing, key, datetime.now(timezone.utc))
                elif isinstance(ctype, Enum) and getattr(ctype, "enums", None):
                    setattr(listing, key, ctype.enums[0])

            db.session.add(listing)
            db.session.flush()
            listing_created += 1
            listing_ids.append(int(listing.id))

        for idx, (state, city, locality) in enumerate(shortlet_targets):
            title = f"{state} Shortlet Stay"
            existing = Shortlet.query.filter_by(owner_id=int(merchant.id), title=title).first()
            if existing:
                shortlet_existing += 1
                shortlet_ids.append(int(existing.id))
                continue

            base_price = float(35000 + (idx * 1500))
            platform_fee = round(base_price * 0.03, 2)
            final_price = round(base_price + platform_fee, 2)
            shortlet = Shortlet(
                owner_id=int(merchant.id),
                title=title,
                description=f"Seeded shortlet coverage for {state}.",
                state=state,
                city=city,
                locality=locality,
                lga="",
                nightly_price=final_price,
                base_price=base_price,
                platform_fee=platform_fee,
                final_price=final_price,
                cleaning_fee=1500.0,
                beds=1,
                baths=1,
                guests=2,
                image_path="",
                property_type="apartment",
                amenities='["wifi","power","water"]',
                house_rules='["No smoking"]',
                rating=0.0,
                reviews_count=0,
                verification_score=20,
                created_at=datetime.utcnow(),
            )
            db.session.add(shortlet)
            db.session.flush()
            shortlet_created += 1
            shortlet_ids.append(int(shortlet.id))

        db.session.commit()
    except Exception as e:
        db.session.rollback()
        try:
            current_app.logger.exception("seed_nationwide_failed")
        except Exception:
            pass
        debug_payload = _debug_error_payload(e, u)
        if debug_payload:
            return jsonify({"ok": False, "error": "db_error", **debug_payload}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500

    out = {
        "ok": True,
        "merchant_id": int(merchant.id),
        "listings_created": int(listing_created),
        "listings_existing": int(listing_existing),
        "shortlets_created": int(shortlet_created),
        "shortlets_existing": int(shortlet_existing),
        "listing_ids": listing_ids[:20],
        "shortlet_ids": shortlet_ids[:20],
    }
    if request.headers.get("X-Debug", "").strip() == "1" and _is_admin(u):
        out["states_seeded"] = [x[0] for x in listing_targets]
        out["shortlet_states_seeded"] = [x[0] for x in shortlet_targets]
    return jsonify(out), 200


@admin_bp.post("/demo/seed-leaderboards")
def seed_leaderboards():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    try:
        requested = int(payload.get("n") or request.args.get("n") or 12)
    except Exception:
        requested = 12
    if requested < 3:
        requested = 3
    if requested > 24:
        requested = 24

    states = [
        ("Lagos", "Ikeja"),
        ("Federal Capital Territory", "Gwarinpa"),
        ("Rivers", "Port Harcourt"),
        ("Kano", "Nassarawa"),
        ("Oyo", "Ibadan"),
        ("Kaduna", "Kaduna"),
        ("Enugu", "Enugu"),
        ("Delta", "Asaba"),
        ("Ogun", "Abeokuta"),
        ("Akwa Ibom", "Uyo"),
        ("Plateau", "Jos"),
        ("Edo", "Benin City"),
        ("Anambra", "Awka"),
        ("Imo", "Owerri"),
        ("Kwara", "Ilorin"),
    ]
    states = states[:requested]

    created_users = 0
    reused_users = 0
    created_profiles = 0
    reused_profiles = 0
    created_listings = 0
    reused_listings = 0
    created_follows = 0
    merchant_ids = []
    listing_schema_ok = True
    listing_schema_missing = []

    def _seed_phone(prefix_idx: int) -> str:
        return f"+234809{str(prefix_idx).zfill(7)}"

    def _unique_phone(candidate: str) -> str:
        phone = (candidate or "").strip()
        if phone and not User.query.filter_by(phone=phone).first():
            return phone
        return f"+2348{str(uuid.uuid4().int % 1000000000).zfill(9)}"

    def _safe_fill_not_null_listing(seed: Listing) -> None:
        for col in Listing.__table__.columns:
            if col.primary_key or col.nullable:
                continue
            key = col.name
            val = getattr(seed, key, None)
            if val is not None:
                continue
            ctype = col.type
            if isinstance(ctype, (String, Text)):
                setattr(seed, key, "")
            elif isinstance(ctype, (Integer, Float, Numeric)):
                setattr(seed, key, 0)
            elif isinstance(ctype, Boolean):
                setattr(seed, key, True)
            elif isinstance(ctype, DateTime):
                setattr(seed, key, datetime.now(timezone.utc))
            elif isinstance(ctype, Enum) and getattr(ctype, "enums", None):
                setattr(seed, key, ctype.enums[0])

    try:
        bind = db.session.get_bind()
        existing_cols = {c.get("name") for c in sa_inspect(bind).get_columns("listings")}
        model_cols = {c.name for c in Listing.__table__.columns}
        missing_cols = sorted([c for c in model_cols if c not in existing_cols])
        if missing_cols:
            listing_schema_ok = False
            listing_schema_missing = missing_cols
    except Exception:
        listing_schema_ok = False
        listing_schema_missing = ["schema_introspection_failed"]

    try:
        for idx, (state, city) in enumerate(states, start=1):
            slug = state.lower().replace(" ", "_")
            email = f"merchant_seed_{slug}@t.com"
            merchant = User.query.filter_by(email=email).first()
            if merchant:
                reused_users += 1
            else:
                merchant = User(
                    name=f"{state} Seed Merchant",
                    email=email,
                    phone=_unique_phone(_seed_phone(idx)),
                    role="merchant",
                    is_verified=True,
                    kyc_tier=2,
                    is_available=True,
                )
                merchant.set_password("TempPass123!")
                db.session.add(merchant)
                db.session.flush()
                created_users += 1

            merchant_ids.append(int(merchant.id))

            profile = MerchantProfile.query.filter_by(user_id=int(merchant.id)).first()
            if profile:
                reused_profiles += 1
            else:
                profile = MerchantProfile(user_id=int(merchant.id))
                created_profiles += 1
            profile.shop_name = profile.shop_name or f"{state} Market Hub"
            profile.shop_category = profile.shop_category or "General"
            profile.phone = profile.phone or merchant.phone or ""
            profile.state = state
            profile.city = city
            profile.locality = profile.locality or ""
            profile.total_orders = max(int(profile.total_orders or 0), 8 + idx)
            profile.successful_deliveries = max(int(profile.successful_deliveries or 0), 5 + idx)
            profile.cancelled_orders = int(profile.cancelled_orders or 0)
            profile.disputes = int(profile.disputes or 0)
            profile.avg_rating = max(float(profile.avg_rating or 0.0), 3.8 + (idx % 4) * 0.25)
            profile.rating_count = max(int(profile.rating_count or 0), 4 + idx)
            profile.total_sales = max(float(profile.total_sales or 0.0), float((8 + idx) * 15000))
            profile.is_featured = True if idx <= 5 else bool(profile.is_featured)
            profile.is_suspended = False
            profile.updated_at = datetime.utcnow()
            db.session.add(profile)

            if listing_schema_ok:
                seed_key = f"leaderboard_seed_listing_{slug}"
                listing = Listing.query.filter_by(seed_key=seed_key).first()
                if listing:
                    reused_listings += 1
                else:
                    base_price = float(11000 + idx * 900)
                    platform_fee = round(base_price * 0.03, 2)
                    final_price = round(base_price + platform_fee, 2)
                    listing = Listing(
                        user_id=int(merchant.id),
                        title=f"{state} Seed Product",
                        description=f"Leaderboard seed listing for {state}.",
                        state=state,
                        city=city,
                        locality="",
                        category="declutter",
                        price=final_price,
                        base_price=base_price,
                        platform_fee=platform_fee,
                        final_price=final_price,
                        image_path="",
                        image_filename="seed.jpg",
                        is_active=True,
                        created_at=datetime.utcnow(),
                        date_posted=datetime.utcnow(),
                        seed_key=seed_key,
                    )
                    _safe_fill_not_null_listing(listing)
                    db.session.add(listing)
                    created_listings += 1

        for follower_idx in range(1, 6):
            buyer_email = f"buyer_seed_{follower_idx}@t.com"
            buyer = User.query.filter_by(email=buyer_email).first()
            if not buyer:
                buyer = User(
                    name=f"Seed Buyer {follower_idx}",
                    email=buyer_email,
                    phone=_unique_phone(f"+234818{str(follower_idx).zfill(7)}"),
                    role="buyer",
                    is_verified=True,
                    kyc_tier=1,
                    is_available=True,
                )
                buyer.set_password("TempPass123!")
                db.session.add(buyer)
                db.session.flush()

            for merchant_id in merchant_ids[: min(5 + follower_idx, len(merchant_ids))]:
                exists = MerchantFollow.query.filter_by(follower_id=int(buyer.id), merchant_id=int(merchant_id)).first()
                if exists:
                    continue
                db.session.add(MerchantFollow(follower_id=int(buyer.id), merchant_id=int(merchant_id)))
                created_follows += 1

        db.session.commit()
    except Exception as e:
        db.session.rollback()
        try:
            current_app.logger.exception("seed_leaderboards_failed")
        except Exception:
            pass
        debug_payload = _debug_error_payload(e, u)
        if debug_payload:
            return jsonify({"ok": False, "error": "db_error", **debug_payload}), 500
        return jsonify({"ok": False, "error": "db_error"}), 500

    return jsonify(
        {
            "ok": True,
            "states_seeded": [x[0] for x in states],
            "merchants_created": int(created_users),
            "merchants_reused": int(reused_users),
            "profiles_created": int(created_profiles),
            "profiles_reused": int(reused_profiles),
            "listings_created": int(created_listings),
            "listings_reused": int(reused_listings),
            "listing_schema_ok": bool(listing_schema_ok),
            "listing_schema_missing": listing_schema_missing[:20],
            "follows_created": int(created_follows),
            "merchant_ids": merchant_ids[:20],
        }
    ), 200
