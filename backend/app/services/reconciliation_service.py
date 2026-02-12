from __future__ import annotations

import json
from datetime import datetime

from app.extensions import db
from app.models import Wallet, WalletTxn, ReconciliationReport


def _signed_amount(direction: str, amount: float) -> float:
    if (direction or "").strip().lower() == "debit":
        return -abs(float(amount or 0.0))
    return abs(float(amount or 0.0))


def recompute_wallet_balances(*, since: str | None = None, tolerance: float = 0.01) -> dict:
    wallets = Wallet.query.order_by(Wallet.user_id.asc()).all()
    drift_items = []

    for wallet in wallets:
        txns = WalletTxn.query.filter_by(wallet_id=int(wallet.id)).order_by(WalletTxn.created_at.asc()).all()
        computed = 0.0
        for txn in txns:
            computed += _signed_amount(txn.direction, float(txn.amount or 0.0))
        current = float(wallet.balance or 0.0)
        drift = round(current - computed, 4)
        if abs(drift) > float(tolerance):
            drift_items.append(
                {
                    "wallet_id": int(wallet.id),
                    "user_id": int(wallet.user_id),
                    "stored_balance": current,
                    "computed_balance": round(computed, 4),
                    "drift": drift,
                }
            )

    summary = {
        "ok": True,
        "scope": "wallet_ledger",
        "since": since or "",
        "wallet_count": len(wallets),
        "drift_count": len(drift_items),
        "drift_items": drift_items,
        "generated_at": datetime.utcnow().isoformat(),
    }
    return summary


def persist_report(summary: dict, *, created_by: int | None = None) -> ReconciliationReport:
    report = ReconciliationReport(
        scope=(summary.get("scope") or "wallet_ledger")[:64],
        since=(summary.get("since") or "")[:64] or None,
        summary_json=json.dumps(summary)[:200000],
        drift_count=int(summary.get("drift_count") or 0),
        created_by=int(created_by) if created_by is not None else None,
        created_at=datetime.utcnow(),
    )
    db.session.add(report)
    db.session.commit()
    return report
