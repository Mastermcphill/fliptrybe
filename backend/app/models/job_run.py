from datetime import datetime

from app.extensions import db


class JobRun(db.Model):
    __tablename__ = "job_runs"

    id = db.Column(db.Integer, primary_key=True)
    job_name = db.Column(db.String(64), nullable=False, index=True)
    ran_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)
    ok = db.Column(db.Boolean, nullable=False, default=True, index=True)
    duration_ms = db.Column(db.Integer, nullable=True)
    error = db.Column(db.Text, nullable=True)

    def to_dict(self) -> dict:
        return {
            "id": int(self.id),
            "job_name": self.job_name or "",
            "ran_at": self.ran_at.isoformat() if self.ran_at else None,
            "ok": bool(self.ok),
            "duration_ms": int(self.duration_ms) if self.duration_ms is not None else None,
            "error": self.error or "",
        }
