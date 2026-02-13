from __future__ import annotations

from datetime import datetime

from app.extensions import db
from app.models import JobRun


def record_job_run(*, job_name: str, ok: bool, started_at: datetime, error: str | None = None) -> JobRun | None:
    duration_ms: int | None = None
    try:
        duration_ms = max(0, int((datetime.utcnow() - started_at).total_seconds() * 1000))
    except Exception:
        duration_ms = None
    try:
        row = JobRun(
            job_name=(job_name or "unknown").strip()[:64],
            ran_at=datetime.utcnow(),
            ok=bool(ok),
            duration_ms=duration_ms,
            error=(error or "")[:1000] or None,
        )
        db.session.add(row)
        db.session.commit()
        return row
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
        return None
