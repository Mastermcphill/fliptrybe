#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-https://tri-o-fliptrybe.onrender.com}"
TS="$(date +%s)"
BUYER_EMAIL="${BUYER_EMAIL:-smoke_buyer_${TS}@fliptrybe.test}"
BUYER_PASSWORD="${BUYER_PASSWORD:-SmokePass123!}"
PHONE_SUFFIX="$(printf '%s' "$TS" | tail -c 9)"
BUYER_PHONE="${BUYER_PHONE:-+23480${PHONE_SUFFIX}}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

echo "== FlipTrybe Ship Readiness Smoke =="
echo "BASE: $BASE"

echo
echo "[1] Version/health/public discovery"
curl -fsS "$BASE/api/version" | python -m json.tool >/dev/null
curl -fsS "$BASE/api/health" | python -m json.tool >/dev/null
curl -fsS "$BASE/api/public/listings/recommended?limit=3" | python -m json.tool >/dev/null
curl -fsS "$BASE/api/public/shortlets/recommended?limit=3" | python -m json.tool >/dev/null
echo "OK: core public endpoints"

echo
echo "[2] Register + login + me"
REGISTER_PAYLOAD=$(cat <<JSON
{"name":"Smoke Buyer","email":"$BUYER_EMAIL","phone":"$BUYER_PHONE","password":"$BUYER_PASSWORD"}
JSON
)
REGISTER_RES="$(curl -sS -X POST "$BASE/api/auth/register" -H "Content-Type: application/json" -d "$REGISTER_PAYLOAD")"
BUYER_TOKEN="$(printf '%s' "$REGISTER_RES" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))")"
if [[ -z "$BUYER_TOKEN" ]]; then
  LOGIN_PAYLOAD=$(cat <<JSON
{"email":"$BUYER_EMAIL","password":"$BUYER_PASSWORD"}
JSON
)
  LOGIN_RES="$(curl -sS -X POST "$BASE/api/auth/login" -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD")"
  BUYER_TOKEN="$(printf '%s' "$LOGIN_RES" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))")"
fi
if [[ -z "$BUYER_TOKEN" ]]; then
  echo "ERROR: unable to get buyer token"
  exit 1
fi
curl -fsS "$BASE/api/auth/me" -H "Authorization: Bearer $BUYER_TOKEN" | python -m json.tool >/dev/null
echo "OK: auth flow"

echo
echo "[3] Buyer support ticket + notifications + moneybox status"
TICKET_PAYLOAD='{"subject":"Smoke test","message":"User support message"}'
curl -fsS -X POST "$BASE/api/support/tickets" -H "Authorization: Bearer $BUYER_TOKEN" -H "Content-Type: application/json" -d "$TICKET_PAYLOAD" | python -m json.tool >/dev/null
curl -fsS "$BASE/api/notifications" -H "Authorization: Bearer $BUYER_TOKEN" | python -m json.tool >/dev/null
curl -fsS "$BASE/api/moneybox/status" -H "Authorization: Bearer $BUYER_TOKEN" | python -m json.tool >/dev/null
echo "OK: buyer secured endpoints"

if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
  echo
  echo "[4] Admin support list + optional reply"
  ADMIN_LOGIN=$(cat <<JSON
{"email":"$ADMIN_EMAIL","password":"$ADMIN_PASSWORD"}
JSON
)
  ADMIN_RES="$(curl -sS -X POST "$BASE/api/auth/login" -H "Content-Type: application/json" -d "$ADMIN_LOGIN")"
  ADMIN_TOKEN="$(printf '%s' "$ADMIN_RES" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))")"
  if [[ -z "$ADMIN_TOKEN" ]]; then
    echo "ERROR: admin login failed"
    exit 1
  fi
  THREADS_JSON="$(curl -sS "$BASE/api/admin/support/threads" -H "Authorization: Bearer $ADMIN_TOKEN")"
  printf '%s' "$THREADS_JSON" | python -m json.tool >/dev/null
  THREAD_ID="$(printf '%s' "$THREADS_JSON" | python -c "import sys,json; d=json.load(sys.stdin); items=d.get('items') or []; print((items[0].get('thread_id') if items else '') or '')")"
  if [[ -n "$THREAD_ID" ]]; then
    REPLY_PAYLOAD='{"body":"Admin smoke reply"}'
    curl -fsS -X POST "$BASE/api/admin/support/threads/$THREAD_ID/messages" -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "$REPLY_PAYLOAD" | python -m json.tool >/dev/null
    echo "OK: admin reply"
  else
    echo "WARN: no support thread found to reply"
  fi
fi

echo
echo "Smoke run complete."
