# Flutter Smoke Checklist

## Guest
- Open app to landing.
- Tap `Browse Marketplace` and `Browse Shortlets` without login.
- Verify feeds load, skeletons/empty states render correctly.
- Verify appearance toggle is reachable and persists.

## Buyer
- Signup -> login -> logout -> login again.
- Browse marketplace, use search, open listing detail.
- Open notifications inbox and mark one item read.
- Create support ticket.

## Shortlet
- Open shortlet feed.
- Apply a filter and clear it.
- Open shortlet detail and verify CTA state is explicit (live or disabled reason).

## Support Roundtrip
- User creates support ticket.
- Admin opens support threads and replies.
- User sees admin reply in the same thread.

## Admin
- Login as admin.
- Open: Hub, System Health, Support Threads, Payout Console, Feature Flags.
- Process one payout action and verify visible outcome.
- Sign out; ensure nav stack resets to auth.

## Theme + Accessibility
- Validate light/dark readability on key screens.
- Validate no vertical title rendering on narrow device width.
- Validate disabled actions show reason text and do not dead-tap.
