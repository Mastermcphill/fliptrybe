# UI Wiring Map (Active Shells)

This map covers high-impact screen actions and the bound service/API path.

## Guest/Public
- `LandingScreen`
  - Browse Marketplace -> `MarketplaceScreen` (public discovery service)
  - Browse Shortlets -> `ShortletScreen` (public shortlet discovery)
- `PublicBrowseShell`
  - Marketplace tab -> `GET /api/public/listings/recommended`
  - Shortlet tab -> `GET /api/public/shortlets/recommended`

## Buyer
- `LoginScreen` / `RoleSignupScreen`
  - Submit -> `POST /api/auth/login` / `POST /api/auth/register`
- `MarketplaceScreen`
  - Load feed -> `MarketplaceCatalogService.recommended/newDrops/deals`
  - Search -> `GET /api/public/listings/search`
  - Item tap -> listing detail route
- `ListingDetailScreen`
  - Favorite -> listing favorite endpoint (guarded by auth gate)
  - Buy/Add to cart/checkout actions -> payment/cart flow or explicit disabled reason
- `NotificationsInboxScreen`
  - Load -> `GET /api/notify/inbox` + local cache merge
  - Mark read -> local read + `POST /api/notifications/<id>/read` for persisted IDs
- `SupportTicketsScreen`
  - Create ticket -> `POST /api/support/tickets`
  - List tickets -> `GET /api/support/tickets`
- `ProfileScreen`
  - Appearance -> settings/theme route
  - Sign out -> `logoutToLanding` (client reset + storage clear + nav reset)

## Merchant
- `MerchantHomeScreen`
  - KPIs/listings/orders summary -> merchant service endpoints
  - Autosave controls -> `/api/moneybox/autosave/settings`
  - Withdraw/deposit/tier actions -> moneybox/wallet endpoints
- `MerchantListingsScreen`
  - View listing -> listing detail
  - Edit/Bulk (disabled in this release) -> explicit reason, no dead tap

## Driver
- `DriverHomeScreen`
  - Jobs/Earnings load -> driver services
  - Autosave settings -> `/api/moneybox/autosave/settings`
- `DriverJobsScreen`
  - Timeline/nav actions with missing linkage are disabled with explicit reason

## Inspector
- `InspectorHomeScreen`
  - Bookings/Earnings load -> inspector services
  - Availability update (disabled) -> explicit reason
- `InspectorBookingsScreen`
  - Submit report action disabled where workflow is not enabled, with explicit reason

## Admin
- `AdminHubScreen`
  - Routes to health, support, payouts, flags, analytics, autopilot, omega, marketplace
  - Disabled modules (disputes/bonds) are rendered as disabled rows with reason text
- `AdminSupportThreadsScreen`
  - Thread list -> `GET /api/admin/support/threads`
  - Thread open -> `GET /api/admin/support/threads/<id>/messages`
  - Reply -> `POST /api/admin/support/threads/<id>/messages`
- `AdminPayoutConsoleScreen`
  - Provider payout process -> `POST /api/wallet/payouts/<id>/admin/pay`
- `AdminFeatureFlagsScreen`
  - Load flags -> `GET /api/admin/flags`
  - Update flags -> `PUT /api/admin/flags`
- `AdminAutopilotScreen`
  - Run/autopilot preview/draft generation -> `/api/admin/autopilot/*`
