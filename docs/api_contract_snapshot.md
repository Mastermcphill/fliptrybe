# API Contract Snapshot (Frontend-Consumed)

This document has two parts:
- Normalized contract notes for critical shared envelopes.
- Exhaustive frontend endpoint inventory extracted from `frontend/lib` service/screen calls.

## Global API Error Contract (`/api/*`)
- Errors return JSON (not HTML):
```json
{"ok":false,"error":"NotFound","message":"Not Found","status":404,"trace_id":"..."}
```

## Shared Response Envelopes
- Discovery list envelope: `ok, city, state, items, limit[, offset,total]`
- Entity list envelope: `ok, items` (some legacy routes return raw arrays)
- Action result envelope: `ok` + route-specific keys (`message`, `id`, `status`, etc.)

## Vertical Expansion Additions (2026-02-18)
- Category taxonomy:
  - `GET /api/public/categories` now includes `category_groups` with vertical groups:
    - `Vehicles`
    - `Power & Energy`
  - `GET /api/public/categories/form-schema?category_id=<id>` returns dynamic form schema:
    - `schema.metadata_key` in `vehicle_metadata | energy_metadata | ""`
    - `schema.listing_type_hint` in `vehicle | energy | declutter`
    - `schema.fields[]` with `key, label, type, required, options`
  - `GET /api/public/category-groups` returns vertical groups only.
- Listings search:
  - `GET /api/listings/search` added as unified search route.
  - `GET /api/public/listings/search` and `GET /api/admin/listings/search` support additional filters:
    - `listing_type`
    - `make`
    - `model`
    - `year`
    - `battery_type`
    - `inverter_capacity`
    - `lithium_only`
- Listing payload additions:
  - `listing_type`
  - `vehicle_metadata`
  - `energy_metadata`
  - `vehicle_make`, `vehicle_model`, `vehicle_year`
  - `battery_type`, `inverter_capacity`, `lithium_only`, `bundle_badge`
  - `delivery_available`, `inspection_required`
  - `location_verified`, `inspection_request_enabled`, `financing_option`
  - `approval_status`, `inspection_flagged`
- Admin listing controls:
  - `POST /api/admin/listings/:id/approve` with `{approved|status}`.
  - `POST /api/admin/listings/:id/inspection-flag` with `{flagged}`.
- Merchant profile photo:
  - `POST /api/me/profile/photo` now supports both:
    - JSON URL payload (`profile_image_url`) for backward compatibility.
    - Multipart upload payload (`image`) for upload-widget flow.

## Identity Gate Update (2026-02-18)
- Email verification gate removed end-to-end.
- Auth routes removed:
  - `GET /api/auth/verify-email`
  - `POST /api/auth/verify-email/resend`
  - `GET /api/auth/verify-email/status`
- Protected sell/payout/moneybox/order actions now use phone verification gate:
  - Error code: `PHONE_NOT_VERIFIED`
  - Legacy `EMAIL_NOT_VERIFIED` is no longer returned.

## Frontend Endpoint Inventory

| Method | Path Template | Request Keys | Response Keys | Frontend Source |
|---|---|---|---|---|
| `DELETE` | `/cart/items/$itemId` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/cart_service.dart` |
| `DELETE` | `/merchants/$userId/follow` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/admin/analytics/overview` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/growth_analytics_service.dart` |
| `GET` | `/admin/analytics/revenue-breakdown` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/growth_analytics_service.dart` |
| `GET` | `/admin/anomalies` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/admin_anomalies_screen.dart` |
| `GET` | `/admin/autopilot` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `GET` | `/admin/autopilot/recommendations$suffix` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `GET` | `/admin/autopilot/snapshots?limit=$limit` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `GET` | `/admin/economics/health` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/growth_analytics_service.dart` |
| `GET` | `/admin/flags` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_ops_service.dart` |
| `GET` | `/admin/health/summary` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_ops_service.dart` |
| `GET` | `/admin/inspector-requests?status=pending` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/admin_overview_screen.dart` |
| `GET` | `/admin/listings` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/admin_lists_screen.dart` |
| `GET` | `/admin/omega/intelligence` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/omega_intelligence_service.dart` |
| `GET` | `/admin/orders/${widget.orderId}/timeline` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/admin_order_timeline_screen.dart` |
| `GET` | `/admin/payments/manual/$paymentIntentId` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `GET` | `/admin/payments/mode` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `GET` | `/admin/search?q=${Uri.encodeQueryComponent(q)}` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/admin_global_search_screen.dart` |
| `GET` | `/admin/settings/payments` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `GET` | `/admin/simulation/baseline` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/liquidity_simulation_service.dart` |
| `GET` | `/admin/summary` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_service.dart` |
| `GET` | `/admin/support/threads/$threadId/messages` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/support_service.dart` |
| `GET` | `/admin/users` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/admin_lists_screen.dart` |
| `GET` | `/buyer/analytics` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/growth_analytics_service.dart` |
| `GET` | `/cart` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/cart_service.dart` |
| `GET` | `/driver/active` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_directory_service.dart` |
| `GET` | `/driver/jobs` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_service.dart` |
| `GET` | `/driver/offers` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_offer_service.dart` |
| `GET` | `/driver/profile` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_directory_service.dart` |
| `GET` | `/drivers` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_roster_service.dart` |
| `GET` | `/heat` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/heatmap_screen.dart` |
| `GET` | `/heatmap` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/feed_service.dart` |
| `GET` | `/inspectors/me/profile` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/inspector_service.dart` |
| `GET` | `/investor/analytics` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/metrics_screen.dart` |
| `GET` | `/kpis/merchant` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/kpi_service.dart` |
| `GET` | `/kpis/merchant` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/kyc/admin/pending` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/kyc_service.dart` |
| `GET` | `/kyc/status` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/kyc_service.dart` |
| `GET` | `/leaderboards` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/leaderboards/featured` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/leaderboard_service.dart` |
| `GET` | `/listings` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/listing_service.dart` |
| `GET` | `/listings/$listingId` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/listing_service.dart` |
| `GET` | `/locations` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/feed_service.dart` |
| `GET` | `/me/following-merchants?limit=$limit&offset=$offset` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/me/preferences` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/city_preference_service.dart` |
| `GET` | `/media/cloudinary/config` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/shortlet_service.dart` |
| `GET` | `/merchant/analytics` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/sales_analytics_screen.dart` |
| `GET` | `/merchant/analytics` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/growth_analytics_service.dart` |
| `GET` | `/merchant/followers/count` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/merchant/followers?limit=$limit&offset=$offset` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/merchant/listings` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/listing_service.dart` |
| `GET` | `/merchant/orders` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `GET` | `/merchants/$userId` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/moneybox/autosave/settings` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `GET` | `/moneybox/ledger` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `GET` | `/moneybox/status` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `GET` | `/notify/inbox` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/notification_service.dart` |
| `GET` | `/orders/$orderId` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `GET` | `/orders/$orderId/delivery` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `GET` | `/orders/$orderId/timeline` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `GET` | `/orders/my$suffix` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `GET` | `/payments/methods?scope=$safeScope` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/payment_service.dart` |
| `GET` | `/payments/status?order_id=$orderId` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/payment_service.dart` |
| `GET` | `/payout/recipient` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/payout_recipient_service.dart` |
| `GET` | `/public/categories` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/category_service.dart` |
| `GET` | `/public/features` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/marketplace_catalog_service.dart` |
| `GET` | `/public/manual-payment-instructions` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/payment_service.dart` |
| `GET` | `/public/merchants/$userId` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `GET` | `/public/sales_ticker?limit=8` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/landing_screen.dart` |
| `GET` | `/receipts` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/receipt_service.dart` |
| `GET` | `/referral/code` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/referral_service.dart` |
| `GET` | `/referral/stats` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/referral_service.dart` |
| `GET` | `/role-requests/me` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/pending_approval_screen.dart` |
| `GET` | `/settings` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/settings_service.dart` |
| `GET` | `/shortlets/$shortletId` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/shortlet_service.dart` |
| `GET` | `/shortlets/popular` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/shortlet_service.dart` |
| `GET` | `/support/messages` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/support_chat_screen.dart` |
| `GET` | `/wallet` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/wallet_service.dart` |
| `GET` | `/wallet/ledger` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/wallet_service.dart` |
| `GET` | `/wallet/payouts` | path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/wallet_service.dart` |
| `PATCH` | `/cart/items/$itemId` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/cart_service.dart` |
| `POST` | `/admin/autopilot/generate-draft?window=$window` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/autopilot/preview-impact` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/autopilot/recommendations/$recommendationId/status` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/autopilot/run?window=$window` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/autopilot/settings` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/autopilot/tick` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/autopilot/toggle` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/commission` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/commission_service.dart` |
| `POST` | `/admin/commission/$id/disable` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/commission_service.dart` |
| `POST` | `/admin/commission/policies` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/commission_policy_service.dart` |
| `POST` | `/admin/commission/policies/$policyId/activate` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/commission_policy_service.dart` |
| `POST` | `/admin/commission/policies/$policyId/archive` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/commission_policy_service.dart` |
| `POST` | `/admin/commission/policies/$policyId/rules` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/commission_policy_service.dart` |
| `POST` | `/admin/expansion/simulate` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/omega_intelligence_service.dart` |
| `POST` | `/admin/fraud/$fraudFlagId/freeze` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/omega_intelligence_service.dart` |
| `POST` | `/admin/fraud/$fraudFlagId/review` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/omega_intelligence_service.dart` |
| `POST` | `/admin/liquidity/cross-market-simulate` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/omega_intelligence_service.dart` |
| `POST` | `/admin/listings/$listingId/disable` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_service.dart` |
| `POST` | `/admin/notifications/broadcast` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_broadcast_service.dart` |
| `POST` | `/admin/notifications/process` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_broadcast_service.dart` |
| `POST` | `/admin/notify-queue/$id/mark-sent` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_notify_queue_service.dart` |
| `POST` | `/admin/notify-queue/$id/requeue` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_notify_queue_service.dart` |
| `POST` | `/admin/notify-queue/$id/retry-now` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_notify_queue_service.dart` |
| `POST` | `/admin/payments/manual/mark-paid` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/payments/manual/reject` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/payments/mode` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/role-requests/$requestId/approve` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_role_service.dart` |
| `POST` | `/admin/role-requests/$requestId/reject` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_role_service.dart` |
| `POST` | `/admin/settings/payments` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_autopilot_service.dart` |
| `POST` | `/admin/simulation/liquidity` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/liquidity_simulation_service.dart` |
| `POST` | `/admin/support/threads/$threadId/messages` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/support_service.dart` |
| `POST` | `/admin/users/$userId/disable` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_service.dart` |
| `POST` | `/auth/logout` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/api_service.dart` |
| `POST` | `/auth/set-role` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/auth_service.dart` |
| `POST` | `/cart/items` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/cart_service.dart` |
| `POST` | `/driver/availability` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_availability_service.dart` |
| `POST` | `/driver/jobs/$jobId/accept` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_service.dart` |
| `POST` | `/driver/jobs/$jobId/status` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_service.dart` |
| `POST` | `/driver/offers/$offerId/accept` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_offer_service.dart` |
| `POST` | `/driver/offers/$offerId/reject` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_offer_service.dart` |
| `POST` | `/driver/orders/$orderId/confirm-delivery` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `POST` | `/driver/profile` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/driver_directory_service.dart` |
| `POST` | `/kyc/admin/set` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/kyc_service.dart` |
| `POST` | `/kyc/submit` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/kyc_service.dart` |
| `POST` | `/me/preferences` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/city_preference_service.dart` |
| `POST` | `/me/profile/photo` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `POST` | `/merchants/$userId/follow` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `POST` | `/merchants/$userId/simulate-sale` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `POST` | `/merchants/profile` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/merchant_service.dart` |
| `POST` | `/moneybox/autosave` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `POST` | `/moneybox/autosave/settings` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `POST` | `/moneybox/open` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `POST` | `/moneybox/tier` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `POST` | `/moneybox/withdraw` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/moneybox_service.dart` |
| `POST` | `/notifications/$safeId/read` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/notification_service.dart` |
| `POST` | `/notify/flush-demo` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/notification_service.dart` |
| `POST` | `/orders` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `POST` | `/orders/$orderId/driver/assign` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `POST` | `/orders/$orderId/driver/status` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `POST` | `/orders/$orderId/qr/issue` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `POST` | `/orders/$orderId/qr/scan` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `POST` | `/orders/bulk` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/cart_service.dart` |
| `POST` | `/payments/initialize` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/payment_service.dart` |
| `POST` | `/payments/initialize` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/topup_service.dart` |
| `POST` | `/payments/manual/$paymentIntentId/proof` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/payment_service.dart` |
| `POST` | `/payout/recipient` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/payout_recipient_service.dart` |
| `POST` | `/pricing/suggest` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/pricing_service.dart` |
| `POST` | `/receipts/demo` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/receipt_service.dart` |
| `POST` | `/referral/apply` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/referral_service.dart` |
| `POST` | `/seller/orders/$orderId/confirm-pickup` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/order_service.dart` |
| `POST` | `/settings` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/settings_service.dart` |
| `POST` | `/shortlets` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/shortlet_service.dart` |
| `POST` | `/shortlets/$shortletId/review` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/shortlet_service.dart` |
| `POST` | `/support/messages` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/screens/support_chat_screen.dart` |
| `POST` | `/support/tickets` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/support_service.dart` |
| `POST` | `/support/tickets/$ticketId/status` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/support_service.dart` |
| `POST` | `/wallet/payouts/$payoutId/admin/approve` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_wallet_service.dart` |
| `POST` | `/wallet/payouts/$payoutId/admin/mark-paid` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_wallet_service.dart` |
| `POST` | `/wallet/payouts/$payoutId/admin/pay` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_wallet_service.dart` |
| `POST` | `/wallet/payouts/$payoutId/admin/process` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_wallet_service.dart` |
| `POST` | `/wallet/payouts/$payoutId/admin/reject` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/admin_wallet_service.dart` |
| `POST` | `/wallet/topup-demo` | JSON body + path/query params + auth header where required | JSON object/list; success route-specific, errors use global API contract | `frontend/lib/services/wallet_service.dart` |
