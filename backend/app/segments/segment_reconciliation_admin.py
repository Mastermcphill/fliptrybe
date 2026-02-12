from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.utils.reconciliation import reconcile_latest
from app.utils.jwt_utils import decode_token
from app.models import User, ReconciliationReport
from app.services.reconciliation_service import recompute_wallet_balances, persist_report

recon_bp = Blueprint("recon_bp", __name__, url_prefix="/api/admin/reconcile")


def _bearer():
    h = request.headers.get("Authorization", "")
    if not h.startswith("Bearer "):
        return None
    return h.replace("Bearer ", "", 1).strip()


def _current_user():
    tok = _bearer()
    if not tok:
        return None
    payload = decode_token(tok)
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


@recon_bp.post("")
def run_recon():
    u = _current_user()
    if not u or (u.role or "") != "admin":
        return jsonify({"message": "Admin required"}), 403
    data = request.get_json(silent=True) or {}
    limit = int(data.get("limit") or 200)
    mode = (data.get("mode") or "legacy").strip().lower()
    if mode == "wallet_ledger":
        since = (data.get("since") or "").strip() or None
        summary = recompute_wallet_balances(since=since)
        persist = bool(data.get("persist", True))
        report_id = None
        if persist:
            report = persist_report(summary, created_by=int(u.id))
            report_id = int(report.id)
        return jsonify({"ok": True, "mode": "wallet_ledger", "report_id": report_id, "summary": summary}), 200
    res = reconcile_latest(limit=limit)
    return jsonify(res), 200


@recon_bp.get("/latest")
def latest_report():
    u = _current_user()
    if not u or (u.role or "") != "admin":
        return jsonify({"message": "Admin required"}), 403
    row = ReconciliationReport.query.order_by(ReconciliationReport.created_at.desc()).first()
    if not row:
        return jsonify({"ok": True, "report": None}), 200
    return jsonify({"ok": True, "report": row.to_dict()}), 200
