# FlipTrybe Backend Scale Notes

## Runtime Topology
- `web`: `ops/start.sh` (runs migrations once, then Gunicorn)
- `worker`: Celery worker (`celery -A celery_app:celery worker`)
- `cron`: Celery beat scheduler (`celery -A celery_app:celery beat`)

## Local Run
- Web:
```bash
cd backend
python -m flask --app main:app db upgrade
./ops/start.sh
```
- Worker:
```bash
cd backend
celery -A celery_app:celery worker --loglevel=INFO
```
- Beat:
```bash
cd backend
celery -A celery_app:celery beat --loglevel=INFO
```

## Required Env Vars
- Database/runtime:
  - `DATABASE_URL`
  - `SECRET_KEY`
- Redis/Celery:
  - `REDIS_URL`
  - `CELERY_BROKER_URL` (falls back to `REDIS_URL`)
  - `CELERY_RESULT_BACKEND` (falls back to `REDIS_URL`)
  - `CACHE_REDIS_URL` (falls back to `REDIS_URL`)
  - `RATE_LIMIT_REDIS_URL` (falls back to `REDIS_URL`)
- Feature flags:
  - `ENABLE_CACHE`
  - `ENABLE_RATE_LIMIT`
  - `ENABLE_IDEMPOTENCY_ENFORCEMENT`
  - `PAYSTACK_WEBHOOK_QUEUE`
  - `TERMII_QUEUE`
  - `ENABLE_METRICS`
- Cache TTL:
  - `DEFAULT_CACHE_TTL_SECONDS`
  - `LISTING_DETAIL_CACHE_TTL_SECONDS`
  - `FEED_CACHE_TTL_SECONDS`

## Cache Keys + Invalidation
- Key format: `v1:<scope>:<sorted_params>`
- Listing detail cache:
  - Scope: `listing_detail`
  - Endpoint: `GET /api/listings/<id>`
  - TTL: `LISTING_DETAIL_CACHE_TTL_SECONDS`
- Feed/search cache:
  - Scope prefix: `feed:*`
  - Endpoints:
    - `GET /api/public/listings/search`
    - `GET /api/listings/search`
    - `GET /api/public/listings/recommended`
  - TTL: `FEED_CACHE_TTL_SECONDS`
- Invalidation:
  - On listing create/update/delete
  - On admin approve/inspection-flag changes
  - Current strategy: remove listing detail key + broad `v1:feed:` prefix

## Rate Limit Tiers
- Auth endpoints:
  - `10/min` per IP
  - `30/hr` per IP
- Browse GET endpoints:
  - `120/min` per user (authenticated) or IP (anonymous)
- Write endpoints:
  - `60/min` per user (authenticated) or IP (anonymous)
- Response shape on throttle:
```json
{
  "ok": false,
  "error": {
    "code": "RATE_LIMITED",
    "retry_after_seconds": 12
  },
  "trace_id": "..."
}
```

## Idempotency Scopes
- Key source: `Idempotency-Key` header
- Hash source: `method + path + canonical_json(payload)`
- Enforced when `ENABLE_IDEMPOTENCY_ENFORCEMENT=true` for configured prefixes:
  - `/api/orders`
  - `/api/payments/initialize`
  - `/api/payments/webhook/paystack`
  - `/api/webhooks/paystack`
  - `/api/wallet/payouts`
- Conflict response:
  - HTTP `409`
  - `error.code = IDEMPOTENCY_KEY_REUSE`
