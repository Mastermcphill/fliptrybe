# Render Deployment Notes (FlipTrybe)

## Required Environment Variables
- FLIPTRYBE_ENV=production
- SECRET_KEY=<long random string>
- DATABASE_URL=<Render Postgres URL>
- CORS_ORIGINS=<comma-separated origins, e.g. https://app.fliptrybe.com>
- PAYSTACK_SECRET_KEY (if payments enabled)
- TERMII_API_KEY (if SMS enabled)
- TERMII_SENDER_ID (optional)

## Start Command
```
gunicorn -b 0.0.0.0:$PORT "app:create_app()"
```

## Branch + Root Parity
- Render service branch must be `main`.
- Root directory must be `backend`.
- `render.yaml` in repo root now pins these settings and enables auto-deploy.

## Release Command (Migrations)
```
flask db upgrade
```

## Health Check
- GET /api/health
- Expect JSON: { ok: true, service: "fliptrybe-backend", env: "production", db: "ok"|"fail" }

## Demo Endpoints
- Demo seed endpoints are removed and are not available in any environment.

## Notes
- Production will refuse to start if SECRET_KEY or DATABASE_URL is missing.
- Avoid CORS '*' in production; set explicit origins via CORS_ORIGINS.
