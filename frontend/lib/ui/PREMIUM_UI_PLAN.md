# Premium UI Plan

## Baseline
- `flutter pub get`: pass
- `flutter test`: pass (21 tests)
- `flutter analyze`: 123 issues (report-only baseline)

### Lint Category Baseline
- `deprecated_member_use`: 39
- `prefer_const_constructors`: 31
- `unused_import`: 14
- `curly_braces_in_flow_control_structures`: 12
- `unused_field`: 6
- `unnecessary_cast`: 6
- `prefer_interpolation_to_compose_strings`: 5
- `unused_local_variable`: 3
- `prefer_const_declarations`: 2
- `prefer_final_fields`: 1
- `sort_child_properties_last`: 1
- `control_flow_in_finally`: 1
- `unused_element`: 1
- `use_super_parameters`: 1

## Token Inventory
- Spacing: `s4,s8,s12,s16,s20,s24,s32`
- Radius: `r12,r16,r20`
- Elevation: `e0,e1,e2,e3`
- Motion: `d150,d200,d300`
- Typography: page/section/card/body/meta/price
- Palettes: `neutral|mint|sand` for light+dark

## Component Kit
- `FTScaffold`
- `FTAppBar`
- `FTCard`
- `FTButton` (primary/secondary/ghost/destructive)
- `FTInput`
- `FTTile`
- `FTBadge`
- `FTEmptyState`
- `FTSkeleton`
- `FTToast`

## Sweep Checklist
- [ ] Replace hardcoded colors with `colorScheme`
- [ ] Replace ad hoc spacing with token spacing
- [ ] Use FT components across target screens
- [ ] Standardize loading/empty/error states
- [ ] Validate light/dark + 3 palettes
- [ ] Keep role shell navigation behavior intact
- [ ] Keep admin flows intact

## Coverage Matrix

### Buyer
- `buyer_home_screen.dart`
- `marketplace_screen.dart`
- `marketplace/marketplace_search_results_screen.dart`
- `listing_detail_screen.dart`
- `orders_screen.dart`

### Merchant
- `merchant_home_screen.dart`
- `merchant_listings_screen.dart`
- `merchant_orders_screen.dart`
- `merchant_growth_screen.dart`

### Driver
- `driver_home_screen.dart`
- `driver_jobs_screen.dart`
- `driver_earnings_screen.dart`

### Inspector
- `inspector_home_screen.dart`
- `inspector_bookings_screen.dart`
- `inspector_earnings_screen.dart`

### Admin
- `admin_overview_screen.dart`
- `admin_hub_screen.dart`
- `admin_support_threads_screen.dart`
- `admin_autopilot_screen.dart`
- `admin_notify_queue_screen.dart`
- `admin_role_approvals_screen.dart`
- `admin_inspector_requests_screen.dart`

### Shared / Guest / Auth
- `landing_screen.dart`
- `login_screen.dart`
- `role_signup_screen.dart`
- `profile_screen.dart`
- `settings_demo_screen.dart`
- `public_browse_shell.dart`
