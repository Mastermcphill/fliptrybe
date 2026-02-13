from __future__ import annotations

import os
import hmac
import json
from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import Order, User, InspectorProfile, InspectionReview, InspectionAudit, OrderEvent, AvailabilityConfirmation, InspectionTicket, EscrowUnlock
from app.utils.jwt_utils import decode_token
from app.utils.account_flags import flag_duplicate_phone
from app.utils.escrow_unlocks import ensure_unlock, set_code_if_missing, verify_code, bump_attempts, mark_unlock_qr_verified
from app.utils.notify import queue_sms, queue_whatsapp
from app.jobs.escrow_runner import _hold_order_into_escrow, run_escrow_automation
from app.escrow import release_inspector_payout
from app.utils.events import log_event
from app.utils.bonding import (
    get_or_create_bond,
    refresh_bond_required_for_tier,
    reserve_for_inspection,
    release_for_inspection,
    slash_for_audit,
    required_amount_for_tier,
)


inspections_bp = Blueprint("inspections_bp", __name__, url_prefix="/api")


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


def _availability_confirmed(order_id: int) -> bool:
    try:
        row = AvailabilityConfirmation.query.filter_by(order_id=int(order_id)).first()
        return bool(row and (row.status or "") == "yes")
    except Exception:
        return False


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _is_admin(u: User | None) -> bool:
    if not u:
        return False
    r = _role(u)
    if r == "admin":
        return True
    try:
        return int(u.id or 0) == 1
    except Exception:
        return False


def _now():
    return datetime.utcnow()


def _event(order_id: int, actor_id: int | None, event: str, note: str = "") -> None:
    try:
        key = f"order:{int(order_id)}:{event}:{int(actor_id) if actor_id is not None else 'system'}"
        existing = OrderEvent.query.filter_by(idempotency_key=key[:160]).first()
        if existing:
            return
        e = OrderEvent(
            order_id=int(order_id),
            actor_user_id=actor_id,
            event=event,
            note=note[:240],
            idempotency_key=key[:160],
        )
        db.session.add(e)
        db.session.commit()
        mapped = None
        ev = (event or "").strip().lower()
        if "inspection_requested" in ev:
            mapped = "inspection_requested"
        elif ev in ("inspection_inspected", "inspection_completed", "inspected", "inspection_closed"):
            mapped = "inspection_completed"
        if mapped:
            log_event(
                mapped,
                actor_user_id=actor_id,
                subject_type="order",
                subject_id=int(order_id),
                idempotency_key=f"inspection_event:{int(order_id)}:{mapped}:{int(actor_id) if actor_id is not None else 'system'}",
                metadata={"event": event, "note": note},
            )
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass


def _tier_rank(tier: str | None) -> int:
    t = (tier or "BRONZE").strip().upper()
    if t == "PLATINUM":
        return 4
    if t == "GOLD":
        return 3
    if t == "SILVER":
        return 2
    return 1


def _active_inspection_count(inspector_user_id: int) -> int:
    return (
        Order.query
        .filter(Order.inspector_id == int(inspector_user_id))
        .filter(Order.inspection_status.in_(["PENDING", "ON_MY_WAY", "ARRIVED", "INSPECTED"]))
        .count()
    )


def _recompute_profile_score(prof: InspectorProfile, order: Order | None = None) -> InspectorProfile:
    rows = InspectionReview.query.filter_by(inspector_user_id=int(prof.user_id)).all()
    if rows:
        avg_rating = sum([int(r.rating or 0) for r in rows]) / max(1, len(rows))
    else:
        avg_rating = 3.5

    avg_rating_delta = float(avg_rating) - 3.5

    on_time = 0.0
    if order and order.inspection_on_my_way_at and order.inspection_arrived_at:
        delta_min = (order.inspection_arrived_at - order.inspection_on_my_way_at).total_seconds() / 60.0
        on_time = 1.0 if delta_min <= 120 else 0.0

    audits = int(prof.dispute_audit_count or 0)
    overturned = int(prof.dispute_overturned_count or 0)
    overturned_rate = (overturned / audits) if audits > 0 else 0.0

    evidence_quality_rate = 1.0

    score = 70.0
    score += 6.0 * avg_rating_delta
    score += 8.0 * on_time
    score -= 12.0 * overturned_rate
    score += 4.0 * evidence_quality_rate
    score = max(0.0, min(100.0, score))

    tier = "BRONZE"
    if score >= 85:
        tier = "PLATINUM"
    elif score >= 70:
        tier = "GOLD"
    elif score >= 50:
        tier = "SILVER"

    prof.reputation_score = score
    prof.reputation_tier = tier
    prof.last_score_at = _now()
    prof.updated_at = _now()
    return prof


def _assign_inspector(order: Order) -> int | None:
    """Pick the best available inspector.

    Current strategy (safe default):
      - Active inspector profile
      - Region match (if provided)
      - Higher reputation tier
      - Higher reputation score
      - Lower active inspection load
    """
    profiles = InspectorProfile.query.filter_by(is_active=True).all()
    if not profiles:
        return None

    region_hint = (order.pickup or "").strip().lower()
    scored = []

    for prof in profiles:
        try:
            bond = refresh_bond_required_for_tier(int(prof.user_id), prof.reputation_tier)
        except Exception:
            bond = get_or_create_bond(int(prof.user_id), tier=prof.reputation_tier)

        if float(bond.bond_available_amount or 0.0) < float(bond.bond_required_amount or 0.0):
            continue
        if (bond.status or "") != "ACTIVE":
            continue

        region = (prof.region or "").strip().lower()
        region_match = 0
        if region and region_hint:
            if region == region_hint or region in region_hint:
                region_match = 1

        load = _active_inspection_count(int(prof.user_id))
        scored.append(
            (
                region_match,
                _tier_rank(prof.reputation_tier),
                float(prof.reputation_score or 0.0),
                -int(load),
                prof,
            )
        )

    if not scored:
        return None

    scored.sort(reverse=True, key=lambda x: (x[0], x[1], x[2], x[3]))

    for _, _, _, _, prof in scored:
        try:
            bond = refresh_bond_required_for_tier(int(prof.user_id), prof.reputation_tier)
        except Exception:
            bond = get_or_create_bond(int(prof.user_id), tier=prof.reputation_tier)

        required = float(bond.bond_required_amount or required_amount_for_tier(prof.reputation_tier))
        if reserve_for_inspection(int(prof.user_id), int(order.id), required):
            return int(prof.user_id)

    return None


@inspections_bp.post("/orders/<int:order_id>/inspection/request")
def request_inspection(order_id: int):
    """Buyer requests inspection for an already-paid order.

    This is the retroactive gate you specified: it can be triggered from paid history.
    """
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (_is_admin(u) or int(o.buyer_id) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    # Require payment signal. In this MVP, payment_reference presence is the indicator.
    if not (o.payment_reference or "").strip():
        return jsonify({"message": "Order must be paid (payment_reference missing)"}), 400
    if not _availability_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409
    if (o.fulfillment_mode or "unselected") != "inspection":
        return jsonify({"message": "Fulfillment mode must be inspection"}), 409

    if (o.inspection_status or "NONE") not in ("NONE", "PENDING"):
        return jsonify({"message": "Inspection already in progress or closed", "order": o.to_dict()}), 409

    payload = request.get_json(silent=True) or {}

    o.inspection_required = True
    try:
        fee = float(payload.get("inspection_fee") or 0.0)
    except Exception:
        fee = 0.0
    if fee < 0:
        fee = 0.0
    try:
        o.inspection_fee = float(fee)
    except Exception:
        pass
    o.inspection_status = "PENDING"
    o.inspection_outcome = "NONE"
    o.inspection_requested_at = _now()
    o.release_condition = "INSPECTION_PASS"

    if o.escrow_status == "NONE":
        _hold_order_into_escrow(o)

    if not o.inspector_id:
        picked = _assign_inspector(o)
        if picked:
            try:
                # Atomic assignment (prevents double-accept / race overwrites)
                updated = (
                    db.session.query(Order)
                    .filter(Order.id == int(o.id))
                    .filter(Order.inspector_id.is_(None))
                    .update({Order.inspector_id: int(picked)})
                )
                if updated:
                    o.inspector_id = int(picked)
            except Exception:
                db.session.rollback()
    try:
        buyer = User.query.get(int(o.buyer_id)) if o.buyer_id else None
        seller = User.query.get(int(o.merchant_id)) if o.merchant_id else None
        inspector = User.query.get(int(o.inspector_id)) if o.inspector_id else None
        prof = InspectorProfile.query.filter_by(user_id=int(o.inspector_id)).first() if o.inspector_id else None
        inspector_phone = ""
        if prof and getattr(prof, "phone", None):
            inspector_phone = prof.phone
        elif inspector and getattr(inspector, "phone", None):
            inspector_phone = inspector.phone

        ticket = InspectionTicket.query.filter_by(order_id=int(o.id)).first()
        if not ticket:
            ticket = InspectionTicket(
                order_id=int(o.id),
                inspector_id=int(o.inspector_id) if o.inspector_id else None,
                seller_phone=(getattr(seller, "phone", None) or ""),
                seller_address=(o.pickup or ""),
                item_summary=f"Order #{int(o.id)} inspection",
                buyer_full_name=(buyer.name if buyer else ""),
                buyer_phone=(getattr(buyer, "phone", None) if buyer else ""),
                status="created",
            )
            db.session.add(ticket)

        unlock = ensure_unlock(int(o.id), "inspection_inspector")
        code = set_code_if_missing(unlock, int(o.id), "inspection_inspector")
        if code and buyer:
            msg = f"FlipTrybe: Inspector code for Order #{int(o.id)} is {code}. Share only with the inspector."
            queue_sms(int(buyer.id), "FlipTrybe", msg, meta={"order_id": int(o.id)})
            queue_whatsapp(int(buyer.id), "FlipTrybe", msg, meta={"order_id": int(o.id)})
        if inspector and buyer:
            msg_buyer = f"FlipTrybe: Inspector {inspector.name or ''} assigned for Order #{int(o.id)}."
            if inspector_phone:
                msg_buyer += f" Phone: {inspector_phone}"
            queue_sms(int(buyer.id), "FlipTrybe", msg_buyer, meta={"order_id": int(o.id)})
        if inspector and seller:
            msg_seller = f"FlipTrybe: Inspector {inspector.name or ''} assigned for Order #{int(o.id)}."
            if inspector_phone:
                msg_seller += f" Phone: {inspector_phone}"
            queue_sms(int(seller.id), "FlipTrybe", msg_seller, meta={"order_id": int(o.id)})
        db.session.add(unlock)
    except Exception:
        pass
    o.updated_at = _now()
    db.session.add(o)
    db.session.commit()
    _event(int(o.id), int(u.id), "inspection_requested", "Inspection requested")

    return jsonify({"ok": True, "order": o.to_dict()}), 200


@inspections_bp.post("/inspections/<int:order_id>/status")
def update_inspection_status(order_id: int):
    """Inspector updates status: ON_MY_WAY -> ARRIVED -> INSPECTED.

    Strict no-skip enforcement.
    """
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (_is_admin(u) or (o.inspector_id and int(o.inspector_id) == int(u.id))):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    next_status = (payload.get("status") or "").strip().upper()
    if next_status not in ("ON_MY_WAY", "ARRIVED", "INSPECTED"):
        return jsonify({"message": "status must be one of ON_MY_WAY, ARRIVED, INSPECTED"}), 400

    current = (o.inspection_status or "NONE").upper()
    allowed_next = {
        "PENDING": "ON_MY_WAY",
        "ON_MY_WAY": "ARRIVED",
        "ARRIVED": "INSPECTED",
    }

    if current not in allowed_next or allowed_next[current] != next_status:
        return jsonify({"message": f"Invalid transition {current} -> {next_status}"}), 409

    o.inspection_status = next_status
    if next_status == "ON_MY_WAY":
        o.inspection_on_my_way_at = _now()
    if next_status == "ARRIVED":
        o.inspection_arrived_at = _now()
    if next_status == "INSPECTED":
        o.inspection_inspected_at = _now()

    o.updated_at = _now()
    db.session.add(o)
    db.session.commit()
    status_event = f"inspection_{next_status.lower()}"
    _event(int(o.id), int(u.id), status_event, f"Inspection status {next_status}")
    return jsonify({"ok": True, "order": o.to_dict()}), 200


@inspections_bp.post("/inspector/tickets/<int:ticket_id>/complete")
def complete_inspection_ticket(ticket_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    ticket = InspectionTicket.query.get(int(ticket_id))
    if not ticket:
        return jsonify({"message": "Not found"}), 404

    o = Order.query.get(int(ticket.order_id))
    if not o:
        return jsonify({"message": "Order not found"}), 404

    if not (_is_admin(u) or (o.inspector_id and int(o.inspector_id) == int(u.id))):
        return jsonify({"message": "Forbidden"}), 403

    if not _availability_confirmed(int(o.id)):
        return jsonify({"message": "Availability confirmation required"}), 409

    unlock = EscrowUnlock.query.filter_by(order_id=int(o.id), step="inspection_inspector").first()
    if not unlock:
        return jsonify({"message": "Inspection unlock not initialized"}), 409
    if unlock.locked:
        return jsonify({"message": "Inspection code locked. Contact admin."}), 423
    if unlock.expires_at and datetime.utcnow() > unlock.expires_at:
        return jsonify({"message": "Inspection code expired"}), 409
    if unlock.qr_required and not unlock.qr_verified:
        return jsonify({"message": "QR scan required before inspection completion"}), 409

    payload = request.get_json(silent=True) or {}
    code = (payload.get("code") or "").strip()

    if not verify_code(unlock, int(o.id), "inspection_inspector", code):
        allowed = bump_attempts(unlock)
        try:
            db.session.add(unlock)
            db.session.commit()
        except Exception:
            db.session.rollback()
        if not allowed:
            return jsonify({"message": "Inspection code locked. Contact admin."}), 423
        return jsonify({"message": "Invalid inspection code"}), 400

    unlock.unlocked_at = datetime.utcnow()
    ticket.status = "completed"
    o.inspection_status = "INSPECTED"
    if not o.inspection_inspected_at:
        o.inspection_inspected_at = _now()
    o.updated_at = _now()

    try:
        release_inspector_payout(o)
        db.session.add(unlock)
        db.session.add(ticket)
        db.session.add(o)
        db.session.commit()
        _event(int(o.id), int(u.id), "inspection_complete", "Inspection complete (QR + code)")
        return jsonify({"ok": True, "ticket": ticket.to_dict(), "order": o.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@inspections_bp.post("/inspections/<int:order_id>/outcome")
def submit_inspection_outcome(order_id: int):
    """Inspector submits PASS/FAIL/FRAUD.

    Evidence requirements:
      - For FAIL/FRAUD: require >=1 evidence URL + note.
    """
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (_is_admin(u) or (o.inspector_id and int(o.inspector_id) == int(u.id))):
        return jsonify({"message": "Forbidden"}), 403

    if (o.inspection_status or "NONE").upper() != "INSPECTED":
        return jsonify({"message": "Inspector must set status INSPECTED before outcome"}), 409

    payload = request.get_json(silent=True) or {}
    outcome = (payload.get("outcome") or "").strip().upper()
    if outcome not in ("PASS", "FAIL", "FRAUD"):
        return jsonify({"message": "outcome must be PASS, FAIL, or FRAUD"}), 400

    evidence = payload.get("evidence_urls")
    note = (payload.get("note") or "").strip()

    # Normalize evidence into JSON string
    urls = []
    if isinstance(evidence, list):
        urls = [str(x).strip() for x in evidence if str(x).strip()]
    elif isinstance(evidence, str) and evidence.strip():
        urls = [evidence.strip()]

    if outcome in ("FAIL", "FRAUD"):
        if len(urls) < 1:
            return jsonify({"message": "Evidence required: provide at least 1 photo/video URL"}), 409
        if len(note) < 3:
            return jsonify({"message": "Note required for FAIL/FRAUD"}), 409

    o.inspection_outcome = outcome
    o.inspection_evidence_urls = json.dumps(urls)
    o.inspection_note = note[:400]
    o.inspection_status = "CLOSED"
    o.inspection_closed_at = _now()
    o.updated_at = _now()

    # Update inspector counters
    if o.inspector_id:
        prof = InspectorProfile.query.filter_by(user_id=int(o.inspector_id)).first()
        if prof:
            prof.completed_inspections = int(prof.completed_inspections or 0) + 1
            if outcome == "FAIL":
                prof.failed_inspections = int(prof.failed_inspections or 0) + 1
            if outcome == "FRAUD":
                prof.fraud_flags = int(prof.fraud_flags or 0) + 1
            prof.updated_at = _now()
            db.session.add(prof)

    db.session.add(o)
    db.session.commit()
    _event(int(o.id), int(u.id), "inspection_closed", f"Inspection outcome {outcome}")

    if outcome == "PASS" and o.inspector_id:
        try:
            release_for_inspection(int(o.inspector_id), int(o.id))
        except Exception:
            pass

    # Trigger escrow automation for this order category.
    # This keeps the system moving without admin babysitting.
    _ = run_escrow_automation(limit=50)

    return jsonify({"ok": True, "order": o.to_dict()}), 200


@inspections_bp.post("/inspections/<int:order_id>/review")
def create_inspection_review(order_id: int):
    """Buyer leaves a rating after inspection closes."""
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404
    if not (_is_admin(u) or int(o.buyer_id) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    if (o.inspection_status or "NONE").upper() != "CLOSED":
        return jsonify({"message": "Inspection must be CLOSED before review"}), 409
    if not o.inspector_id:
        return jsonify({"message": "No inspector assigned"}), 400

    payload = request.get_json(silent=True) or {}
    try:
        rating = int(payload.get("rating") or 5)
    except Exception:
        rating = 5
    rating = max(1, min(5, rating))
    tags = payload.get("tags")
    comment = (payload.get("comment") or "").strip()

    existing = InspectionReview.query.filter_by(order_id=int(o.id), reviewer_user_id=int(u.id)).first()
    if existing:
        return jsonify({"message": "Review already exists", "review": existing.to_dict()}), 409

    rev = InspectionReview(
        order_id=int(o.id),
        inspector_user_id=int(o.inspector_id),
        reviewer_user_id=int(u.id),
        rating=rating,
        tags_json=json.dumps(tags or []),
        comment=comment[:400],
    )

    db.session.add(rev)

    prof = InspectorProfile.query.filter_by(user_id=int(o.inspector_id)).first()
    if prof:
        prof = _recompute_profile_score(prof, order=o)
        db.session.add(prof)

    db.session.commit()
    if prof:
        try:
            refresh_bond_required_for_tier(int(prof.user_id), prof.reputation_tier)
        except Exception:
            pass
    return jsonify({"ok": True, "review": rev.to_dict(), "inspector_profile": prof.to_dict() if prof else None}), 201


@inspections_bp.post("/inspections/<int:order_id>/audit")
def create_inspection_audit(order_id: int):
    """Admin adjudication. If OVERTURNED, penalize inspector."""
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if not _is_admin(u):
        return jsonify({"message": "Forbidden"}), 403

    o = Order.query.get(order_id)
    if not o:
        return jsonify({"message": "Not found"}), 404
    if not o.inspector_id:
        return jsonify({"message": "No inspector assigned"}), 400

    payload = request.get_json(silent=True) or {}
    decision = (payload.get("decision") or "UPHELD").strip().upper()
    if decision not in ("UPHELD", "OVERTURNED"):
        return jsonify({"message": "decision must be UPHELD or OVERTURNED"}), 400
    reason = (payload.get("reason") or "").strip()

    aud = InspectionAudit(
        order_id=int(o.id),
        inspector_user_id=int(o.inspector_id),
        admin_user_id=int(u.id),
        decision=decision,
        reason=reason[:400],
    )
    db.session.add(aud)

    prof = InspectorProfile.query.filter_by(user_id=int(o.inspector_id)).first()
    if prof:
        prof.dispute_audit_count = int(prof.dispute_audit_count or 0) + 1
        if decision == "OVERTURNED":
            prof.dispute_overturned_count = int(prof.dispute_overturned_count or 0) + 1
        prof = _recompute_profile_score(prof, order=o)
        db.session.add(prof)

    db.session.commit()
    if prof:
        try:
            refresh_bond_required_for_tier(int(prof.user_id), prof.reputation_tier)
        except Exception:
            pass

    outcome = (o.inspection_outcome or "NONE").upper()
    if prof and outcome in ("FAIL", "FRAUD"):
        if decision == "OVERTURNED":
            try:
                slash_for_audit(int(prof.user_id), int(aud.id), int(o.id), tier=prof.reputation_tier)
            except Exception:
                pass
        if decision == "UPHELD":
            try:
                release_for_inspection(int(prof.user_id), int(o.id))
            except Exception:
                pass
    return jsonify({"ok": True, "audit": aud.to_dict(), "inspector_profile": prof.to_dict() if prof else None}), 201


@inspections_bp.get("/inspectors/me/profile")
def my_inspector_profile():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    prof = InspectorProfile.query.filter_by(user_id=int(u.id)).first()
    if not prof:
        # auto-provision if the user is an inspector or admin
        if _role(u) not in ("inspector", "admin"):
            return jsonify({"message": "Not an inspector"}), 403
        prof = InspectorProfile(user_id=int(u.id), is_active=True)
        db.session.add(prof)
        db.session.commit()
    return jsonify({"ok": True, "profile": prof.to_dict()}), 200


@inspections_bp.post("/inspectors/me/profile")
def update_inspector_profile():
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401
    if _role(u) not in ("inspector", "admin"):
        return jsonify({"message": "Not an inspector"}), 403

    payload = request.get_json(silent=True) or {}
    prof = InspectorProfile.query.filter_by(user_id=int(u.id)).first()
    if not prof:
        prof = InspectorProfile(user_id=int(u.id), is_active=True)

    incoming_phone = (payload.get("phone") or prof.phone or "").strip()
    if incoming_phone:
        try:
            dup_users = flag_duplicate_phone(int(u.id), incoming_phone)
            if dup_users:
                return jsonify({"message": "Phone already in use by another account"}), 409
        except Exception:
            pass
    prof.phone = incoming_phone

    region = (payload.get("region") or prof.region or "").strip()
    if region:
        prof.region = region

    prof.updated_at = _now()

    try:
        db.session.add(prof)
        db.session.commit()
        return jsonify({"ok": True, "profile": prof.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@inspections_bp.post("/admin/escrow/run")
def run_escrow():
    """Manual trigger for escrow automation.

    Useful for Render cron or admin panel.
    """
    # Option A: Allow Render Cron using a service token.
    # If provided and valid, do NOT require JWT user auth.
    cron_secret = (os.getenv("ESCROW_CRON_TOKEN") or "").strip()
    bearer = _bearer_token()  # reads Authorization: Bearer <...>

    if cron_secret and bearer and hmac.compare_digest(bearer, cron_secret):
        pass
    else:
        # Fallback: Admin JWT only (existing behavior)
        u = _current_user()
        if not u:
            return jsonify({"message": "Unauthorized"}), 401
        if not _is_admin(u):
            return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    try:
        limit = int(payload.get("limit") or 500)
    except Exception:
        limit = 500
    return jsonify(run_escrow_automation(limit=limit)), 200


_debug_segments = (os.getenv("FLIPTRYBE_DEBUG_SEGMENTS") or "").strip().lower()
if _debug_segments in ("1", "true", "yes", "y", "on"):
    print("Segment Loaded: Inspector Agent Mode + Escrow Hooks")
