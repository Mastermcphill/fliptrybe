from __future__ import annotations

import os
import uuid
from datetime import datetime

from flask import Blueprint, jsonify, request
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError

from app.extensions import db
from app.models import User, Listing, Order, OrderEvent, DriverProfile, MerchantProfile, MoneyBoxAccount, MoneyBoxLedger, Wallet, WalletTxn
from app.models import InspectorProfile
from app.utils.ng_locations import NIGERIA_LOCATIONS, get_city_coords
from app.jobs.escrow_runner import _hold_order_into_escrow
from app.utils.bonding import (
    refresh_bond_required_for_tier,
    required_amount_for_tier,
    topup_bond,
    reserve_for_inspection,
)

demo_bp = Blueprint("demo_bp", __name__, url_prefix="/api/demo")

_INIT = False


def _is_demo_env() -> bool:
    env = (os.getenv("FLIPTRYBE_ENV", "dev") or "dev").strip().lower()
    if env in ("prod", "production", "staging"):
        return False
    # allow any non-prod env by default
    if env:
        return True
    flask_env = (os.getenv("FLASK_ENV") or "").strip().lower()
    app_env = (os.getenv("APP_ENV") or "").strip().lower()
    if flask_env == "development":
        return True
    if app_env in ("dev", "development"):
        return True
    if os.getenv("FLASK_DEBUG") == "1" or os.getenv("DEBUG") == "1":
        return True
    return False


@demo_bp.before_app_request
def _ensure_tables_once():
    global _INIT
    if _INIT:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT = True


@demo_bp.post("/seed")
def demo_seed():
    def _truthy(val) -> bool:
        return str(val or "").strip().lower() in ("1", "true", "yes", "y", "on")

    env = (os.getenv("FLIPTRYBE_ENV", "dev") or "dev").strip().lower()
    allow_override = _truthy(os.getenv("FLIPTRYBE_ENABLE_DEMO_SEED"))
    if env in ("prod", "production") and not allow_override:
        return jsonify({"message": "Demo seed disabled in production"}), 403

    payload = request.get_json(silent=True) or {}
    reset_flag = _truthy(payload.get("reset")) or _truthy(request.args.get("reset")) or (os.getenv("FLIPTRYBE_SEED_RESET") or "").strip() == "1"
    count = payload.get("count", 10)
    try:
        count = int(count)
    except Exception:
        count = 10
    count = max(3, min(count, 25))

    def _ensure_user(email: str, name: str, role: str) -> User:
        u = User.query.filter_by(email=email).first()
        if not u:
            u = User(name=name, email=email, role=role)
            try:
                u.set_password("demo12345")
            except Exception:
                pass
            db.session.add(u)
            db.session.commit()
            return u

        changed = False
        if (u.role or "").lower() != role:
            u.role = role
            changed = True
        if not (u.name or "").strip():
            u.name = name
            changed = True
        try:
            u.set_password("demo12345")
            changed = True
        except Exception:
            pass
        if changed:
            db.session.add(u)
            db.session.commit()
        return u

    buyer_user = _ensure_user("buyer@fliptrybe.com", "Demo Buyer", "buyer")
    merchant_user = _ensure_user("merchant@fliptrybe.com", "Demo Merchant", "merchant")
    driver_user = _ensure_user("driver@fliptrybe.com", "Demo Driver", "driver")
    admin_user = _ensure_user("admin@fliptrybe.com", "Demo Admin", "admin")
    inspector_user = _ensure_user("inspector@fliptrybe.com", "Demo Inspector", "inspector")

    try:
        driver_user.is_available = True
        db.session.add(driver_user)
        db.session.commit()
    except Exception:
        db.session.rollback()

    # Create/update merchant profile
    try:
        mp = MerchantProfile.query.filter_by(user_id=merchant_user.id).first()
        if not mp:
            mp = MerchantProfile(user_id=merchant_user.id)
        try:
            mp.is_top_tier = True
        except Exception:
            pass
        mp.shop_name = "Demo Merchant"
        mp.shop_category = "Electronics"
        mp.phone = mp.phone or "08000000001"
        mp.state = "Lagos"
        mp.city = "Ikeja"
        mp.locality = "Ikeja"
        db.session.add(mp)
        db.session.commit()
    except Exception:
        db.session.rollback()

    # Create/update driver profile
    try:
        dp = DriverProfile.query.filter_by(user_id=driver_user.id).first()
        if not dp:
            dp = DriverProfile(user_id=driver_user.id)
        dp.phone = dp.phone or "08000000002"
        dp.vehicle_type = dp.vehicle_type or "bike"
        dp.plate_number = dp.plate_number or "DEMO-001"
        dp.state = "Lagos"
        dp.city = "Ikeja"
        dp.locality = "Ikeja"
        dp.is_active = True
        db.session.add(dp)
        db.session.commit()
    except Exception:
        db.session.rollback()

    ip = None
    # Create/update inspector profile + bond
    try:
        ip = InspectorProfile.query.filter_by(user_id=inspector_user.id).first()
        if not ip:
            ip = InspectorProfile(user_id=inspector_user.id, is_active=True, region="Lagos")
        ip.is_active = True
        ip.region = "Lagos"
        try:
            ip.phone = ip.phone or "08000000003"
        except Exception:
            pass
        if not (ip.reputation_tier or "").strip():
            ip.reputation_tier = "SILVER"
        db.session.add(ip)
        db.session.commit()
    except Exception:
        db.session.rollback()

    try:
        bond = refresh_bond_required_for_tier(int(inspector_user.id), getattr(ip, "reputation_tier", "SILVER"))
        required = required_amount_for_tier(getattr(ip, "reputation_tier", "SILVER"))
        available = float(bond.bond_available_amount or 0.0)
        if available < required:
            topup_bond(int(inspector_user.id), float(required - available), note="Demo seed topup")
    except Exception:
        db.session.rollback()

    # Do NOT delete data by default; only reset when explicitly requested
    try:
        if reset_flag:
            demo_listing_ids = [
                int(r.id) for r in Listing.query.filter(
                    Listing.user_id == int(merchant_user.id),
                    or_(
                        Listing.seed_key.ilike("demo_listing_%"),
                        Listing.title.ilike("Demo Listing #%"),
                        Listing.description.ilike("%Investor demo%"),
                    )
                ).all()
            ]
            if demo_listing_ids:
                order_ids = [
                    int(r.id) for r in Order.query.filter(
                        Order.listing_id.in_(demo_listing_ids)
                    ).all()
                ]
                if order_ids:
                    try:
                        OrderEvent.query.filter(OrderEvent.order_id.in_(order_ids)).delete(synchronize_session=False)
                    except Exception:
                        pass
                    try:
                        Order.query.filter(Order.id.in_(order_ids)).delete(synchronize_session=False)
                    except Exception:
                        pass
                Listing.query.filter(Listing.id.in_(demo_listing_ids)).delete(synchronize_session=False)
            db.session.commit()
    except Exception:
        db.session.rollback()

    priority_states = {'Lagos', 'FCT', 'Oyo', 'Rivers', 'Kano'}
    priority = [x for x in NIGERIA_LOCATIONS if x.get('state') in priority_states]
    rest = [x for x in NIGERIA_LOCATIONS if x.get('state') not in priority_states]
    seed_locations = priority + rest
    lagos_loc = next((x for x in NIGERIA_LOCATIONS if x.get('state') == 'Lagos'), None)
    lagos_cities = ["Ikeja", "Lagos", "Ikorodu"]
    if lagos_loc and (lagos_loc.get("cities") or []):
        lagos_cities = lagos_loc.get("cities") or lagos_cities

    created = []
    for i in range(count):
        if i < 3 and lagos_loc:
            loc = lagos_loc
            city = lagos_cities[i % len(lagos_cities)]
        else:
            loc = seed_locations[i % len(seed_locations)]
            cities = loc.get('cities') or []
            city = cities[i % len(cities)] if cities else loc.get('state')
        base_price = float(5000 + (i * 750))
        platform_fee = round(base_price * 0.03, 2)
        final_price = round(base_price + platform_fee, 2)
        title = f"Demo Listing #{i+1}"
        seed_key = f"demo_listing_{i+1}"
        l = Listing.query.filter_by(seed_key=seed_key).first()
        if not l:
            try:
                l = Listing.query.filter_by(title=title, user_id=int(merchant_user.id)).first()
            except Exception:
                l = None
            if l and not getattr(l, "seed_key", None):
                l.seed_key = seed_key
        if not l:
            l = Listing(seed_key=seed_key)
        l.title = title
        l.description = "Investor demo listing generated automatically."
        l.price = final_price
        l.base_price = base_price
        l.platform_fee = platform_fee
        l.final_price = final_price
        l.user_id = merchant_user.id
        l.state = (loc.get('state') or '').strip()
        l.city = (city or '').strip()
        l.locality = (city or '').strip()
        l.image_path = ""
        for field, value in (
            ('is_active', True),
            ('is_disabled', False),
            ('disabled', False),
            ('status', 'active'),
        ):
            if hasattr(l, field):
                try:
                    setattr(l, field, value)
                except Exception:
                    pass

        coords = get_city_coords(city)
        if coords and hasattr(l, 'latitude') and hasattr(l, 'longitude'):
            try:
                l.latitude = coords[0]
                l.longitude = coords[1]
            except Exception:
                pass

        try:
            db.session.add(l)
            db.session.commit()
        except IntegrityError:
            db.session.rollback()
            l = Listing.query.filter_by(seed_key=seed_key).first()
            if l:
                l.title = title
                l.description = "Investor demo listing generated automatically."
                l.price = final_price
                l.base_price = base_price
                l.platform_fee = platform_fee
                l.final_price = final_price
                l.user_id = merchant_user.id
                l.state = (loc.get('state') or '').strip()
                l.city = (city or '').strip()
                l.locality = (city or '').strip()
                l.image_path = ""
                try:
                    db.session.add(l)
                    db.session.commit()
                except Exception:
                    db.session.rollback()
        except Exception:
            db.session.rollback()
        if l:
            created.append(l.to_dict())

    # Seed a demo order for end-to-end flows (idempotent)
    try:
        if created:
            first_id = created[0].get("id") if isinstance(created[0], dict) else None
            if first_id:
                demo_ref = "demo-seed-order"
                demo_key = "demo_seed_order"
                o = Order.query.filter_by(seed_key=demo_key).first()
                if not o:
                    o = Order.query.filter_by(payment_reference=demo_ref).first()
                    if o and not getattr(o, "seed_key", None):
                        o.seed_key = demo_key
                if not o:
                    o = Order(seed_key=demo_key)
                o.buyer_id = int(buyer_user.id)
                o.merchant_id = int(merchant_user.id)
                o.listing_id = int(first_id)
                o.amount = float(created[0].get("price") or 0.0)
                o.delivery_fee = 1500.0
                o.inspection_fee = 0.0
                o.status = "merchant_accepted"
                o.payment_reference = demo_ref
                o.inspection_required = True
                o.inspection_status = "PENDING"
                o.inspection_outcome = "NONE"
                o.inspector_id = int(inspector_user.id)
                o.driver_id = None
                o.release_condition = "INSPECTION_PASS"
                o.updated_at = datetime.utcnow()
                _hold_order_into_escrow(o)
                try:
                    db.session.add(o)
                    db.session.commit()
                except IntegrityError:
                    db.session.rollback()
                    o = Order.query.filter_by(seed_key=demo_key).first()
                except Exception:
                    db.session.rollback()
                seed_key = f"order:{int(o.id)}:seeded:seed"
                existing_event = OrderEvent.query.filter_by(idempotency_key=seed_key[:160]).first()
                if not existing_event:
                    existing_event = OrderEvent.query.filter_by(order_id=int(o.id), event="seeded").first()
                if not existing_event:
                    db.session.add(
                        OrderEvent(
                            order_id=int(o.id),
                            actor_user_id=int(admin_user.id),
                            event="seeded",
                            note="Demo seed order",
                            idempotency_key=seed_key[:160],
                        )
                    )
                    db.session.commit()
                try:
                    required = required_amount_for_tier(getattr(ip, "reputation_tier", "SILVER"))
                    reserve_for_inspection(int(inspector_user.id), int(o.id), float(required))
                except Exception:
                    db.session.rollback()
    except Exception:
        db.session.rollback()

    seeded_order_id = None
    try:
        seeded = Order.query.filter_by(seed_key="demo_seed_order").first()
        if seeded:
            seeded_order_id = int(seeded.id)
    except Exception:
        seeded_order_id = None

    return jsonify({"ok": True, "created": len(created), "listings": created[:5], "seeded_order_id": seeded_order_id}), 201


@demo_bp.get("/ledger_summary")
def ledger_summary():
    if not _is_demo_env():
        return jsonify({"message": "Not found"}), 404

    email = (request.args.get("user") or request.args.get("email") or "").strip().lower()
    if not email:
        email = "merchant@fliptrybe.com"

    u = User.query.filter_by(email=email).first()
    if not u:
        return jsonify({"message": "User not found"}), 404

    acct = MoneyBoxAccount.query.filter_by(user_id=int(u.id)).first()
    moneybox_count = 0
    mb_last = []
    if acct:
        moneybox_count = MoneyBoxLedger.query.filter_by(account_id=int(acct.id)).count()
        rows = (
            MoneyBoxLedger.query
            .filter_by(account_id=int(acct.id))
            .order_by(MoneyBoxLedger.id.desc())
            .limit(5)
            .all()
        )
        mb_last = [{
            "id": int(r.id),
            "amount": float(r.amount or 0.0),
            "entry_type": r.entry_type or "",
            "reference": r.reference or "",
            "created_at": r.created_at.isoformat() if r.created_at else None,
        } for r in rows]

    wallet = Wallet.query.filter_by(user_id=int(u.id)).first()
    wallet_count = 0
    wallet_last = []
    wallet_balance = 0.0
    if wallet:
        wallet_count = WalletTxn.query.filter_by(wallet_id=int(wallet.id)).count()
        wallet_balance = float(wallet.balance or 0.0)
        rows = (
            WalletTxn.query
            .filter_by(wallet_id=int(wallet.id))
            .order_by(WalletTxn.id.desc())
            .limit(5)
            .all()
        )
        wallet_last = [{
            "id": int(r.id),
            "amount": float(r.amount or 0.0),
            "direction": r.direction or "",
            "kind": r.kind or "",
            "reference": r.reference or "",
            "created_at": r.created_at.isoformat() if r.created_at else None,
        } for r in rows]

    demo_emails = [
        "buyer@fliptrybe.com",
        "merchant@fliptrybe.com",
        "driver@fliptrybe.com",
        "admin@fliptrybe.com",
        "inspector@fliptrybe.com",
    ]
    try:
        demo_user_count = User.query.filter(User.email.in_(demo_emails)).count()
    except Exception:
        demo_user_count = 0
    try:
        demo_listing_count = Listing.query.filter(Listing.seed_key.ilike("demo_listing_%")).count()
    except Exception:
        demo_listing_count = 0
    try:
        demo_order_count = Order.query.filter(Order.seed_key == "demo_seed_order").count()
    except Exception:
        demo_order_count = 0

    return jsonify({
        "ok": True,
        "user_id": int(u.id),
        "moneybox_count": int(moneybox_count),
        "wallet_txn_count": int(wallet_count),
        "moneybox_principal": float(getattr(acct, "principal_balance", 0.0) if acct else 0.0),
        "wallet_balance": float(wallet_balance),
        "moneybox_last": mb_last,
        "wallet_last": wallet_last,
        "demo_user_count": int(demo_user_count),
        "demo_listing_count": int(demo_listing_count),
        "demo_order_count": int(demo_order_count),
    }), 200
