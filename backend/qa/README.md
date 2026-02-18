QA Runner for FlipTrybe backend

How to run

- From backend root (Windows PowerShell):

```powershell
.\.venv\Scripts\Activate.ps1
$env:FLASK_APP="main.py"
python -m flask db upgrade
.\qa\qa_run.ps1
```

What it does
- Runs migrations
- Starts the Flask server in background
- Calls `/api/health`
- Executes a set of regression tests and invariants
- Saves artifacts to `qa/artifacts/qa_run_<timestamp>.log` and DB snapshots

Notes
- The runner uses `.venv\Scripts\python.exe` if no venv is activated.
- If endpoints are missing the runner will log the responses and mark tests accordingly.
# FlipTrybe Backend QA Suite

## Purpose
`qa_run.ps1` runs backend regression + invariants in one command.

## Coverage
- Anti-fraud regression: D, E, F, G
- Happy path: paid -> availability yes -> assigned -> pickup -> delivery -> completed
- Ledger and `/api/admin/reconcile` proof
- Invariants:
  - seller cannot buy own listing
  - follow policy
  - chat policy via support chat routes
  - role switch admin control
  - idempotency/replay safety

## Run
From `backend` root:

```powershell
.\qa\qa_run.ps1
```

Exit codes:
- `0` all checks pass
- `1` one or more checks fail
- `2` runner exception

## Artifacts
Logs are saved in:

- `qa/artifacts/qa_run_<timestamp>.log`

Additional server stdout/stderr logs are also written in `qa/artifacts`.

## Notes
- Runner executes `python -m flask db upgrade` first.
- Runner starts a local server process (`python main.py`) and stops it in `finally`.
- Fresh random emails are generated every run to prevent collisions.
