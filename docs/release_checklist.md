# FlipTrybe Release Checklist

## Preflight
- Confirm branch is `main` and working tree is clean.
- Confirm API base URL is production-safe for release builds.
- Confirm signing config exists (`frontend/android/key.properties`).
- Confirm Render environment variables are set for the target mode:
  - `SECRET_KEY`, `DATABASE_URL`
  - payments/provider toggles and keys (if enabled)
  - notification/media toggles and keys (if enabled)

## Quality Gates
1. `cd frontend`
2. `flutter pub get`
3. `flutter test`
4. `flutter analyze` (report-only baseline tracking)

## Build Artifacts
1. `flutter build apk --release`
2. `flutter build appbundle --release`
3. `flutter build windows --release`

## Backend Validation
1. `cd backend`
2. `python -m unittest discover -s tests -p "test_*.py"`
3. `powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\smoke_render.ps1`
4. `bash ./ops/smoke_render.sh` (bash environments)

## Smoke Flows
- Login + signup (buyer, merchant, inspector pending state)
- Marketplace browse, search, listing detail
- Shortlet browse + detail
- Cart checkout path selection (wallet/paystack/manual)
- Money actions: top-up, withdrawal request, tier upgrade confirmation
- Admin hub + queue + support + system health
- Notification center load, mark-read, empty state

## Observability
- Verify Sentry DSN settings for backend and frontend.
- Verify request IDs appear in failed API snackbars and logs.
- Verify `Report a problem` ticket includes diagnostics payload.

## Release Notes Inputs
- Build version (`pubspec.yaml`)
- Commit SHA (`GIT_SHA`)
- Known limitations / flags

## Render Deployment Notes
- Deploy backend first, then verify:
  - `/api/version` reports expected `git_sha` and `alembic_head`
  - `/api/health` is `ok: true`
- Deploy frontend after backend verification.
- Validate request-id propagation (`X-Request-ID`) on one failing API call.

## Rollback Notes
- Backend rollback: redeploy previous Render commit and run health/version checks.
- Frontend rollback: re-upload previous known-good APK/AAB/Windows artifact.
- If rollback occurs, disable risky runtime flags in admin (`/api/admin/flags`) before reopening traffic.

## Rollout
- Upload AAB to Play Console (Internal/Closed track)
- Publish release notes
- Monitor crash-free sessions and support queue for 24 hours
