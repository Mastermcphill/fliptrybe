# API Contract Snapshot (Frontend-Consumed)

This snapshot captures the primary routes used by active Flutter flows and the expected JSON contracts.

## Public Discovery

### `GET /api/public/listings/recommended`
- Query: `city?`, `state?`, `limit?`, `offset?`, `category_id?`, `parent_category_id?`, `brand_id?`, `model_id?`
- `200`:
```json
{
  "ok": true,
  "city": "Lagos",
  "state": "Lagos",
  "items": [],
  "limit": 20,
  "offset": 0,
  "total": 0
}
```

### `GET /api/public/listings/search`
- Query: `q`, plus recommended filters above.
- `200` same envelope as recommended with `items`.

### `GET /api/public/listings/deals`
### `GET /api/public/listings/new_drops`
- `200` same envelope as recommended with `items`.

### `GET /api/public/shortlets/recommended`
- Query: `city?`, `state?`, `limit?`
- `200`:
```json
{
  "ok": true,
  "city": "Lagos",
  "state": "Lagos",
  "items": [],
  "limit": 20
}
```

## Auth

### `POST /api/auth/register`
- Body: `name`, `email`, `phone`, `password` (+ optional referral fields).
- `200/201` includes `token` and `user` payload.

### `POST /api/auth/login`
- Body: `email`, `password`
- `200` includes `token` and `user`.

### `GET /api/auth/me`
- Auth required.
- `200` current user object + role request metadata.

## Notifications

### `GET /api/notifications`
- Auth required.
- `200`:
```json
{"ok": true, "items": [{"id": 1, "is_read": false, "read_at": null}]}
```

### `POST /api/notifications/<notification_id>/read`
- Auth required.
- `200`:
```json
{"ok": true, "id": 1, "is_read": true, "read_at": "2026-02-15T12:00:00"}
```
- `404` for unknown/invalid ID:
```json
{"message": "Not found", "trace_id": "..."}
```

## Support

### `POST /api/support/tickets`
- Auth required.
- Body: `subject`, `message`
- `201` ticket payload.

### `GET /api/admin/support/threads`
- Admin auth required.
- `200` list of threads with `thread_id`.

### `GET /api/admin/support/threads/<thread_id>/messages`
- Admin auth required.
- `200`:
```json
{"ok": true, "items": [{"sender_role": "buyer|admin", "body": "..."}]}
```

### `POST /api/admin/support/threads/<thread_id>/messages`
- Admin auth required.
- Body: `{ "body": "..." }`
- `201`:
```json
{"ok": true, "message": {"thread_id": 10, "sender_role": "admin", "body": "..."}}
```

## Wallet / Moneybox

### `GET /api/moneybox/status`
- Auth required.
- `200` current moneybox state for user.

### `POST /api/wallet/payouts/<payout_id>/admin/pay`
- Admin auth required.
- Compatibility alias to payout processing path.
- `200` payout result envelope.

## Global Error Contract for `/api/*`
- `4xx/5xx` returns JSON:
```json
{
  "ok": false,
  "error": "NotFound",
  "message": "Not Found",
  "status": 404,
  "trace_id": "..."
}
```
