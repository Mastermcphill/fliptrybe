# FlipTrybe Ship-Ready Audit Report

## Scope
- Full wiring audit across Flutter + Flask with no feature redesign.
- Focus: dead actions, endpoint contract sync, auth/session stability, predictable API failures, support loop integrity, and release smoke readiness.

## What Works
- Auth/session core paths are live and tested:
  - register/login/me
  - centralized logout (`logoutToLanding`) clears client/session/nav.
- Public discovery endpoints return valid JSON:
  - `/api/public/listings/recommended`
  - `/api/public/listings/search`
  - `/api/public/listings/deals`
  - `/api/public/listings/new_drops`
  - `/api/public/shortlets/recommended`
- Manual payments + admin payout wiring paths are present and tested.
- Admin support reply roundtrip is implemented and tested.
- Frontend no-op callback scan is clean (`onTap: () {}` / `onPressed: () {}`).

## What Was Broken
- API error contract had gaps for unknown API routes (could return non-uniform failures).
- Notification read endpoint accepted only integer path converter; non-persisted/local IDs produced converter-level failure responses.
- Notification local IDs were still attempting backend mark-read calls.
- Legacy admin placeholder screens had visible quality issues (broken evidence URL and malformed currency text).

## What Was Fixed
- Added global JSON error contract for `/api/*`:
  - HTTP exceptions and unhandled exceptions now return JSON with `ok=false`, `error`, `message`, `status`, `trace_id`.
- Hardened notifications read endpoint:
  - `POST /api/notifications/<notification_id>/read` now handles non-numeric IDs deterministically with JSON `404`.
- Frontend notification mark-read sync:
  - Local/demo notification IDs now short-circuit to local success without unnecessary backend call.
- Reduced unauthenticated 401 UX noise:
  - Global “Session expired” feedback now triggers only for requests that actually carried auth headers.
- Updated admin placeholder screens for correctness:
  - fixed broken evidence image URL.
  - corrected malformed bond balance copy.
  - aligned to theme colors.

## What Remains Intentionally Disabled
- Dispute resolution actions.
- Inspector bond suspension actions.
- Driver actions requiring missing order linkage/navigation integration.
- Inspector report submission in environments where workflow is disabled.
- Merchant listing edit/bulk actions where backend workflow is not enabled.

All disabled actions are explicit and user-visible with clear reason text.
