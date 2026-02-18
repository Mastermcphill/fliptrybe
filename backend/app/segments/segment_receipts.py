from __future__ import annotations

from flask import Blueprint, jsonify, request, send_file

from app.extensions import db
from app.models import User, Receipt
from app.utils.jwt_utils import decode_token
from app.utils.receipt_pdf import render_receipt_pdf

receipts_bp = Blueprint("receipts_bp", __name__, url_prefix="/api")

_RECEIPTS_INIT_DONE = False


@receipts_bp.before_app_request
def _ensure_tables_once():
    global _RECEIPTS_INIT_DONE
    if _RECEIPTS_INIT_DONE:
        return
    try:
        db.create_all()
    except Exception:
        pass
    _RECEIPTS_INIT_DONE = True


def _bearer_token() -> str | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header.replace("Bearer ", "", 1).strip() or None


def _current_user():
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
        user_id = int(sub)
    except Exception:
        return None
    return User.query.get(user_id)


@receipts_bp.get("/receipts")
def list_receipts():
    user = _current_user()
    if not user:
        return jsonify({"message": "Unauthorized"}), 401

    rows = Receipt.query.filter_by(user_id=user.id).order_by(Receipt.created_at.desc()).limit(80).all()
    return jsonify({"ok": True, "items": [x.to_dict() for x in rows]}), 200


@receipts_bp.get("/receipts/<int:receipt_id>/pdf")
def receipt_pdf(receipt_id: int):
    user = _current_user()
    if not user:
        return jsonify({"message": "Unauthorized"}), 401

    rec = Receipt.query.get(receipt_id)
    if not rec or int(rec.user_id or 0) != int(user.id or 0):
        return jsonify({"message": "Receipt not found"}), 404

    pdf_bytes = render_receipt_pdf(rec.to_dict())
    # Flask send_file from memory
    import io
    return send_file(
        io.BytesIO(pdf_bytes),
        mimetype="application/pdf",
        as_attachment=False,
        download_name=f"fliptrybe_receipt_{receipt_id}.pdf",
    )
