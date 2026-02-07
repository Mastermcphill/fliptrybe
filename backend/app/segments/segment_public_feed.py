from __future__ import annotations

from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request, current_app
from sqlalchemy.exc import InternalError, SQLAlchemyError

from app.extensions import db
from app.models import OrderEvent, Order, Listing


public_bp = Blueprint("public_bp", __name__, url_prefix="/api/public")


@public_bp.get("/sales_ticker")
def sales_ticker():
    """Public, non-PII sales confirmations for the landing page ticker."""
    try:
        limit = int(request.args.get("limit", 8))
    except Exception:
        limit = 8
    limit = max(1, min(limit, 20))

    try:
        current_app.logger.info("sales_ticker_hit limit=%s", limit)
    except Exception:
        pass

    def _run_query() -> list[dict]:
        # Only show very recent confirmations (keeps it believable)
        cutoff = datetime.utcnow() - timedelta(days=14)

        rows = (
            OrderEvent.query
            .filter(OrderEvent.event == "paid")
            .filter(OrderEvent.created_at >= cutoff)
            .order_by(OrderEvent.created_at.desc())
            .limit(limit)
            .all()
        )

        items = []
        for e in rows:
            try:
                o = Order.query.get(int(e.order_id))
                if not o:
                    continue
                title = "Item"
                state = getattr(o, "state", None) or ""
                city = getattr(o, "city", None) or ""
                try:
                    lst = Listing.query.get(int(o.listing_id)) if getattr(o, "listing_id", None) else None
                    if lst and (lst.title or ""):
                        title = (lst.title or "Item").strip()
                except Exception:
                    pass
                try:
                    amt = float(getattr(o, "amount", 0.0) or 0.0)
                except Exception:
                    amt = 0.0

                items.append({
                    "item": title,
                    "city": city.strip() or None,
                    "state": state.strip() or None,
                    "amount": amt,
                    "paid": True,
                    "created_at": e.created_at.isoformat() if e.created_at else None,
                })
            except Exception:
                continue
        return items

    try:
        try:
            db.session.rollback()
        except Exception:
            pass
        items = _run_query()
        return jsonify({"ok": True, "items": items}), 200
    except InternalError as e:
        msg = str(e)
        if "InFailedSqlTransaction" in msg:
            try:
                db.session.rollback()
            except Exception:
                pass
            try:
                items = _run_query()
                return jsonify({"ok": True, "items": items}), 200
            except Exception:
                pass
        try:
            db.session.rollback()
        except Exception:
            pass
        try:
            current_app.logger.exception("sales_ticker_error")
        except Exception:
            pass
        return jsonify({"ok": True, "items": []}), 200
    except (SQLAlchemyError, Exception):
        try:
            db.session.rollback()
        except Exception:
            pass
        try:
            current_app.logger.exception("sales_ticker_error")
        except Exception:
            pass
        return jsonify({"ok": True, "items": []}), 200
