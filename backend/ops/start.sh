#!/usr/bin/env bash
set -euo pipefail

export FLASK_APP="${FLASK_APP:-main.py}"

echo "Running migrations..."
python -m flask db upgrade

echo "Starting gunicorn..."
exec gunicorn wsgi:app --bind 0.0.0.0:${PORT}
