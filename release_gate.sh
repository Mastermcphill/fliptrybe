#!/usr/bin/env bash
set -euo pipefail

echo "==[0] Repo sanity =="
git rev-parse --abbrev-ref HEAD
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree not clean"
  git status --porcelain
  exit 1
fi

echo
echo "==[A] Backend tests =="
cd backend
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests -p "test_*.py"
PYTHONDONTWRITEBYTECODE=1 python -m unittest -q \
  tests.test_request_id_headers \
  tests.test_image_fingerprint_dedupe

echo
echo "==[B] Frontend tests =="
cd ../frontend
flutter pub get
flutter test

echo
echo "==[DONE] Release gate PASSED ✅ =="
