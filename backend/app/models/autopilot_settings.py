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
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
