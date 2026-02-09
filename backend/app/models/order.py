from datetime import datetime

from app.extensions import db


class Order(db.Model):
    __tablename__ = "orders"

    id = db.Column(db.Integer, primary_key=True)

    buyer_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    merchant_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)

    listing_id = db.Column(db.Integer, db.ForeignKey("listings.id"), nullable=True, index=True)

    amount = db.Column(db.Float, nullable=False, default=0.0)
    delivery_fee = db.Column(db.Float, nullable=False, default=0.0)
    inspection_fee = db.Column(db.Float, nullable=False, default=0.0)

    pickup = db.Column(db.String(200), nullable=True)
    dropoff = db.Column(db.String(200), nullable=True)

    status = db.Column(db.String(32), nullable=False, default="created")
    # created -> paid -> merchant_accepted -> driver_assigned -> picked_up -> delivered -> completed
    # can also be cancelled
    fulfillment_mode = db.Column(db.String(16), nullable=False, default="unselected")

    payment_reference = db.Column(db.String(80), nullable=True, index=True)
    seed_key = db.Column(db.String(64), nullable=True, unique=True, index=True)
    handshake_id = db.Column(db.String(64), nullable=True, index=True)

    driver_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)

    # =====================================================
    # DELIVERY SECRET CODES (Seller ↔ Driver ↔ Buyer)
    # =====================================================
    pickup_code = db.Column(db.String(8), nullable=True)
    dropoff_code = db.Column(db.String(8), nullable=True)
    pickup_code_attempts = db.Column(db.Integer, nullable=False, default=0)
    dropoff_code_attempts = db.Column(db.Integer, nullable=False, default=0)
    pickup_confirmed_at = db.Column(db.DateTime, nullable=True)
    dropoff_confirmed_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    # =====================================================
    # ESCROW + INSPECTION (Inspector Agent Mode)
    # =====================================================
    # Escrow primitives
    escrow_status = db.Column(
        db.String(16),
        nullable=False,
        default="NONE",
        index=True,
    )
    escrow_hold_amount = db.Column(db.Float, nullable=False, default=0.0)
    escrow_currency = db.Column(db.String(8), nullable=False, default="NGN")
    escrow_held_at = db.Column(db.DateTime, nullable=True)
    escrow_release_at = db.Column(db.DateTime, nullable=True)
    escrow_refund_at = db.Column(db.DateTime, nullable=True)
    escrow_disputed_at = db.Column(db.DateTime, nullable=True)

    # Release policy
    release_condition = db.Column(
        db.String(24),
        nullable=False,
        default="INSPECTION_PASS",
    )
    release_timeout_hours = db.Column(db.Integer, nullable=False, default=48)

    # Inspection gate
    inspection_required = db.Column(db.Boolean, nullable=False, default=False)
    inspection_status = db.Column(
        db.String(24),
        nullable=False,
        default="NONE",
        index=True,
    )
    # NONE | PENDING | ON_MY_WAY | ARRIVED | INSPECTED | CLOSED
    inspection_outcome = db.Column(
        db.String(16),
        nullable=False,
        default="NONE",
        index=True,
    )
    # NONE | PASS | FAIL | FRAUD

    inspector_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)

    inspection_requested_at = db.Column(db.DateTime, nullable=True)
    inspection_on_my_way_at = db.Column(db.DateTime, nullable=True)
    inspection_arrived_at = db.Column(db.DateTime, nullable=True)
    inspection_inspected_at = db.Column(db.DateTime, nullable=True)
    inspection_closed_at = db.Column(db.DateTime, nullable=True)

    # Evidence bundle (JSON string of URLs) + note
    inspection_evidence_urls = db.Column(db.Text, nullable=True)
    inspection_note = db.Column(db.String(400), nullable=True)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "buyer_id": int(self.buyer_id),
            "merchant_id": int(self.merchant_id),
            "listing_id": int(self.listing_id) if self.listing_id is not None else None,
            "amount": float(self.amount or 0.0),
            "delivery_fee": float(self.delivery_fee or 0.0),
            "inspection_fee": float(self.inspection_fee or 0.0),
            "pickup": self.pickup or "",
            "dropoff": self.dropoff or "",
            "status": self.status,
            "fulfillment_mode": self.fulfillment_mode or "unselected",
            "payment_reference": self.payment_reference or "",
            "handshake_id": self.handshake_id or "",
            "driver_id": int(self.driver_id) if self.driver_id is not None else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,

            "escrow_status": self.escrow_status,
            "escrow_hold_amount": float(self.escrow_hold_amount or 0.0),
            "escrow_currency": self.escrow_currency,
            "escrow_held_at": self.escrow_held_at.isoformat() if self.escrow_held_at else None,
            "escrow_release_at": self.escrow_release_at.isoformat() if self.escrow_release_at else None,
            "escrow_refund_at": self.escrow_refund_at.isoformat() if self.escrow_refund_at else None,
            "escrow_disputed_at": self.escrow_disputed_at.isoformat() if self.escrow_disputed_at else None,
            "release_condition": self.release_condition,
            "release_timeout_hours": int(self.release_timeout_hours or 0),

            "inspection_required": bool(self.inspection_required),
            "inspection_status": self.inspection_status,
            "inspection_outcome": self.inspection_outcome,
            "inspector_id": int(self.inspector_id) if self.inspector_id is not None else None,
            "inspection_requested_at": self.inspection_requested_at.isoformat() if self.inspection_requested_at else None,
            "inspection_on_my_way_at": self.inspection_on_my_way_at.isoformat() if self.inspection_on_my_way_at else None,
            "inspection_arrived_at": self.inspection_arrived_at.isoformat() if self.inspection_arrived_at else None,
            "inspection_inspected_at": self.inspection_inspected_at.isoformat() if self.inspection_inspected_at else None,
            "inspection_closed_at": self.inspection_closed_at.isoformat() if self.inspection_closed_at else None,
            "inspection_evidence_urls": self.inspection_evidence_urls or "[]",
            "inspection_note": self.inspection_note or "",
        }
