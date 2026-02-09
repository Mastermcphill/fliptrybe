# Delivery secret codes flow (seller -> driver -> buyer)

## Step-by-step flow
1) Buyer creates order (POST /api/orders). Order stores buyer_id, merchant_id, status.
2) Merchant accepts order (POST /api/orders/<id>/merchant/accept) after availability confirmed.
3) Driver assigned (POST /api/orders/<id>/driver/assign). This triggers pickup unlock:
   - _issue_pickup_unlock(o) in segment_orders_api.py
   - pickup_code generated and stored in orders.pickup_code
   - escrow_unlocks row created with step=pickup_seller, code_hash stored
   - SMS sent to driver with pickup code
4) Driver issues pickup QR (POST /api/orders/<id>/qr/issue step=pickup_seller) -> token stored in qr_challenges.
5) Merchant scans pickup QR (POST /api/orders/<id>/qr/scan) -> qr_challenges updated.
6) Merchant confirms pickup with code (POST /api/seller/orders/<id>/confirm-pickup) -> escrow_unlocks verified, seller payout release triggered.
7) Driver sets status picked_up (POST /api/orders/<id>/driver/status status=picked_up) -> delivery unlock:
   - _issue_delivery_unlock(o) generates dropoff_code
   - orders.dropoff_code stored, escrow_unlocks step=delivery_driver created with code_hash
   - SMS sent to buyer with dropoff code
8) Buyer issues delivery QR (POST /api/orders/<id>/qr/issue step=delivery_driver) -> token stored
9) Driver scans delivery QR (POST /api/orders/<id>/qr/scan) -> qr_challenges updated
10) Driver confirms delivery with code (POST /api/driver/orders/<id>/confirm-delivery) -> escrow_unlocks verified, driver payout release triggered.

Note: Buyer has no separate confirm endpoint in backend. Buyer issues delivery QR and sees status updates.

## UI data source (delivery state + codes)
- GET /api/orders/<id>/delivery (buyer/merchant/driver/admin)
  - Returns delivery progress + role-scoped codes:
    - pickup_code only for merchant/admin
    - dropoff_code for driver/admin and buyer (to share with driver)
  - Also returns pickup/dropoff confirmed timestamps and attempts counters.

## Endpoints + roles
- /api/orders (buyer)
- /api/orders/<id>/merchant/accept (merchant)
- /api/orders/<id>/driver/assign (merchant/admin)
- /api/orders/<id>/qr/issue (driver for pickup; buyer for delivery)
- /api/orders/<id>/qr/scan (merchant for pickup; driver for delivery)
- /api/seller/orders/<id>/confirm-pickup (merchant)
- /api/orders/<id>/driver/status (driver)
- /api/driver/orders/<id>/confirm-delivery (driver)
- /api/orders/<id>/delivery (buyer/merchant/driver/admin)

## DB fields
- orders.pickup_code, orders.dropoff_code (raw codes)
- escrow_unlocks.code_hash, escrow_unlocks.step, escrow_unlocks.qr_verified, escrow_unlocks.unlocked_at
- qr_challenges.token, qr_challenges.step, qr_challenges.scanned_at

## Gaps / minimal fixes
- Frontend has buyerConfirmDelivery() hitting /orders/<id>/buyer/confirm (missing). Keep unused or add backend alias only if needed.
- Codes are stored raw in orders.*_code; consider hashing-only if exposure risk becomes a concern.
