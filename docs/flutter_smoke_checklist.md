# Flutter Smoke Checklist

## Guest
- Open app to landing.
- Tap `Browse Marketplace` and `Browse Shortlets` without login.
- Verify feeds load, skeletons/empty states render correctly.
- Verify appearance toggle is reachable and persists.

## Buyer
- Signup -> login -> logout -> login again.
- Browse marketplace, use search, open listing detail.
- Create a listing immediately after registration (no verify prompts in flow).
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
- In support chat, send a message with a phone/email; verify server blocks with contact-sharing error.

## Marketplace Governance
- As buyer, attempt to save listing description containing phone/email/address; verify save is blocked with guidance text.
- As merchant, create listing without customer payout profile; verify required-field error.
- As merchant, create listing with complete customer payout profile and confirm publish succeeds.
- As admin, open customer payout profile from Admin Marketplace and use copy action.

## Real Estate
- Create each listing type: House for Rent, House for Sale, Land for Sale.
- Filter by property type and location.
- Filter house listings by bedrooms/bathrooms/furnished/serviced.
- Filter land listings by land size and title document type.

## Admin
- Login as admin.
- Open: Hub, System Health, Support Threads, Payout Console, Feature Flags.
- Process one payout action and verify visible outcome.
- Sign out; ensure nav stack resets to auth.

## Theme + Accessibility
- Validate light/dark readability on key screens.
- Validate no vertical title rendering on narrow device width.
- Validate disabled actions show reason text and do not dead-tap.
