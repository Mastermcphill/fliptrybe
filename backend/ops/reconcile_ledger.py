from __future__ import annotations

import argparse
import json
import os
import sys


def _bootstrap_app():
    from app import create_app

    app = create_app()
    app.app_context().push()
    return app


def main():
    parser = argparse.ArgumentParser(description="Recompute wallet balances from ledger and report drift.")
    parser.add_argument("--since", default="", help="Optional since marker for report metadata.")
    parser.add_argument("--persist", action="store_true", help="Persist report row in reconciliation_reports.")
    args = parser.parse_args()

    _bootstrap_app()
    from app.services.reconciliation_service import recompute_wallet_balances, persist_report

    summary = recompute_wallet_balances(since=(args.since or None))
    if args.persist:
        row = persist_report(summary, created_by=None)
        summary["report_id"] = int(row.id)

    print(json.dumps(summary, indent=2))
    drift_count = int(summary.get("drift_count") or 0)
    return 0 if drift_count == 0 else 2


if __name__ == "__main__":
    os.environ.setdefault("FLASK_APP", "main.py")
    sys.exit(main())
