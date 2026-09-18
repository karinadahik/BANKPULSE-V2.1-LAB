#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
PAYMENT_KEY="release-gate-$(date +%s%N)"

FIRST="/tmp/release-gate-payment-first.json"
SECOND="/tmp/release-gate-payment-second.json"
PAYMENTS="/tmp/release-gate-payments.json"

echo "========================================"
echo " BUSINESS RELEASE GATE"
echo " Capability: Process a payment once"
echo "========================================"

echo
echo "[1/4] Technical availability"

curl -fsS "$BASE_URL/health/payments" > /dev/null

echo "Payments API: UP"

echo
echo "[2/4] First business request"

curl -fsS \
  -X POST "$BASE_URL/api/payments" \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: $PAYMENT_KEY" \
  -d '{"account":"EC-4242","amount":500.00,"currency":"USD"}' \
  > "$FIRST"

echo
echo "[3/4] Retry same business operation"

curl -fsS \
  -X POST "$BASE_URL/api/payments" \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: $PAYMENT_KEY" \
  -d '{"account":"EC-4242","amount":500.00,"currency":"USD"}' \
  > "$SECOND"

echo
echo "[4/4] Validate business invariant"

curl -fsS "$BASE_URL/api/payments" > "$PAYMENTS"

first_id="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$FIRST")"
second_id="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$SECOND")"

if [ -z "$first_id" ] || [ -z "$second_id" ]; then
  echo "RELEASE BLOCKED: could not read payment IDs"
  exit 1
fi

if [ "$first_id" != "$second_id" ]; then
  echo "RELEASE BLOCKED: retry created a different payment"
  echo "First payment:  $first_id"
  echo "Second payment: $second_id"
  exit 1
fi

matches="$(
  grep -o "\"idempotencyKey\":\"$PAYMENT_KEY\"" "$PAYMENTS" \
    | wc -l \
    | tr -d ' '
)"

if [ "$matches" -ne 1 ]; then
  echo "RELEASE BLOCKED: expected exactly 1 payment, found $matches"
  exit 1
fi

echo "Same Idempotency-Key -> 2 requests -> 1 payment"
echo "Payment ID: $first_id"
echo "BUSINESS RELEASE GATE: PASS"