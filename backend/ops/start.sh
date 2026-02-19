#!/usr/bin/env bash
set -euo pipefail

FLASK_APP_TARGET="${FLASK_APP_TARGET:-main:app}"
WEB_CONCURRENCY="${WEB_CONCURRENCY:-3}"
THREADS="${THREADS:-2}"
TIMEOUT="${TIMEOUT:-60}"
KEEPALIVE="${KEEPALIVE:-5}"
PORT="${PORT:-5000}"
GUNICORN_APP="${GUNICORN_APP:-wsgi:app}"

echo "Running migrations..."
python -m flask --app "${FLASK_APP_TARGET}" db upgrade

echo "Starting gunicorn..."
exec gunicorn "${GUNICORN_APP}" \
  --bind "0.0.0.0:${PORT}" \
  --workers "${WEB_CONCURRENCY}" \
  --threads "${THREADS}" \
  --timeout "${TIMEOUT}" \
  --keep-alive "${KEEPALIVE}"
