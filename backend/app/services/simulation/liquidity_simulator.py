from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from app.models import Order, PayoutRequest, ShortletBooking, Wallet, WalletTxn


PAID_ORDER_STATES = (
    "paid",
    "merchant_accepted",
    "driver_assigned",
    "picked_up",
    "delivered",
    "completed",
)


def _to_minor(amount) -> int:
    try:
        parsed = Decimal(str(amount or 0))
    except Exception:
        parsed = Decimal("0")
    return int((parsed * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _ratio(value) -> float:
    try:
        return max(0.0, min(1.0, float(value or 0.0)))
    except Exception:
        return 0.0


def _pct(value) -> float:
    try:
        return max(0.0, min(100.0, float(value or 0.0)))
    except Exception:
        return 0.0


def _platform_wallet_balance_minor() -> int:
    # Platform wallet currently maps to earliest admin wallet in this codebase.
    wallet = Wallet.query.order_by(Wallet.id.asc()).first()
    if not wallet:
        return 0
    return _to_minor(getattr(wallet, "balance", 0.0))


def get_liquidity_baseline() -> dict:
    now = datetime.utcnow()
    since = now - timedelta(days=30)
    orders = Order.query.filter(Order.created_at >= since, Order.status.in_(PAID_ORDER_STATES)).all()
    bookings = ShortletBooking.query.filter(
        ShortletBooking.created_at >= since,
        ShortletBooking.payment_status == "paid",
    ).all()
    total_gmv_minor = sum(_to_minor(getattr(o, "total_price", 0.0) or getattr(o, "amount", 0.0)) for o in orders)
    total_gmv_minor += sum(_to_minor(getattr(b, "total_amount", 0.0)) for b in bookings)

    total_orders = int(len(orders) + len(bookings))
    avg_daily_gmv_minor = int(round(total_gmv_minor / 30.0)) if total_gmv_minor > 0 else 0
    avg_daily_orders = float(total_orders) / 30.0

    order_commission_minor = sum(
        int(getattr(o, "sale_platform_minor", 0) or 0)
        + int(getattr(o, "delivery_platform_minor", 0) or 0)
        + int(getattr(o, "inspection_platform_minor", 0) or 0)
        for o in orders
    )
    shortlet_commission_minor = sum(_to_minor((float(getattr(b, "total_amount", 0.0) or 0.0) * 0.05)) for b in bookings)
    total_commission_minor = int(order_commission_minor + shortlet_commission_minor)
    avg_daily_commission_minor = int(round(total_commission_minor / 30.0)) if total_commission_minor > 0 else 0

    payout_rows = PayoutRequest.query.filter(PayoutRequest.created_at >= since).all()
    payout_minor = sum(_to_minor(getattr(row, "amount", 0.0)) for row in payout_rows)
    withdrawal_ratio = (float(payout_minor) / float(total_gmv_minor)) if total_gmv_minor > 0 else 0.0

    return {
        "ok": True,
        "window_days": 30,
        "avg_daily_gmv_minor": int(max(0, avg_daily_gmv_minor)),
        "avg_daily_orders": float(round(avg_daily_orders, 3)),
        "avg_daily_commission_minor": int(max(0, avg_daily_commission_minor)),
        "withdrawal_ratio": float(round(max(0.0, withdrawal_ratio), 4)),
        "platform_wallet_balance_minor": int(max(0, _platform_wallet_balance_minor())),
    }


@dataclass(frozen=True)
class ScenarioConfig:
    name: str
    gmv_factor: float
    orders_factor: float
    withdrawal_factor: float
    chargeback_factor: float


SCENARIOS = {
    "base": ScenarioConfig("base", 1.0, 1.0, 1.0, 1.0),
    "optimistic": ScenarioConfig("optimistic", 1.15, 1.1, 0.9, 0.8),
    "pessimistic": ScenarioConfig("pessimistic", 0.85, 0.9, 1.15, 1.3),
}


def run_liquidity_simulation(
    *,
    time_horizon_days: int,
    assumed_daily_gmv_minor: int,
    assumed_order_count_daily: float,
    withdrawal_rate_pct: float,
    payout_delay_days: int,
    chargeback_rate_pct: float,
    operating_cost_daily_minor: int = 0,
    commission_bps: int = 500,
    scenario: str = "base",
) -> dict:
    horizon = max(1, min(int(time_horizon_days or 0), 365))
    gmv_daily = max(0, int(assumed_daily_gmv_minor or 0))
    order_daily = max(0.0, float(assumed_order_count_daily or 0.0))
    withdraw_ratio = _pct(withdrawal_rate_pct) / 100.0
    chargeback_ratio = _pct(chargeback_rate_pct) / 100.0
    payout_delay = max(0, min(int(payout_delay_days or 0), 60))
    opex_daily = max(0, int(operating_cost_daily_minor or 0))
    fee_bps = max(0, int(commission_bps or 0))

    profile = SCENARIOS.get((scenario or "base").strip().lower(), SCENARIOS["base"])
    opening_balance_minor = _platform_wallet_balance_minor()
    balance = int(opening_balance_minor)
    min_balance = int(balance)
    days_to_negative = None
    pending_payouts: list[int] = [0 for _ in range(payout_delay + 1)]

    projected_commission_revenue_minor = 0
    projected_payouts_minor = 0
    projected_platform_float_minor = 0
    balance_series: list[dict] = []
    stress_points: list[str] = []

    for day in range(1, horizon + 1):
        day_gmv = int(round(gmv_daily * profile.gmv_factor))
        day_orders = max(0.0, order_daily * profile.orders_factor)
        day_commission = int(round((day_gmv * fee_bps) / 10000.0))
        day_chargebacks = int(round(day_gmv * chargeback_ratio * profile.chargeback_factor))
        seller_side_cash = max(0, day_gmv - day_commission)
        day_payout_scheduled = int(round(seller_side_cash * _ratio(withdraw_ratio * profile.withdrawal_factor)))

        matured_payout = pending_payouts.pop(0) if pending_payouts else 0
        pending_payouts.append(day_payout_scheduled)

        balance = balance + day_commission - matured_payout - day_chargebacks - opex_daily
        min_balance = min(min_balance, balance)
        if balance < 0 and days_to_negative is None:
            days_to_negative = day
        if day_chargebacks > int(day_commission * 0.9):
            stress_points.append(f"Day {day}: chargeback wave ({day_chargebacks} minor)")
        if matured_payout > int(day_commission * 2):
            stress_points.append(f"Day {day}: payout spike ({matured_payout} minor)")

        projected_commission_revenue_minor += day_commission
        projected_payouts_minor += matured_payout
        projected_platform_float_minor += max(0, day_commission - matured_payout)
        balance_series.append(
            {
                "day": int(day),
                "gmv_minor": int(day_gmv),
                "orders": float(round(day_orders, 3)),
                "commission_minor": int(day_commission),
                "chargebacks_minor": int(day_chargebacks),
                "payouts_minor": int(matured_payout),
                "operating_cost_minor": int(opex_daily),
                "balance_minor": int(balance),
            }
        )

    return {
        "ok": True,
        "scenario": profile.name,
        "inputs": {
            "time_horizon_days": int(horizon),
            "assumed_daily_gmv_minor": int(gmv_daily),
            "assumed_order_count_daily": float(round(order_daily, 3)),
            "withdrawal_rate_pct": float(_pct(withdrawal_rate_pct)),
            "payout_delay_days": int(payout_delay),
            "chargeback_rate_pct": float(_pct(chargeback_rate_pct)),
            "operating_cost_daily_minor": int(opex_daily),
            "commission_bps": int(fee_bps),
        },
        "opening_balance_minor": int(opening_balance_minor),
        "projected_commission_revenue_minor": int(projected_commission_revenue_minor),
        "projected_payouts_minor": int(projected_payouts_minor),
        "projected_platform_float_minor": int(projected_platform_float_minor),
        "min_cash_balance_minor": int(min_balance),
        "days_to_negative": int(days_to_negative) if days_to_negative is not None else None,
        "stress_points": stress_points[:30],
        "series": balance_series,
    }
