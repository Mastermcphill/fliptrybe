from datetime import datetime
import sqlalchemy as sa

from app.extensions import db


class AutopilotSettings(db.Model):
    __tablename__ = "autopilot_settings"

    id = db.Column(db.Integer, primary_key=True)
    enabled = db.Column(db.Boolean, nullable=False, default=True)

    last_run_at = db.Column(db.DateTime, nullable=True)

    # Nightly jobs
    last_wallet_reconcile_at = db.Column(db.DateTime, nullable=True)

    # Integration toggles (secrets remain env-only)
    payments_provider = db.Column(db.String(24), nullable=False, default="mock", server_default="mock")
    paystack_enabled = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))
    termii_enabled_sms = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))
    termii_enabled_wa = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))
    integrations_mode = db.Column(db.String(24), nullable=False, default="disabled", server_default="disabled")
    payments_mode = db.Column(db.String(32), nullable=False, default="mock", server_default="mock")
    last_paystack_webhook_at = db.Column(db.DateTime, nullable=True)
    payments_mode_changed_at = db.Column(db.DateTime, nullable=True)
    payments_mode_changed_by = db.Column(db.Integer, nullable=True)
    manual_payment_bank_name = db.Column(db.String(120), nullable=False, default="", server_default="")
    manual_payment_account_number = db.Column(db.String(64), nullable=False, default="", server_default="")
    manual_payment_account_name = db.Column(db.String(120), nullable=False, default="", server_default="")
    manual_payment_note = db.Column(db.String(240), nullable=False, default="", server_default="")
    manual_payment_sla_minutes = db.Column(
        db.Integer, nullable=False, default=360, server_default=sa.text("360")
    )
    search_v2_mode = db.Column(db.String(16), nullable=False, default="off", server_default="off")
    payments_allow_legacy_fallback = db.Column(
        db.Boolean, nullable=False, default=False, server_default=sa.text("false")
    )
    otel_enabled = db.Column(db.Boolean, nullable=False, default=False, server_default=sa.text("false"))
    rate_limit_enabled = db.Column(
        db.Boolean, nullable=False, default=True, server_default=sa.text("true")
    )

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": int(self.id),
            "enabled": bool(self.enabled),
            "last_run_at": self.last_run_at.isoformat() if self.last_run_at else None,
            "last_wallet_reconcile_at": self.last_wallet_reconcile_at.isoformat() if self.last_wallet_reconcile_at else None,
            "payments_provider": (self.payments_provider or "mock"),
            "paystack_enabled": bool(self.paystack_enabled),
            "termii_enabled_sms": bool(self.termii_enabled_sms),
            "termii_enabled_wa": bool(self.termii_enabled_wa),
            "integrations_mode": (self.integrations_mode or "disabled"),
            "payments_mode": (self.payments_mode or "mock"),
            "last_paystack_webhook_at": self.last_paystack_webhook_at.isoformat() if self.last_paystack_webhook_at else None,
            "payments_mode_changed_at": self.payments_mode_changed_at.isoformat() if self.payments_mode_changed_at else None,
            "payments_mode_changed_by": int(self.payments_mode_changed_by) if self.payments_mode_changed_by is not None else None,
            "manual_payment_bank_name": (self.manual_payment_bank_name or ""),
            "manual_payment_account_number": (self.manual_payment_account_number or ""),
            "manual_payment_account_name": (self.manual_payment_account_name or ""),
            "manual_payment_note": (self.manual_payment_note or ""),
            "manual_payment_sla_minutes": int(self.manual_payment_sla_minutes or 360),
            "search_v2_mode": (self.search_v2_mode or "off"),
            "payments_allow_legacy_fallback": bool(self.payments_allow_legacy_fallback),
            "otel_enabled": bool(self.otel_enabled),
            "rate_limit_enabled": bool(self.rate_limit_enabled),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
