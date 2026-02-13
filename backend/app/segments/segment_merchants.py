from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request
from sqlalchemy import text

from app.extensions import db
from app.models import User, MerchantProfile, MerchantReview, Wallet, Transaction, MerchantFollow
from app.utils.jwt_utils import decode_token
from app.utils.commission import compute_commission, RATES
from app.utils.receipts import create_receipt
from app.utils.notify import queue_in_app, queue_sms, queue_whatsapp, mark_sent
from app.utils.account_flags import flag_duplicate_phone

merchants_bp = Blueprint("merchants_bp", __name__, url_prefix="/api")

_MERCHANTS_INIT_DONE = False


@merchants_bp.before_app_request
def _ensure_tables_once():
    global _MERCHANTS_INIT_DONE
    if _MERCHANTS_INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _MERCHANTS_INIT_DONE = True


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
        user_id = int(sub)
    except Exception:
        return None
    return User.query.get(user_id)


def _get_or_create_profile(user_id: int) -> MerchantProfile:
    mp = MerchantProfile.query.filter_by(user_id=user_id).first()
    if mp:
        return mp
    mp = MerchantProfile(user_id=user_id)
    db.session.add(mp)
    db.session.commit()
    return mp


def _get_or_create_wallet(user_id: int) -> Wallet:
    w = Wallet.query.filter_by(user_id=user_id).first()
    if w:
        return w
    w = Wallet(user_id=user_id, balance=0.0)
    db.session.add(w)
    db.session.commit()
    return w


def _tx(wallet_id: int, *, amount: float, gross: float, net: float, commission: float, purpose: str, direction: str, reference: str) -> Transaction:
    tx = Transaction(
        wallet_id=wallet_id,
        amount=amount,
        gross_amount=gross,
        net_amount=net,
        commission_total=commission,
        purpose=purpose,
        direction=direction,
        reference=reference[:50],
        created_at=datetime.utcnow(),
    )
    db.session.add(tx)
    return tx


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    # MVP: treat first user as admin or email contains "admin"
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


def _merchant_public_payload(user_id: int) -> dict:
    user = User.query.get(int(user_id))
    profile = MerchantProfile.query.filter_by(user_id=int(user_id)).first()
    followers = MerchantFollow.query.filter_by(merchant_id=int(user_id)).count()
    display_name = ""
    if profile and (profile.shop_name or "").strip():
        display_name = (profile.shop_name or "").strip()
    elif user and (user.name or "").strip():
        display_name = (user.name or "").strip()
    else:
        display_name = f"Merchant {int(user_id)}"
    return {
        "id": int(user_id),
        "name": display_name,
        "profile_image_url": (getattr(user, "profile_image_url", "") or "") if user else "",
        "joined_at": user.created_at.isoformat() if user and user.created_at else None,
        "followers_count": int(followers or 0),
    }


@merchants_bp.get("/merchants")
def list_merchants():
    state = (request.args.get("state") or "").strip()
    city = (request.args.get("city") or "").strip()
    category = (request.args.get("category") or "").strip()

    q = MerchantProfile.query
    if state:
        q = q.filter(MerchantProfile.state.ilike(state))
    if city:
        q = q.filter(MerchantProfile.city.ilike(city))
    if category:
        q = q.filter(MerchantProfile.shop_category.ilike(category))

    items = q.all()
    # Sort by score desc
    items.sort(key=lambda x: float(x.score()), reverse=True)

    payload = []
    for row in items:
        item = row.to_dict()
        user = User.query.get(int(row.user_id)) if row.user_id is not None else None
        item["profile_image_url"] = (getattr(user, "profile_image_url", "") or "") if user else ""
        payload.append(item)
    return jsonify({"ok": True, "items": payload}), 200


@merchants_bp.post("/me/profile/photo")
def set_profile_photo():
    user = _current_user()
    if not user:
        return jsonify({"message": "Unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    url = str(payload.get("profile_image_url") or "").strip()
    if not url:
        return jsonify({"ok": False, "error": "PROFILE_IMAGE_REQUIRED", "message": "profile_image_url is required"}), 400
    if not (url.startswith("http://") or url.startswith("https://")):
        return jsonify({"ok": False, "error": "PROFILE_IMAGE_INVALID", "message": "profile_image_url must be an absolute URL"}), 400
    user.profile_image_url = url[:1024]
    try:
        db.session.add(user)
        db.session.commit()
        return jsonify({"ok": True, "profile_image_url": user.profile_image_url}), 200
    except Exception as exc:
        db.session.rollback()
        return jsonify({"ok": False, "error": "PROFILE_IMAGE_UPDATE_FAILED", "message": str(exc)}), 500


@merchants_bp.get("/public/merchants/<int:user_id>")
def public_merchant_card(user_id: int):
    user = User.query.get(int(user_id))
    if not user:
        return jsonify({"message": "Merchant not found"}), 404
    return jsonify({"ok": True, "merchant": _merchant_public_payload(int(user_id))}), 200


@merchants_bp.get("/merchants/top")
def top_merchants():
    limit = 20
    raw_limit = (request.args.get("limit") or "").strip()
    try:
        limit = int(raw_limit) if raw_limit else 20
    except Exception:
        limit = 20
    if limit <= 0:
        limit = 20
    if limit > 50:
        limit = 50

    items = MerchantProfile.query.all()
    items.sort(key=lambda x: float(x.score()), reverse=True)
    payload = []
    for row in items[:limit]:
        item = row.to_dict()
        user = User.query.get(int(row.user_id)) if row.user_id is not None else None
        item["profile_image_url"] = (getattr(user, "profile_image_url", "") or "") if user else ""
        payload.append(item)
    return jsonify({"ok": True, "items": payload}), 200


@merchants_bp.get("/merchants/<int:user_id>")
def merchant_detail(user_id: int):
    mp = MerchantProfile.query.filter_by(user_id=user_id).first()
    if not mp:
        return jsonify({"message": "Merchant not found"}), 404

    reviews = MerchantReview.query.filter_by(merchant_user_id=user_id).order_by(MerchantReview.created_at.desc()).limit(30).all()
    merchant_payload = mp.to_dict()
    merchant_payload["profile_image_url"] = (getattr(User.query.get(int(user_id)), "profile_image_url", "") or "")
    return jsonify({"ok": True, "merchant": merchant_payload, "public_card": _merchant_public_payload(int(user_id)), "reviews": [x.to_dict() for x in reviews]}), 200


@merchants_bp.post("/merchants/profile")
def upsert_profile():
    user = _current_user()
    if not user:
        return jsonify({"message": "Unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    mp = _get_or_create_profile(user.id)

    mp.shop_name = (payload.get("shop_name") or mp.shop_name or "").strip() or None
    mp.shop_category = (payload.get("shop_category") or mp.shop_category or "").strip() or None
    incoming_phone = (payload.get("phone") or mp.phone or "").strip() or None
    if incoming_phone:
        try:
            dup_users = flag_duplicate_phone(int(user.id), incoming_phone)
            if dup_users:
                return jsonify({"message": "Phone already in use by another account"}), 409
        except Exception:
            pass
    mp.phone = incoming_phone

    mp.state = (payload.get("state") or mp.state or "").strip() or None
    mp.city = (payload.get("city") or mp.city or "").strip() or None
    mp.locality = (payload.get("locality") or mp.locality or "").strip() or None
    mp.lga = (payload.get("lga") or mp.lga or "").strip() or None

    mp.updated_at = datetime.utcnow()

    try:
        db.session.add(mp)
        db.session.commit()
        return jsonify({"ok": True, "merchant": mp.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Profile update failed", "error": str(e)}), 500


@merchants_bp.post("/merchants/<int:user_id>/review")
def add_review(user_id: int):
    payload = request.get_json(silent=True) or {}
    try:
        rating = int(payload.get("rating") or 5)
    except Exception:
        rating = 5
    if rating < 1:
        rating = 1
    if rating > 5:
        rating = 5

    comment = (payload.get("comment") or "").strip()
    name = (payload.get("rater_name") or "Anonymous").strip()

    mp = MerchantProfile.query.filter_by(user_id=user_id).first()
    if not mp:
        mp = _get_or_create_profile(user_id)

    rev = MerchantReview(merchant_user_id=user_id, rater_name=name, rating=rating, comment=comment)
    db.session.add(rev)

    # update avg rating incrementally
    prev_count = int(mp.rating_count or 0)
    prev_avg = float(mp.avg_rating or 0.0)
    new_count = prev_count + 1
    new_avg = ((prev_avg * prev_count) + float(rating)) / float(new_count)

    mp.rating_count = new_count
    mp.avg_rating = float(round(new_avg, 2))
    mp.updated_at = datetime.utcnow()

    try:
        db.session.commit()
        return jsonify({"ok": True, "merchant": mp.to_dict(), "review": rev.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Review failed", "error": str(e)}), 500


@merchants_bp.post("/admin/merchants/<int:user_id>/feature")
def admin_feature(user_id: int):
    user = _current_user()
    if not _is_admin(user):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    flag = bool(payload.get("is_featured") is True)

    mp = _get_or_create_profile(user_id)
    mp.is_featured = flag
    mp.updated_at = datetime.utcnow()

    try:
        db.session.commit()
        return jsonify({"ok": True, "merchant": mp.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Update failed", "error": str(e)}), 500


@merchants_bp.post("/admin/merchants/<int:user_id>/suspend")
def admin_suspend(user_id: int):
    user = _current_user()
    if not _is_admin(user):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    flag = bool(payload.get("is_suspended") is True)

    mp = _get_or_create_profile(user_id)
    mp.is_suspended = flag
    mp.updated_at = datetime.utcnow()

    try:
        db.session.commit()
        try:
            if flag:
                from app.models import MoneyBoxAccount
                from app.utils.moneybox import liquidate_to_wallet
                acct = MoneyBoxAccount.query.filter_by(user_id=int(user_id)).first()
                if acct:
                    liquidate_to_wallet(acct, reason="merchant_suspended", reference=f"merchant_suspended:{int(user_id)}")
        except Exception:
            pass
        return jsonify({"ok": True, "merchant": mp.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Update failed", "error": str(e)}), 500


@merchants_bp.post("/merchants/<int:user_id>/simulate-sale")
def simulate_sale(user_id: int):
    """Investor/demo: simulate a sale -> credits merchant wallet net, records commission tx."""
    payload = request.get_json(silent=True) or {}
    try:
        gross = float(payload.get("amount") or 0.0)
    except Exception:
        gross = 0.0

    if gross <= 0:
        return jsonify({"message": "amount must be > 0"}), 400

    mp = _get_or_create_profile(user_id)
    if mp.is_suspended:
        return jsonify({"message": "merchant suspended"}), 400

    base_price = float(gross)
    if base_price < 0:
        base_price = 0.0
    platform_fee = round(base_price * 0.03, 2)
    final_price = round(base_price + platform_fee, 2)

    incentive = 0.0
    platform_share = platform_fee
    if bool(getattr(mp, "is_top_tier", False)) and platform_fee > 0:
        incentive = round(platform_fee * (11.0 / 13.0), 2)
        platform_share = round(platform_fee - incentive, 2)

    net = round(base_price + incentive, 2)

    # create receipt (buyer side demo uses same user_id)
    rec = create_receipt(
        user_id=user_id,
        kind="listing_sale",
        reference=f"sale:{datetime.utcnow().isoformat()}",
        amount=base_price,
        fee=platform_fee,
        total=final_price,
        description="Listing sale receipt (demo)",
        meta={"platform_fee": platform_fee, "net_to_merchant": net, "incentive": incentive, "platform_share": platform_share},
    )

    # queue notifications (in-app + sms + whatsapp) and mark sent for demo
    n1 = queue_in_app(user_id, "Sale completed", f"You received NGN {net}.", meta={"receipt_id": None})
    n2 = queue_sms(user_id, "Sale completed", f"FlipTrybe: You received NGN {net}.", provider="stub")
    n3 = queue_whatsapp(user_id, "Sale completed", f"FlipTrybe: You received NGN {net}.", provider="stub")
    mark_sent(n1, "local:sent")
    mark_sent(n2, "stub:sms")
    mark_sent(n3, "stub:whatsapp")

    # update merchant stats
    mp.total_sales = float(mp.total_sales or 0.0) + float(final_price)
    mp.total_orders = int(mp.total_orders or 0) + 1
    mp.successful_deliveries = int(mp.successful_deliveries or 0) + 1
    mp.updated_at = datetime.utcnow()

    # wallet credit
    w = _get_or_create_wallet(user_id)
    w.balance = float(w.balance or 0.0) + float(net)
    _tx(
        w.id,
        amount=abs(float(net)),
        gross=float(final_price),
        net=float(net),
        commission=float(platform_fee),
        purpose="listing_sale",
        direction="credit",
        reference=f"sale:{datetime.utcnow().isoformat()}",
    )

    try:
        db.session.commit()
        return jsonify({"ok": True, "merchant": mp.to_dict(), "wallet_balance": float(w.balance or 0.0), "base_price": base_price, "platform_fee": platform_fee, "final_price": final_price, "net": net}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Simulation failed", "error": str(e)}), 500
