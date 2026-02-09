# Flutter -> API wiring audit (2026-02-09)

## Core flows mapping
- Signup Buyer: RoleSignupScreen -> buyer signup screen -> ApiService.register / /api/auth/register
- Signup Merchant/Driver/Inspector: role signup screens -> /api/auth/register/<role>
- Role switch: ApiService -> /api/auth/set-role (admin-only)
- Support chat (admin): SupportTicketsScreen -> /api/support/tickets (admin-only threads via /api/admin/support/*)
- Merchant follow: MerchantService.followMerchant -> POST /api/merchants/<id>/follow
- Merchant unfollow: MerchantService.unfollowMerchant -> DELETE /api/merchants/<id>/follow
- Listings list (marketplace): MarketPlaceScreen -> /api/listings
- Listing detail: ListingDetailPlaceholderScreen (local-only placeholder)
- Shortlets list: ShortletScreen -> /api/shortlets

## Top 5 broken/mismatched flows and fixes
1) Merchant unfollow used /merchants/<id>/unfollow (404)
   - Fix: use DELETE /api/merchants/<id>/follow (implemented).
2) Buyer confirm delivery used /orders/<id>/buyer/confirm (missing)
   - Fix: not used in UI; avoid wiring until backend endpoint exists.
3) Support chat in UI uses support tickets; support chat endpoints are not wired
   - Fix: keep Contact Admin pointing to support tickets (working).
4) Shortlets tile sometimes routed to Coming Soon screen
   - Fix: ensure tiles route to ShortletScreen or placeholder.
5) Listing taps must always navigate
   - Fix: Marketplace/Shortlet/merchant listings already route to ListingDetailPlaceholderScreen.

## Notes
- Self-buy guard exists on backend (orders create).
- Merchant follow rules enforced on backend (buyers only).
