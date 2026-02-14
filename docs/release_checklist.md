# FlipTrybe Release Checklist

## Preflight
- Confirm branch is `main` and working tree is clean.
- Confirm API base URL is production-safe for release builds.
- Confirm signing config exists (`frontend/android/key.properties`).

## Quality Gates
1. `cd frontend`
2. `flutter pub get`
3. `flutter test`
4. `flutter analyze` (report-only baseline tracking)

## Build Artifacts
1. `flutter build apk --release`
2. `flutter build appbundle --release`
3. `flutter build windows --release`

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

## Rollout
- Upload AAB to Play Console (Internal/Closed track)
- Publish release notes
- Monitor crash-free sessions and support queue for 24 hours
