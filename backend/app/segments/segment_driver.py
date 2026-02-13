from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from app.extensions import db
from app.models import User, Order, OrderEvent
from app.utils.jwt_utils import decode_token
from app.utils.escrow_unlocks import ensure_unlock, set_code_if_missing
from app.utils.notify import queue_sms, queue_whatsapp
from app.utils.events import log_event

drivers_bp = Blueprint("drivers_bp", __name__, url_prefix="/api/driver")

_INIT_DONE = False


@drivers_bp.before_app_request
def _ensure_tables_once():
    global _INIT_DONE
    if _INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _INIT_DONE = True


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


def _role(u: User | None) -> str:
    if not u:
        return "guest"
    return (getattr(u, "role", None) or "buyer").strip().lower()


def _event(order_id: int, actor_id: int | None, event: str, note: str = "") -> None:
    try:
        key = f"order:{int(order_id)}:{event}:{int(actor_id) if actor_id is not None else 'system'}"
        existing = OrderEvent.query.filter_by(idempotency_key=key[:160]).first()
        if existing:
            return
        e = OrderEvent(
            order_id=order_id,
            actor_user_id=actor_id,
            event=event,
            note=(note or "")[:240],
            idempotency_key=key[:160],
        )
        db.session.add(e)
        db.session.commit()
        mapped = {
            "driver_assigned": "delivery_assigned",
            "picked_up": "delivery_requested",
            "delivered": "delivery_completed",
            "completed": "delivery_completed",
        }.get((event or "").strip().lower())
        if mapped:
            log_event(
                mapped,
                actor_user_id=actor_id,
                subject_type="order",
                subject_id=int(order_id),
                idempotency_key=f"driver_event:{int(order_id)}:{mapped}:{int(actor_id) if actor_id is not None else 'system'}",
                metadata={"event": event, "note": note},
            )
    except Exception:
        db.session.rollback()


def _job_dict(o: Order) -> dict:
    return {
        "id": int(o.id),
        "order_id": int(o.id),
        "pickup": o.pickup or "Pickup",
        "dropoff": o.dropoff or "Dropoff",
        "price": float(o.delivery_fee or 0.0),
        "status": o.status or "",
        "merchant_id": int(o.merchant_id),
        "buyer_id": int(o.buyer_id),
        "driver_id": int(o.driver_id) if o.driver_id is not None else None,
        "amount": float(o.amount or 0.0),
        "delivery_fee": float(o.delivery_fee or 0.0),
        "created_at": o.created_at.isoformat() if o.created_at else None,
        "updated_at": o.updated_at.isoformat() if o.updated_at else None,
    }


@drivers_bp.get("/jobs")
def list_jobs():
    """Driver jobs: returns a flat list of both available jobs and the driver's assigned jobs."""
    u = _current_user()
    if not u:
        return jsonify([]), 200

    r = _role(u)
    if r not in ("driver", "admin"):
        return jsonify([]), 200

    # Available: merchant accepted and no driver yet
    available = (
        Order.query.filter(Order.status == "merchant_accepted", Order.driver_id.is_(None))
        .order_by(Order.created_at.desc())
        .limit(100)
        .all()
    )

    # Mine: assigned or in-progress
    mine = (
        Order.query.filter(Order.driver_id == u.id)
        .order_by(Order.created_at.desc())
        .limit(100)
        .all()
    )

    # Merge without duplicates
    seen = set()
    out = []
    for o in mine + available:
        oid = int(o.id)
        if oid in seen:
            continue
        seen.add(oid)
        out.append(_job_dict(o))

    return jsonify(out), 200


@drivers_bp.post("/jobs/<int:job_id>/accept")

def accept_job(job_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    r = _role(u)
    if r not in ("driver", "admin"):
        return jsonify({"message": "Forbidden"}), 403

    # Load for messaging + responses, but use an atomic update to prevent double-accept race.
    o = Order.query.get(job_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    now = datetime.utcnow()

    # Atomic accept: only one driver can claim the job.
    try:
        updated = (
            db.session.query(Order)
            .filter(
                Order.id == int(job_id),
                Order.driver_id.is_(None),
                (Order.status == "merchant_accepted"),
            )
            .update(
                {
                    Order.driver_id: int(u.id),
                    Order.status: "driver_assigned",
                    Order.updated_at: now,
                },
                synchronize_session=False,
            )
        )
        if updated != 1:
            db.session.rollback()
            # Return precise reason for better UX.
            o2 = Order.query.get(job_id)
            if not o2:
                return jsonify({"message": "Not found"}), 404
            if o2.driver_id is not None:
                return jsonify({"message": "Already assigned", "driver_id": int(o2.driver_id)}), 409
            return jsonify({"message": "Not available"}), 409

        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed to accept job", "error": str(e)}), 500

    # Refresh order after commit for return payload
    o = Order.query.get(job_id)
    try:
        unlock = ensure_unlock(int(o.id), "pickup_seller")
        code = set_code_if_missing(unlock, int(o.id), "pickup_seller")
        if code:
            msg = f"FlipTrybe: Pickup code for Order #{int(o.id)} is {code}. Keep private."
            queue_sms(int(u.id), "FlipTrybe", msg, meta={"order_id": int(o.id)})
            queue_whatsapp(int(u.id), "FlipTrybe", msg, meta={"order_id": int(o.id)})
        db.session.add(unlock)
        db.session.commit()
    except Exception:
        db.session.rollback()
    try:
        _event(o.id, u.id, "driver_assigned", meta={"driver_id": int(u.id)})
    except Exception:
        pass

    return jsonify({"ok": True, "order": o.to_dict()}), 200




@drivers_bp.post("/jobs/<int:job_id>/status")
def update_job_status(job_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    r = _role(u)
    if r not in ("driver", "admin"):
        return jsonify({"message": "Forbidden"}), 403

    o = Order.query.get(job_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if not (o.driver_id and int(o.driver_id) == int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    status = (payload.get("status") or "").strip().lower()

    # allow driver to set picked_up/delivered/completed
    allowed = ("picked_up", "delivered", "completed")
    if status not in allowed:
        return jsonify({"message": "Invalid status"}), 400

    if status in ("delivered", "completed") and (o.escrow_status or "NONE") != "RELEASED":
        return jsonify({"message": "Escrow must be RELEASED before delivery completion"}), 409

    o.status = status
    o.updated_at = datetime.utcnow()

    try:
        if status == "picked_up" and (o.fulfillment_mode or "unselected") == "delivery":
            try:
                unlock = ensure_unlock(int(o.id), "delivery_driver")
                code = set_code_if_missing(unlock, int(o.id), "delivery_driver")
                if code:
                    buyer = User.query.get(int(o.buyer_id))
                    msg = f"FlipTrybe: Delivery code for Order #{int(o.id)} is {code}. Share only with the driver."
                    queue_sms(int(buyer.id), "FlipTrybe", msg, meta={"order_id": int(o.id)})
                    queue_whatsapp(int(buyer.id), "FlipTrybe", msg, meta={"order_id": int(o.id)})
                db.session.add(unlock)
            except Exception:
                pass
        db.session.add(o)
        db.session.commit()
        _event(o.id, u.id, status, f"Driver set status to {status}")
        return jsonify({"ok": True, "job": _job_dict(o)}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"message": "Failed", "error": str(e)}), 500


@drivers_bp.get("/jobs/<int:job_id>")
def get_job(job_id: int):
    u = _current_user()
    if not u:
        return jsonify({"message": "Unauthorized"}), 401

    r = _role(u)
    if r not in ("driver", "admin"):
        return jsonify({"message": "Forbidden"}), 403

    o = Order.query.get(job_id)
    if not o:
        return jsonify({"message": "Not found"}), 404

    if r == "driver" and (not o.driver_id or int(o.driver_id) != int(u.id)):
        return jsonify({"message": "Forbidden"}), 403

    return jsonify(_job_dict(o)), 200
