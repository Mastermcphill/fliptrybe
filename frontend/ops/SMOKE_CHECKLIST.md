# Frontend Smoke Checklist

Run this checklist after major UI refactors and before release.

## Preconditions
- App launches successfully on a fresh install/session.
- Backend/test environment is reachable.
- At least one user account exists for buyer and admin.

## Checklist
1. Login and logout flow
- Open app to landing screen.
- Tap `Login` and sign in with a valid account.
- Confirm role shell loads.
- Sign out.
- Confirm landing/login CTAs remain responsive immediately after logout.

2. Browse feed
- Open marketplace/feed.
- Verify loading state, data state, and empty/error state render correctly.
- Scroll through multiple cards and open/close filters.

3. Open listing
- Open a listing details page from browse/search.
- Confirm price/media/details render.
- Navigate back to list without UI freeze.

4. Create order (if enabled in current environment)
- From a listing, place an order/check out.
- Confirm success/confirmation UI appears.
- Verify order is visible in orders history screen.

5. Admin screens + signout
- Login as admin.
- Open Admin shell tabs (Overview, Operations, Queue, Support, Settings).
- Open at least one detail screen from each main tab.
- Sign out from admin and confirm redirect to login/landing.

## Pass Criteria
- No dead buttons.
- No unrecoverable loading spinners.
- No route dead-ends.
- No visual overflow/crash during main navigation path.
