from datetime import datetime

from app.extensions import db


class ReconciliationReport(db.Model):
    __tablename__ = "reconciliation_reports"

    id = db.Column(db.Integer, primary_key=True)
    scope = db.Column(db.String(64), nullable=False, default="wallet_ledger")
    since = db.Column(db.String(64), nullable=True)
    summary_json = db.Column(db.Text, nullable=True)
    drift_count = db.Column(db.Integer, nullable=False, default=0)
    created_by = db.Column(db.Integer, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            "id": int(self.id),
            "scope": self.scope or "",
            "since": self.since or "",
            "summary_json": self.summary_json or "",
            "drift_count": int(self.drift_count or 0),
            "created_by": int(self.created_by) if self.created_by is not None else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
