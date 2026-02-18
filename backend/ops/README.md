# FlipTrybe Ops Smoke Test Suite

Run:
- From backend root: `.ops\ops_run.ps1`

What it does:
- Runs DB upgrade
- Starts server (flask run, no reload)
- Validates health and base API readiness
- Creates fresh users, approves roles
- Creates orders in multiple states
- Runs autopilot tick(s) and validates idempotency
- Exercises notification queue + dead-letter tooling
- Runs timeout endpoints
- Captures DB proofs and writes artifact log

Outputs:
- `ops\artifacts\ops_run_<timestamp>.log`
- PASS/FAIL summary in stdout

Troubleshooting:
- Ensure `TERMII_API_KEY` is unset to force dead-letter paths, or the runner will mark dead-letter as PASS if messages are sent.
- If ports are occupied, the runner will stop any existing listener on 5000.
