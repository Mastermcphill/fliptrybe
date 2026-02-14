from __future__ import annotations

from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import (
    ListingFavorite,
    Order,
    ShortletBooking,
    User,
)
from app.utils.jwt_utils import decode_token, get_bearer_token


user_analytics_bp = Blueprint("user_analytics_bp", __name__, url_prefix="/api")

_ORDER_SUCCESS_STATUSES = (
    "paid",
    "merchant_accepted",
    "driver_assigned",
    "picked_up",
    "delivered",
    "completed",
)


def _money_to_minor(value) -> int:
    try:
        return int(round(float(value or 0.0) * 100.0))
    except Exception:
        return 0


def _month_floor(dt: datetime) -> datetime:
    return datetime(dt.year, dt.month, 1)


def _month_add(dt: datetime, months: int) -> datetime:
    year = dt.year + (dt.month - 1 + months) // 12
    month = (dt.month - 1 + months) % 12 + 1
    return datetime(year, month, 1)


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


def _is_admin_like(user: User | None) -> bool:
    if not user:
        return False
    role = (getattr(user, "role", None) or "").strip().lower()
    if role in ("admin", "investor"):
        return True
    try:
        return int(getattr(user, "id", 0) or 0) == 1
    except Exception:
        return False


@user_analytics_bp.get("/buyer/analytics")
def buyer_analytics():
    user = _current_user()
    if not user:
        return jsonify({"ok": False, "error": "UNAUTHORIZED", "message": "Unauthorized"}), 401

    paid_orders = Order.query.filter(
        Order.buyer_id == int(user.id),
        Order.status.in_(_ORDER_SUCCESS_STATUSES),
    ).all()
    paid_bookings = ShortletBooking.query.filter(
        ShortletBooking.user_id == int(user.id),
        ShortletBooking.payment_status == "paid",
    ).all()
    total_purchases = int(len(paid_orders) + len(paid_bookings))
    total_spent_minor = int(
        sum(_money_to_minor(getattr(o, "total_price", None) or getattr(o, "amount", 0.0)) for o in paid_orders)
        + sum(_money_to_minor(getattr(b, "total_amount", 0.0)) for b in paid_bookings)
    )
    saved_listings_count = ListingFavorite.query.filter_by(user_id=int(user.id)).count()

    return jsonify(
        {
            "ok": True,
            "total_purchases": total_purchases,
            "total_spent_minor": total_spent_minor,
            "saved_listings_count": int(saved_listings_count),
        }
    ), 200


@user_analytics_bp.get("/investor/analytics")
def investor_analytics():
    user = _current_user()
    if not _is_admin_like(user):
        return jsonify({"ok": False, "error": "FORBIDDEN", "message": "Forbidden"}), 403

    now = datetime.utcnow()
    orders = Order.query.filter(Order.status.in_(_ORDER_SUCCESS_STATUSES)).all()
    bookings = ShortletBooking.query.filter(ShortletBooking.payment_status == "paid").all()

    total_orders = int(len(orders) + len(bookings))
    total_gmv_minor = int(
        sum(_money_to_minor(getattr(o, "total_price", None) or getattr(o, "amount", 0.0)) for o in orders)
        + sum(_money_to_minor(getattr(b, "total_amount", 0.0)) for b in bookings)
    )
    commission_minor = int(
        sum(
            int(getattr(o, "sale_platform_minor", 0) or 0)
            + int(getattr(o, "delivery_platform_minor", 0) or 0)
            + int(getattr(o, "inspection_platform_minor", 0) or 0)
            for o in orders
        )
        + sum(_money_to_minor(float(getattr(b, "total_amount", 0.0) or 0.0) * 0.05) for b in bookings)
    )

    avg_order_value_minor = int(round(total_gmv_minor / total_orders)) if total_orders > 0 else 0
    avg_commission_per_order_minor = int(round(commission_minor / total_orders)) if total_orders > 0 else 0
    try:
        cac_minor = int(request.args.get("cac_minor") or 0)
    except Exception:
        cac_minor = 0
    if cac_minor < 0:
        cac_minor = 0
    ltv_estimate_minor = int(max(avg_commission_per_order_minor * 6 - cac_minor, 0))

    active_cutoff = now - timedelta(days=30)
    active_users = set()
    for row in Order.query.filter(Order.created_at >= active_cutoff).all():
        if row.buyer_id:
            active_users.add(int(row.buyer_id))
        if row.merchant_id:
            active_users.add(int(row.merchant_id))
    for row in ShortletBooking.query.filter(ShortletBooking.created_at >= active_cutoff).all():
        if row.user_id:
            active_users.add(int(row.user_id))

    trend = []
    month_start = _month_floor(now)
    for back in range(5, -1, -1):
        start = _month_add(month_start, -back)
        end = _month_add(start, 1)
        month_orders = Order.query.filter(
            Order.status.in_(_ORDER_SUCCESS_STATUSES),
            Order.created_at >= start,
            Order.created_at < end,
        ).all()
        month_bookings = ShortletBooking.query.filter(
            ShortletBooking.payment_status == "paid",
            ShortletBooking.created_at >= start,
            ShortletBooking.created_at < end,
        ).all()
        month_gmv = int(
            sum(_money_to_minor(getattr(o, "total_price", None) or getattr(o, "amount", 0.0)) for o in month_orders)
            + sum(_money_to_minor(getattr(b, "total_amount", 0.0)) for b in month_bookings)
        )
        month_commission = int(
            sum(
                int(getattr(o, "sale_platform_minor", 0) or 0)
                + int(getattr(o, "delivery_platform_minor", 0) or 0)
                + int(getattr(o, "inspection_platform_minor", 0) or 0)
                for o in month_orders
            )
            + sum(_money_to_minor(float(getattr(b, "total_amount", 0.0) or 0.0) * 0.05) for b in month_bookings)
        )
        trend.append(
            {
                "month": start.strftime("%Y-%m"),
                "gmv_minor": month_gmv,
                "commission_minor": month_commission,
            }
        )

    return jsonify(
        {
            "ok": True,
            "gmv_trend": trend,
            "commission_revenue_minor": int(commission_minor),
            "unit_economics": {
                "avg_order_value_minor": int(avg_order_value_minor),
                "avg_commission_per_order_minor": int(avg_commission_per_order_minor),
                "cac_minor": int(cac_minor),
                "ltv_estimate_minor": int(ltv_estimate_minor),
            },
            "active_users_last_30_days": int(len(active_users)),
        }
    ), 200
