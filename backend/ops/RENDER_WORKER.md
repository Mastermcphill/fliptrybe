# Render Worker Commands (FlipTrybe)

## Canonical Celery app import
Use this import target everywhere:
- `celery -A celery_app:celery ...`

## Render commands
Assumes service `rootDir=backend`.

### Web service
- Build Command:
  - `pip install --upgrade pip && pip install -r requirements.txt`
- Start Command:
  - `bash -c "chmod +x ops/start.sh && ./ops/start.sh"`
- Pre-deploy migration command (web only):
  - `python -m flask --app main:app db upgrade`

### Worker service
- Build Command:
  - `pip install --upgrade pip && pip install -r requirements.txt`
- Start Command:
  - `celery -A celery_app:celery worker --loglevel=INFO --concurrency=${CELERY_CONCURRENCY:-2}`

### Beat/cron service
- Build Command:
  - `pip install --upgrade pip && pip install -r requirements.txt`
- Start Command:
  - `celery -A celery_app:celery beat --loglevel=INFO`

## rootDir notes
- If `rootDir=backend`, do not prefix commands with `cd backend`.
- If `rootDir` is repo root, prefix with `cd backend && ...`.

## Concurrency guidance
- Set `CELERY_CONCURRENCY` explicitly in production.
- Start with `2` for low traffic; increase after observing CPU, memory, and queue latency.
- Keep `worker_prefetch_multiplier=1` (already configured) for fairer queue handling.

## Migration safety
- Run migrations once from the web deploy hook/preDeploy step.
- Workers and beat must never run migrations.

## Import validation
Run:
- `python ops/check_celery_import.py`
Exit code `0` means the canonical Celery app import loads successfully.
