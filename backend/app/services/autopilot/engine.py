from __future__ import annotations

import json
from datetime import datetime, timedelta

from app.extensions import db
from app.models import (
    AuditLog,
    AutopilotEvent,
    AutopilotRecommendation,
    AutopilotSnapshot,
    CommissionPolicy,
    CommissionPolicyRule,
)
from app.models.autopilot_recommendation import recommendation_json_dumps
from app.services.autopilot.recommender import (
    generate_recommendations,
    min_days_between_drafts,
    preview_policy_impact,
)
from app.services.autopilot.signals import compute_autopilot_signals, compute_snapshot_hash
from app.services.simulation.liquidity_simulator import get_liquidity_baseline, run_liquidity_simulation


VALID_REC_STATUS = {"new", "accepted", "dismissed", "converted_to_draft"}


def _json(payload: dict | list | None) -> str:
    try:
        return json.dumps(payload or {}, separators=(",", ":"), ensure_ascii=False)
    except Exception:
        return "{}"


def _log_autopilot_event(event_type: str, admin_id: int | None, payload: dict | None = None) -> None:
    try:
        db.session.add(
            AutopilotEvent(
                event_type=(event_type or "").strip()[:40] or "unknown",
                admin_id=int(admin_id) if admin_id is not None else None,
                payload_json=_json(payload or {}),
            )
        )
    except Exception:
        pass


def _log_admin_audit(admin_id: int | None, action: str, target_id: int | None, meta: dict | None = None) -> None:
    try:
        db.session.add(
            AuditLog(
                actor_user_id=int(admin_id) if admin_id is not None else None,
                action=(action or "").strip()[:64] or "autopilot_event",
                target_type="autopilot",
                target_id=int(target_id) if target_id is not None else None,
                meta=_json(meta or {}),
            )
        )
    except Exception:
        pass


def _find_existing_snapshot(window_days: int, hash_key: str) -> AutopilotSnapshot | None:
    return (
        AutopilotSnapshot.query.filter_by(window_days=int(window_days), hash_key=hash_key)
        .order_by(AutopilotSnapshot.id.desc())
        .first()
    )


def run_autopilot(*, window_days: int, admin_id: int | None = None) -> dict:
    metrics = compute_autopilot_signals(window_days=window_days)
    window = int(metrics.get("window_days") or window_days or 30)
    hash_key = compute_snapshot_hash(window_days=window, metrics=metrics)
    existing = _find_existing_snapshot(window, hash_key)
    if existing:
        recs = (
            AutopilotRecommendation.query.filter_by(snapshot_id=int(existing.id))
            .order_by(AutopilotRecommendation.id.asc())
            .all()
        )
        return {
            "ok": True,
            "snapshot": existing.to_dict(),
            "recommendations": [row.to_dict() for row in recs],
            "idempotent": True,
        }

    snapshot = AutopilotSnapshot(
        window_days=window,
        generated_at=datetime.utcnow(),
        metrics_json=recommendation_json_dumps(metrics),
        created_by_admin_id=int(admin_id) if admin_id is not None else None,
        hash_key=hash_key,
    )
    db.session.add(snapshot)
    db.session.flush()

    rec_payloads = generate_recommendations(metrics)
    rec_rows: list[AutopilotRecommendation] = []
    for payload in rec_payloads:
        row = AutopilotRecommendation(
            snapshot_id=int(snapshot.id),
            applies_to=(payload.get("applies_to") or "declutter"),
            seller_type=(payload.get("seller_type") or "all"),
            city=(payload.get("city") or "all"),
            recommendation_json=recommendation_json_dumps(payload),
            status="new",
        )
        db.session.add(row)
        rec_rows.append(row)

    _log_autopilot_event(
        "run",
        admin_id,
        payload={
            "window_days": window,
            "snapshot_id": int(snapshot.id),
            "recommendations_count": len(rec_rows),
            "hash_key": hash_key,
        },
    )
    _log_admin_audit(
        admin_id,
        "autopilot_run",
        int(snapshot.id),
        {"window_days": window, "recommendations_count": len(rec_rows), "hash_key": hash_key},
    )
    db.session.commit()
    return {
        "ok": True,
        "snapshot": snapshot.to_dict(),
        "recommendations": [row.to_dict() for row in rec_rows],
        "idempotent": False,
    }


def set_recommendation_status(*, recommendation_id: int, status: str, admin_id: int | None = None) -> dict:
    normalized = (status or "").strip().lower()
    if normalized not in VALID_REC_STATUS:
        return {"ok": False, "message": "status must be new|accepted|dismissed|converted_to_draft"}
    row = db.session.get(AutopilotRecommendation, int(recommendation_id))
    if not row:
        return {"ok": False, "message": "Recommendation not found"}
    row.status = normalized
    db.session.add(row)
    _log_autopilot_event(
        "recommendation_status_changed",
        admin_id,
        payload={"recommendation_id": int(row.id), "status": normalized, "snapshot_id": int(row.snapshot_id)},
    )
    _log_admin_audit(
        admin_id,
        "autopilot_recommendation_status",
        int(row.id),
        {"status": normalized, "snapshot_id": int(row.snapshot_id)},
    )
    db.session.commit()
    return {"ok": True, "recommendation": row.to_dict()}


def _find_or_create_latest_snapshot(*, window_days: int, admin_id: int | None) -> dict:
    latest = (
        AutopilotSnapshot.query.filter_by(window_days=int(window_days))
        .order_by(AutopilotSnapshot.generated_at.desc(), AutopilotSnapshot.id.desc())
        .first()
    )
    if latest:
        recs = (
            AutopilotRecommendation.query.filter_by(snapshot_id=int(latest.id))
            .order_by(AutopilotRecommendation.id.asc())
            .all()
        )
        return {"snapshot": latest, "recommendations": recs}
    run = run_autopilot(window_days=window_days, admin_id=admin_id)
    snapshot = db.session.get(AutopilotSnapshot, int((run.get("snapshot") or {}).get("id") or 0))
    recs = (
        AutopilotRecommendation.query.filter_by(snapshot_id=int(snapshot.id))
        .order_by(AutopilotRecommendation.id.asc())
        .all()
        if snapshot
        else []
    )
    return {"snapshot": snapshot, "recommendations": recs}


def generate_draft_policy(*, window_days: int, admin_id: int | None, accepted_only: bool = True) -> dict:
    payload = _find_or_create_latest_snapshot(window_days=window_days, admin_id=admin_id)
    snapshot: AutopilotSnapshot | None = payload.get("snapshot")
    recs: list[AutopilotRecommendation] = payload.get("recommendations") or []
    if not snapshot:
        return {"ok": False, "message": "Could not resolve autopilot snapshot"}

    if snapshot.draft_policy_id:
        existing_policy = db.session.get(CommissionPolicy, int(snapshot.draft_policy_id))
        if existing_policy:
            return {
                "ok": True,
                "snapshot": snapshot.to_dict(),
                "policy": existing_policy.to_dict(),
                "idempotent": True,
            }

    cooldown_days = min_days_between_drafts()
    latest_draft = (
        CommissionPolicy.query.filter(CommissionPolicy.name.ilike("Autopilot Draft%"))
        .order_by(CommissionPolicy.created_at.desc(), CommissionPolicy.id.desc())
        .first()
    )
    if latest_draft and latest_draft.created_at:
        min_next = latest_draft.created_at + timedelta(days=cooldown_days)
        if datetime.utcnow() < min_next:
            return {
                "ok": False,
                "message": f"Autopilot draft cooldown active ({cooldown_days}d).",
                "cooldown_until": min_next.isoformat(),
                "existing_policy_id": int(latest_draft.id),
            }

    filtered = [
        row
        for row in recs
        if row.status == "accepted" or (not accepted_only and row.status in ("new", "accepted"))
    ]
    if not filtered:
        return {
            "ok": False,
            "message": "No accepted recommendations available for draft generation",
            "snapshot": snapshot.to_dict(),
        }

    now = datetime.utcnow()
    policy = CommissionPolicy(
        name=f"Autopilot Draft {now.strftime('%Y-%m-%d')} (window {int(snapshot.window_days)}d)",
        status="draft",
        created_by_admin_id=int(admin_id) if admin_id is not None else None,
        created_at=now,
        notes=_json({"autopilot_snapshot_id": int(snapshot.id), "window_days": int(snapshot.window_days)}),
    )
    db.session.add(policy)
    db.session.flush()

    created_rules = 0
    rec_ids: list[int] = []
    for row in filtered:
        recommendation = row.recommendation()
        rule = recommendation.get("rule_payload") or {}
        cpr = CommissionPolicyRule(
            policy_id=int(policy.id),
            applies_to=(rule.get("applies_to") or "all"),
            seller_type=(rule.get("seller_type") or "all"),
            city=(rule.get("city") or None),
            base_rate_bps=int(rule.get("base_rate_bps") or 500),
            min_fee_minor=int(rule["min_fee_minor"]) if rule.get("min_fee_minor") is not None else None,
            max_fee_minor=int(rule["max_fee_minor"]) if rule.get("max_fee_minor") is not None else None,
            promo_discount_bps=int(rule["promo_discount_bps"]) if rule.get("promo_discount_bps") is not None else None,
            starts_at=None,
            ends_at=None,
            created_at=now,
        )
        starts_at = (rule.get("starts_at") or "").strip()
        ends_at = (rule.get("ends_at") or "").strip()
        try:
            if starts_at:
                cpr.starts_at = datetime.fromisoformat(starts_at.replace("Z", ""))
            if ends_at:
                cpr.ends_at = datetime.fromisoformat(ends_at.replace("Z", ""))
        except Exception:
            cpr.starts_at = None
            cpr.ends_at = None
        db.session.add(cpr)
        row.status = "converted_to_draft"
        db.session.add(row)
        created_rules += 1
        rec_ids.append(int(row.id))

    snapshot.draft_policy_id = int(policy.id)
    db.session.add(snapshot)

    _log_autopilot_event(
        "draft_created",
        admin_id,
        payload={
            "snapshot_id": int(snapshot.id),
            "draft_policy_id": int(policy.id),
            "rules_count": int(created_rules),
            "recommendation_ids": rec_ids,
        },
    )
    _log_admin_audit(
        admin_id,
        "autopilot_draft_created",
        int(policy.id),
        {"snapshot_id": int(snapshot.id), "recommendation_ids": rec_ids, "rules_count": int(created_rules)},
    )
    db.session.commit()
    return {
        "ok": True,
        "snapshot": snapshot.to_dict(),
        "policy": policy.to_dict(),
        "rules_count": int(created_rules),
        "recommendation_ids": rec_ids,
        "idempotent": False,
    }


def preview_draft_impact(*, draft_policy_id: int) -> dict:
    policy = db.session.get(CommissionPolicy, int(draft_policy_id))
    if not policy:
        return {"ok": False, "message": "Draft policy not found"}
    rules = (
        CommissionPolicyRule.query.filter_by(policy_id=int(policy.id))
        .order_by(CommissionPolicyRule.id.asc())
        .all()
    )
    latest_snapshot = (
        AutopilotSnapshot.query.order_by(AutopilotSnapshot.generated_at.desc(), AutopilotSnapshot.id.desc())
        .first()
    )
    signals = latest_snapshot.metrics() if latest_snapshot else compute_autopilot_signals(window_days=30)
    impact = preview_policy_impact(
        draft_policy=policy.to_dict(),
        rules=[row.to_dict() for row in rules],
        signals=signals,
    )

    baseline = get_liquidity_baseline()
    current_bps = 500
    total_gmv = 0
    weighted = 0
    for segment in impact.get("segments") or []:
        gmv_minor = int(segment.get("gmv_minor") or 0)
        proposed_bps = int(segment.get("proposed_bps") or 500)
        total_gmv += gmv_minor
        weighted += proposed_bps * gmv_minor
    if total_gmv > 0:
        current_bps = int(round(weighted / total_gmv))

    base_sim = run_liquidity_simulation(
        time_horizon_days=90,
        assumed_daily_gmv_minor=int(baseline.get("avg_daily_gmv_minor") or 0),
        assumed_order_count_daily=float(baseline.get("avg_daily_orders") or 0.0),
        withdrawal_rate_pct=float(baseline.get("withdrawal_ratio") or 0.0) * 100.0,
        payout_delay_days=3,
        chargeback_rate_pct=1.5,
        operating_cost_daily_minor=0,
        commission_bps=500,
        scenario="base",
    )
    proposed_sim = run_liquidity_simulation(
        time_horizon_days=90,
        assumed_daily_gmv_minor=int(baseline.get("avg_daily_gmv_minor") or 0),
        assumed_order_count_daily=float(baseline.get("avg_daily_orders") or 0.0),
        withdrawal_rate_pct=float(baseline.get("withdrawal_ratio") or 0.0) * 100.0,
        payout_delay_days=3,
        chargeback_rate_pct=1.5,
        operating_cost_daily_minor=0,
        commission_bps=current_bps,
        scenario="base",
    )
    impact["liquidity_effect"] = {
        "baseline_min_cash_minor": int(base_sim.get("min_cash_balance_minor") or 0),
        "proposed_min_cash_minor": int(proposed_sim.get("min_cash_balance_minor") or 0),
        "delta_min_cash_minor": int((proposed_sim.get("min_cash_balance_minor") or 0) - (base_sim.get("min_cash_balance_minor") or 0)),
        "baseline_days_to_negative": base_sim.get("days_to_negative"),
        "proposed_days_to_negative": proposed_sim.get("days_to_negative"),
    }
    return impact
