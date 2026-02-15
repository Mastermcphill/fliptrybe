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

request_json() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local bearer="${4:-}"
  local headers_file
  local body_file
  local code
  local content_type
  headers_file="$(mktemp)"
  body_file="$(mktemp)"
  trap 'rm -f "$headers_file" "$body_file"' RETURN

  local curl_cmd=(
    curl -sS -X "$method" "$BASE$path"
    -H "Accept: application/json"
    -D "$headers_file"
    -o "$body_file"
    -w "%{http_code}"
  )
  if [[ -n "$bearer" ]]; then
    curl_cmd+=(-H "Authorization: Bearer $bearer")
  fi
  if [[ -n "$body" ]]; then
    curl_cmd+=(-H "Content-Type: application/json" -d "$body")
  fi

  code="$("${curl_cmd[@]}")"
  content_type="$(grep -i '^content-type:' "$headers_file" | tail -1 | cut -d: -f2- | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
  if [[ "$path" == /api/* && "$content_type" != *application/json* ]]; then
    echo "ERROR: non-JSON API response for $method $path (Content-Type: ${content_type:-missing})"
    cat "$body_file"
    exit 1
  fi
  if ! python -m json.tool "$body_file" >/dev/null 2>&1; then
    echo "ERROR: invalid JSON body for $method $path"
    cat "$body_file"
    exit 1
  fi
  if (( code >= 400 )); then
    echo "ERROR: HTTP $code for $method $path"
    cat "$body_file"
    exit 1
  fi
  cat "$body_file"
}

echo "== FlipTrybe Ship Readiness Smoke =="
echo "BASE: $BASE"

echo
echo "[0] Deploy parity"
VERSION_JSON="$(request_json GET /api/version)"
PROD_SHA="$(printf '%s' "$VERSION_JSON" | python -c "import sys,json; print((json.load(sys.stdin) or {}).get('git_sha',''))")"
if [[ -z "$PROD_SHA" ]]; then
  echo "ERROR: /api/version did not include git_sha"
  exit 1
fi
LOCAL_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
if [[ -n "$LOCAL_SHA" && "$PROD_SHA" != "$LOCAL_SHA" ]]; then
  echo "ERROR: render parity mismatch"
  echo "  prod:  $PROD_SHA"
  echo "  local: $LOCAL_SHA"
  exit 1
fi
echo "OK: parity git_sha=$PROD_SHA"

echo
echo "[1] Health/public discovery"
request_json GET /api/health >/dev/null
request_json GET "/api/public/listings/recommended?limit=3" >/dev/null
request_json GET "/api/public/shortlets/recommended?limit=3" >/dev/null
echo "OK: core public endpoints"

echo
echo "[2] Register + login + me"
REGISTER_PAYLOAD=$(cat <<JSON
{"name":"Smoke Buyer","email":"$BUYER_EMAIL","phone":"$BUYER_PHONE","password":"$BUYER_PASSWORD"}
JSON
)
REGISTER_RES="$(request_json POST /api/auth/register "$REGISTER_PAYLOAD")"
BUYER_TOKEN="$(printf '%s' "$REGISTER_RES" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))")"
if [[ -z "$BUYER_TOKEN" ]]; then
  LOGIN_PAYLOAD=$(cat <<JSON
{"email":"$BUYER_EMAIL","password":"$BUYER_PASSWORD"}
JSON
)
  LOGIN_RES="$(request_json POST /api/auth/login "$LOGIN_PAYLOAD")"
  BUYER_TOKEN="$(printf '%s' "$LOGIN_RES" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))")"
fi
if [[ -z "$BUYER_TOKEN" ]]; then
  echo "ERROR: unable to get buyer token"
  exit 1
fi
request_json GET /api/auth/me "" "$BUYER_TOKEN" >/dev/null
echo "OK: auth flow"

echo
echo "[3] Buyer support + notifications + moneybox"
request_json POST /api/support/tickets '{"subject":"Smoke test","message":"User support message"}' "$BUYER_TOKEN" >/dev/null
NOTIFY_JSON="$(request_json GET /api/notifications "" "$BUYER_TOKEN")"
NOTIFY_ID="$(printf '%s' "$NOTIFY_JSON" | python -c "import sys,json; d=json.load(sys.stdin); items=d.get('items') or []; print((items[0].get('id') if items else '') or '')")"
if [[ -n "$NOTIFY_ID" ]]; then
  request_json POST "/api/notifications/$NOTIFY_ID/read" "{}" "$BUYER_TOKEN" >/dev/null
fi
request_json GET /api/moneybox/status "" "$BUYER_TOKEN" >/dev/null
echo "OK: buyer secured endpoints"

if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
  echo
  echo "[4] Admin support list + optional reply"
  ADMIN_LOGIN=$(cat <<JSON
{"email":"$ADMIN_EMAIL","password":"$ADMIN_PASSWORD"}
JSON
)
  ADMIN_RES="$(request_json POST /api/auth/login "$ADMIN_LOGIN")"
  ADMIN_TOKEN="$(printf '%s' "$ADMIN_RES" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))")"
  if [[ -z "$ADMIN_TOKEN" ]]; then
    echo "ERROR: admin login failed"
    exit 1
  fi
  THREADS_JSON="$(request_json GET /api/admin/support/threads "" "$ADMIN_TOKEN")"
  THREAD_ID="$(printf '%s' "$THREADS_JSON" | python -c "import sys,json; d=json.load(sys.stdin); items=d.get('items') or []; print((items[0].get('thread_id') if items else '') or '')")"
  if [[ -n "$THREAD_ID" ]]; then
    request_json POST "/api/admin/support/threads/$THREAD_ID/messages" '{"body":"Admin smoke reply"}' "$ADMIN_TOKEN" >/dev/null
    echo "OK: admin reply"
  else
    echo "WARN: no support thread found to reply"
  fi

  PAYOUTS_JSON="$(request_json GET /api/wallet/payouts "" "$ADMIN_TOKEN" || true)"
  if [[ -n "${PAYOUTS_JSON:-}" ]]; then
    PENDING_PAYOUT_ID="$(printf '%s' "$PAYOUTS_JSON" | python -c "import sys,json; d=json.load(sys.stdin); items=d.get('items') or []; row=next((x for x in items if str(x.get('status','')).lower()=='pending'), None); print((row or {}).get('id',''))" 2>/dev/null || true)"
    if [[ -n "$PENDING_PAYOUT_ID" ]]; then
      request_json POST "/api/wallet/payouts/$PENDING_PAYOUT_ID/admin/pay" "{}" "$ADMIN_TOKEN" >/dev/null || echo "WARN: payout admin/pay smoke skipped"
      echo "OK: admin payout pay alias"
    else
      echo "WARN: no pending payout found for admin payout smoke"
    fi
  fi
fi

echo
echo "Smoke run complete."
