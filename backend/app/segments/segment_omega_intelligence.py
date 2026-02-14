from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import AutopilotRecommendation, AutopilotSnapshot, FraudFlag, User
from app.services.elasticity import compute_segment_elasticity, list_recent_elasticity_snapshots
from app.services.fraud import evaluate_active_fraud_flags, freeze_user_for_fraud, review_fraud_flag
from app.services.simulation import city_liquidity_snapshot, simulate_cross_market_balance, simulate_geo_expansion
from app.utils.jwt_utils import decode_token, get_bearer_token


omega_bp = Blueprint("omega_bp", __name__, url_prefix="/api/admin")


def _current_user() -> User | None:
    token = get_bearer_token(request.headers.get("Authorization", ""))
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    try:
        uid = int(payload.get("sub") or 0)
    except Exception:
        return None
    if uid <= 0:
        return None
    try:
        return db.session.get(User, uid)
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return None


def _is_admin(user: User | None) -> bool:
    if not user:
        return False
    role = (getattr(user, "role", None) or "").strip().lower()
    if role == "admin":
        return True
    try:
        return int(getattr(user, "id", 0) or 0) == 1
    except Exception:
        return False


def _require_admin():
    user = _current_user()
    if not user:
        return None, (jsonify({"message": "Unauthorized"}), 401)
    if not _is_admin(user):
        return None, (jsonify({"message": "Forbidden"}), 403)
    return user, None


def _safe_int(value, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


@omega_bp.get("/elasticity/segment")
def admin_elasticity_segment():
    _, err = _require_admin()
    if err:
        return err
    category = (request.args.get("category") or "declutter").strip().lower()
    city = (request.args.get("city") or "all").strip()
    seller_type = (request.args.get("seller_type") or "all").strip().lower()
    window_days = _safe_int(request.args.get("window_days") or 90, 90)
    payload = compute_segment_elasticity(
        category=category,
        city=city,
        seller_type=seller_type,
        window_days=window_days,
        persist_snapshot=True,
    )
    return jsonify({"ok": True, **payload}), 200


@omega_bp.get("/elasticity/snapshots")
def admin_elasticity_snapshots():
    _, err = _require_admin()
    if err:
        return err
    limit = _safe_int(request.args.get("limit") or 30, 30)
    return jsonify({"ok": True, "items": list_recent_elasticity_snapshots(limit=limit)}), 200


@omega_bp.get("/fraud/flags")
def admin_fraud_flags():
    _, err = _require_admin()
    if err:
        return err
    refresh = (request.args.get("refresh") or "1").strip().lower() not in ("0", "false", "no")
    if refresh:
        evaluate_active_fraud_flags(window_days=30, max_users=500)

    status = (request.args.get("status") or "").strip().lower()
    min_score = _safe_int(request.args.get("min_score") or 0, 0)
    limit = max(1, min(_safe_int(request.args.get("limit") or 100, 100), 300))
    offset = max(0, _safe_int(request.args.get("offset") or 0, 0))

    query = FraudFlag.query
    if status:
        if status == "open_only":
            query = query.filter(FraudFlag.status.in_(("open", "reviewed", "action_taken")))
        else:
            query = query.filter(FraudFlag.status == status)
    if min_score > 0:
        query = query.filter(FraudFlag.score >= int(min_score))
    total = query.count()
    rows = (
        query.order_by(FraudFlag.score.desc(), FraudFlag.created_at.desc(), FraudFlag.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    user_ids = [int(row.user_id) for row in rows if row.user_id is not None]
    users = {}
    if user_ids:
        for user in User.query.filter(User.id.in_(user_ids)).all():
            users[int(user.id)] = user
    items = []
    for row in rows:
        item = row.to_dict()
        score = int(item.get("score") or 0)
        if score >= 80:
            level = "freeze"
        elif score >= 60:
            level = "flag"
        elif score >= 30:
            level = "monitor"
        else:
            level = "normal"
        user = users.get(int(row.user_id))
        item["level"] = level
        item["user"] = {
            "id": int(user.id) if user else int(row.user_id),
            "name": (getattr(user, "name", None) or ""),
            "email": (getattr(user, "email", None) or ""),
            "is_active": bool(getattr(user, "is_active", True)) if user else True,
            "role": (getattr(user, "role", None) or "") if user else "",
        }
        items.append(item)
    return jsonify(
        {
            "ok": True,
            "items": items,
            "total": int(total),
            "limit": int(limit),
            "offset": int(offset),
        }
    ), 200


@omega_bp.post("/fraud/<int:fraud_flag_id>/review")
def admin_review_fraud_flag(fraud_flag_id: int):
    user, err = _require_admin()
    if err:
        return err
    payload = request.get_json(silent=True) or {}
    status = (payload.get("status") or "reviewed").strip().lower()
    note = (payload.get("note") or "").strip()
    result = review_fraud_flag(
        fraud_flag_id=int(fraud_flag_id),
        admin_id=int(user.id),
        status=status,
        note=note,
    )
    if not result.get("ok"):
        return jsonify(result), 400
    return jsonify(result), 200


@omega_bp.post("/fraud/<int:fraud_flag_id>/freeze")
def admin_freeze_fraud_flag(fraud_flag_id: int):
    user, err = _require_admin()
    if err:
        return err
    payload = request.get_json(silent=True) or {}
    note = (payload.get("note") or "").strip()
    result = freeze_user_for_fraud(
        fraud_flag_id=int(fraud_flag_id),
        admin_id=int(user.id),
        note=note,
    )
    if not result.get("ok"):
        return jsonify(result), 400
    return jsonify(result), 200


@omega_bp.post("/liquidity/cross-market-simulate")
def admin_cross_market_simulate():
    _, err = _require_admin()
    if err:
        return err
    payload = request.get_json(silent=True) or {}
    result = simulate_cross_market_balance(
        time_horizon_days=_safe_int(payload.get("time_horizon_days") or 90, 90),
        commission_shift_city=(payload.get("commission_shift_city") or "").strip(),
        commission_shift_bps=_safe_int(payload.get("commission_shift_bps") or 0, 0),
        promo_city=(payload.get("promo_city") or "").strip(),
        promo_discount_bps=_safe_int(payload.get("promo_discount_bps") or 0, 0),
        payout_delay_adjustment_days=_safe_int(payload.get("payout_delay_adjustment_days") or 0, 0),
    )
    return jsonify(result), 200


@omega_bp.post("/expansion/simulate")
def admin_expansion_simulate():
    _, err = _require_admin()
    if err:
        return err
    payload = request.get_json(silent=True) or {}
    result = simulate_geo_expansion(
        target_city=(payload.get("target_city") or "").strip(),
        assumed_listings=_safe_int(payload.get("assumed_listings") or 0, 0),
        assumed_daily_gmv_minor=_safe_int(payload.get("assumed_daily_gmv_minor") or 0, 0),
        average_order_value_minor=_safe_int(payload.get("average_order_value_minor") or 1, 1),
        marketing_budget_minor=_safe_int(payload.get("marketing_budget_minor") or 0, 0),
        estimated_commission_bps=_safe_int(payload.get("estimated_commission_bps") or 500, 500),
        operating_cost_daily_minor=_safe_int(payload.get("operating_cost_daily_minor") or 0, 0),
    )
    return jsonify(result), 200


@omega_bp.get("/omega/intelligence")
def admin_omega_intelligence():
    _, err = _require_admin()
    if err:
        return err
    elasticity_declutter = compute_segment_elasticity(
        category="declutter",
        city=(request.args.get("city") or "all"),
        seller_type="all",
        window_days=90,
        persist_snapshot=True,
    )
    elasticity_shortlet = compute_segment_elasticity(
        category="shortlet",
        city=(request.args.get("city") or "all"),
        seller_type="all",
        window_days=90,
        persist_snapshot=True,
    )
    fraud_open = FraudFlag.query.filter(FraudFlag.status.in_(("open", "reviewed", "action_taken"))).all()
    high_risk = [row for row in fraud_open if int(row.score or 0) >= 80]
    liquidity = city_liquidity_snapshot(window_days=30)

    latest_snapshot = (
        AutopilotSnapshot.query.order_by(AutopilotSnapshot.generated_at.desc(), AutopilotSnapshot.id.desc()).first()
    )
    autopilot_rows = []
    if latest_snapshot:
        autopilot_rows = (
            AutopilotRecommendation.query.filter_by(snapshot_id=int(latest_snapshot.id))
            .order_by(AutopilotRecommendation.id.desc())
            .limit(20)
            .all()
        )
    risk_overlay = []
    for row in autopilot_rows:
        rec = row.recommendation()
        risk_flags = rec.get("risk_flags") or []
        if risk_flags:
            risk_overlay.append(
                {
                    "recommendation_id": int(row.id),
                    "title": rec.get("title") or "",
                    "status": row.status or "new",
                    "risk_flags": risk_flags,
                    "confidence": rec.get("confidence") or "low",
                }
            )

    expansion_candidates = []
    for city_row in liquidity.get("cities") or []:
        if float(city_row.get("float_ratio") or 0.0) > 0.02:
            expansion_candidates.append(
                {
                    "city": city_row.get("city"),
                    "signal": "surplus_float",
                    "float_ratio": float(city_row.get("float_ratio") or 0.0),
                    "gmv_minor": int(city_row.get("gmv_minor") or 0),
                }
            )
    expansion_candidates = sorted(
        expansion_candidates,
        key=lambda row: (row.get("float_ratio") or 0.0, row.get("gmv_minor") or 0),
        reverse=True,
    )[:10]

    payload = {
        "ok": True,
        "generated_at": datetime.utcnow().isoformat(),
        "panels": {
            "elasticity_overview": {
                "declutter": {
                    "coefficient": elasticity_declutter.get("elasticity_coefficient"),
                    "sensitivity": elasticity_declutter.get("price_sensitivity"),
                    "confidence": elasticity_declutter.get("confidence"),
                },
                "shortlet": {
                    "coefficient": elasticity_shortlet.get("elasticity_coefficient"),
                    "sensitivity": elasticity_shortlet.get("price_sensitivity"),
                    "confidence": elasticity_shortlet.get("confidence"),
                },
            },
            "fraud_risk_heatmap": {
                "open_flags": int(len(fraud_open)),
                "high_risk_flags": int(len(high_risk)),
            },
            "liquidity_stress_radar": {
                "risk_flags": liquidity.get("risk_flags") or [],
                "stressed_cities": liquidity.get("stressed_cities") or [],
                "surplus_cities": liquidity.get("surplus_cities") or [],
            },
            "expansion_opportunities": expansion_candidates,
            "autopilot_risk_overlay": risk_overlay,
        },
    }
    return jsonify(payload), 200
