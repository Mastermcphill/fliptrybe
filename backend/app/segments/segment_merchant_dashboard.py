from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request, current_app
from app.extensions import db
from app.models import Listing, User, Order, Receipt
from app.utils.jwt_utils import decode_token

merchant_bp = Blueprint("merchant_bp", __name__, url_prefix="/api/merchant")


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



def _merchant_tier_from_score(score: int) -> str:
    if score >= 90:
        return "Elite"
    if score >= 75:
        return "Verified"
    if score >= 55:
        return "Trusted"
    return "Starter"


@merchant_bp.get("/dashboard")
def merchant_dashboard():
    """
    Investor-demo-safe merchant dashboard.
    Returns lightweight metrics and current tier.
    """
    # For now, compute simple stats from listings table
    total_listings = Listing.query.count()

    # Simple score placeholder: increase as platform develops
    score = 60 if total_listings > 0 else 40
    tier = _merchant_tier_from_score(score)

    return jsonify({
        "ok": True,
        "tier": tier,
        "score": score,
        "metrics": {
            "total_listings": total_listings,
            "total_orders": 0,
            "total_sales": 0,
            "pending_withdrawals": 0,
        },
        "ranking_rules": [
            "Order completion rate",
            "Dispute/refund rate",
            "Response speed",
            "Delivery on-time rate",
            "Buyer ratings",
            "Repeat purchases",
        ],
    }), 200


@merchant_bp.get("/kpis")
def merchant_kpis():
    """Real merchant KPIs computed from listings/orders/receipts (token-based)."""
    u = _current_user()
    if not u:
        return jsonify({"ok": True, "kpis": {}}), 200

    mid = int(u.id)

    listings_count = Listing.query.filter_by(user_id=mid).count()

    orders = Order.query.filter_by(merchant_id=mid).all()
    orders_count = len(orders)

    by_status = {}
    revenue = 0.0
    delivery_fees = 0.0
    for o in orders:
        st = (o.status or "unknown").lower()
        by_status[st] = by_status.get(st, 0) + 1
        revenue += float(o.amount or 0.0)
        delivery_fees += float(o.delivery_fee or 0.0)

    # receipts for this merchant
    recs = Receipt.query.filter_by(user_id=mid).all()
    commission_total = sum(float(r.fee or 0.0) for r in recs)
    receipts_total = sum(float(r.total or 0.0) for r in recs)

    # simple health score (demo-friendly)
    completed = by_status.get("completed", 0) + by_status.get("delivered", 0)
    completion_rate = (completed / orders_count) if orders_count else 0.0
    score = int(40 + min(60, (completion_rate * 50) + min(10, listings_count)))

    return jsonify({
        "ok": True,
        "kpis": {
            "listings_count": listings_count,
            "orders_count": orders_count,
            "orders_by_status": by_status,
            "revenue_gross": round(revenue, 2),
            "delivery_fees_gross": round(delivery_fees, 2),
            "commission_total": round(commission_total, 2),
            "receipts_total": round(receipts_total, 2),
            "completion_rate": round(completion_rate, 3),
            "score": score,
        }
    }), 200


@merchant_bp.get("/analytics")
def merchant_analytics():
    """Lightweight sales analytics for merchant accounts."""
    u = _current_user()
    if not u:
        return jsonify({"ok": True, "paid_last_7": 0, "paid_last_30": 0, "recent_paid": []}), 200

    try:
        mid = int(u.id)
    except Exception:
        return jsonify({"ok": True, "paid_last_7": 0, "paid_last_30": 0, "recent_paid": []}), 200

    paid_statuses = {
        "paid",
        "merchant_accepted",
        "driver_assigned",
        "picked_up",
        "delivered",
        "completed",
    }

    try:
        now = datetime.utcnow()
        base_q = Order.query.filter_by(merchant_id=mid).filter(Order.status.in_(list(paid_statuses)))
        paid_last_7 = base_q.filter(Order.created_at >= (now - timedelta(days=7))).count()
        paid_last_30 = base_q.filter(Order.created_at >= (now - timedelta(days=30))).count()

        recent = (
            base_q.order_by(Order.created_at.desc())
            .limit(12)
            .all()
        )

        recent_out = []
        for o in recent:
            recent_out.append({
                "order_id": int(o.id),
                "listing_id": int(o.listing_id) if o.listing_id is not None else None,
                "amount": float(o.amount or 0.0),
                "status": (o.status or "").strip().lower(),
                "created_at": o.created_at.isoformat() if o.created_at else None,
            })

        return jsonify({
            "ok": True,
            "paid_last_7": int(paid_last_7),
            "paid_last_30": int(paid_last_30),
            "recent_paid": recent_out,
        }), 200
    except Exception:
        db.session.rollback()
        try:
            current_app.logger.exception("merchant_analytics_error")
        except Exception:
            pass
        return jsonify({"ok": True, "paid_last_7": 0, "paid_last_30": 0, "recent_paid": []}), 200


@merchant_bp.get("/leaderboard")
def merchant_leaderboard():
    """Public-ish leaderboard for demo (top merchants by score)."""
    # Pull recent merchants from listings table
    rows = (
        Listing.query.order_by(Listing.created_at.desc())
        .limit(500)
        .all()
    )
    merchant_ids = []
    for l in rows:
        if l.user_id and int(l.user_id) not in merchant_ids:
            merchant_ids.append(int(l.user_id))

    out = []
    for mid in merchant_ids[:50]:
        # compute score quickly from existing kpis function logic
        listings_count = Listing.query.filter_by(user_id=mid).count()
        orders = Order.query.filter_by(merchant_id=mid).all()
        orders_count = len(orders)
        by_status = {}
        revenue = 0.0
        for o in orders:
            st = (o.status or "unknown").lower()
            by_status[st] = by_status.get(st, 0) + 1
            revenue += float(o.amount or 0.0)
        completed = by_status.get("completed", 0) + by_status.get("delivered", 0)
        completion_rate = (completed / orders_count) if orders_count else 0.0
        score = int(40 + min(60, (completion_rate * 50) + min(10, listings_count)))

        u = User.query.get(mid)
        out.append({
            "merchant_id": mid,
            "name": (u.name if u else "") or "",
            "email": (u.email if u else "") or "",
            "score": score,
            "listings": listings_count,
            "orders": orders_count,
            "completion_rate": round(completion_rate, 3),
            "revenue_gross": round(revenue, 2),
        })

    out.sort(key=lambda x: (x.get("score", 0), x.get("revenue_gross", 0)), reverse=True)
    return jsonify(out[:25]), 200
