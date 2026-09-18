#!/usr/bin/env bash
set -euo pipefail

SERVICE="social-split-api"
BASE_URL="http://localhost:8086"

echo "=============================================="
echo " SOCIAL SPLIT BUSINESS KPI GATE"
echo " Epic: Collaborative consumption / Social Split"
echo "=============================================="

wait_for_service() {
  echo
  echo "[0/8] Waiting for Social Split API"

  for i in $(seq 1 60); do
    if docker compose exec -T "$SERVICE" \
      curl -fsS "$BASE_URL/actuator/health" \
      > /dev/null 2>&1; then

      echo "Social Split API: UP"
      return 0
    fi

    sleep 2
  done

  echo "BUSINESS KPI GATE: BLOCKED"
  echo "Social Split API did not become healthy"
  exit 1
}

metric() {
  local name="$1"

  docker compose exec -T "$SERVICE" \
    curl -s "$BASE_URL/actuator/prometheus" \
    | awk -v metric_name="$name" \
      '$1 == metric_name {print $2; exit}'
}

delta_int() {
  awk -v after="$1" -v before="$2" \
    'BEGIN {printf "%.0f", after - before}'
}

delta_float() {
  awk -v after="$1" -v before="$2" \
    'BEGIN {printf "%.6f", after - before}'
}

percentage() {
  awk -v numerator="$1" -v denominator="$2" \
    'BEGIN {
      if (denominator == 0) {
        printf "0.00"
      } else {
        printf "%.2f", (numerator / denominator) * 100
      }
    }'
}

wait_for_service

echo
echo "[1/8] Capture metric baseline"

before_initiated="$(metric bankpulse_social_split_sessions_initiated_total)"
before_completed="$(metric bankpulse_social_split_sessions_completed_total)"

before_added="$(metric bankpulse_social_split_participants_added_total)"
before_authorized="$(metric bankpulse_social_split_participants_authorized_total)"

before_close_attempts="$(metric bankpulse_social_split_sessions_close_attempts_total)"
before_close_blocked="$(metric bankpulse_social_split_sessions_close_blocked_total)"

before_duration_count="$(metric bankpulse_social_split_sessions_close_duration_seconds_count)"
before_duration_sum="$(metric bankpulse_social_split_sessions_close_duration_seconds_sum)"

before_valid="$(metric bankpulse_social_split_settlements_valid_total)"
before_invalid="$(metric bankpulse_social_split_settlements_invalid_total)"

echo "Baseline captured"

echo
echo "[2/8] Create Social Split"

suffix="$(date +%s%N)"

session_json="$(
  docker compose exec -T "$SERVICE" \
    curl -fsS \
    -X POST "$BASE_URL/api/splits" \
    -H "Content-Type: application/json" \
    -d "{
      \"hostMemberId\":\"HOST-KPI-$suffix\",
      \"totalAmount\":100.00,
      \"currency\":\"USD\"
    }"
)"

session_id="$(
  printf '%s' "$session_json" \
    | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
)"

if [ -z "$session_id" ]; then
  echo "BUSINESS KPI GATE: BLOCKED"
  echo "Could not create Social Split"
  exit 1
fi

echo "Social Split created: $session_id"

echo
echo "[3/8] Add two participants"

participant_one_json="$(
  docker compose exec -T "$SERVICE" \
    curl -fsS \
    -X POST \
    "$BASE_URL/api/splits/$session_id/participants" \
    -H "Content-Type: application/json" \
    -d '{
      "memberId":"MEMBER-KPI-A",
      "shareAmount":40.00
    }'
)"

participant_one_id="$(
  printf '%s' "$participant_one_json" \
    | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
)"

participant_two_json="$(
  docker compose exec -T "$SERVICE" \
    curl -fsS \
    -X POST \
    "$BASE_URL/api/splits/$session_id/participants" \
    -H "Content-Type: application/json" \
    -d '{
      "memberId":"MEMBER-KPI-B",
      "shareAmount":60.00
    }'
)"

participant_two_id="$(
  printf '%s' "$participant_two_json" \
    | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
)"

if [ -z "$participant_one_id" ] || [ -z "$participant_two_id" ]; then
  echo "BUSINESS KPI GATE: BLOCKED"
  echo "Could not obtain participant IDs"
  exit 1
fi

echo "Participant A: $participant_one_id -> USD 40"
echo "Participant B: $participant_two_id -> USD 60"

echo
echo "[4/8] Verify premature close is blocked"

blocked_code="$(
  docker compose exec -T "$SERVICE" \
    curl -s \
    -o /tmp/social-split-blocked.json \
    -w "%{http_code}" \
    -X POST \
    "$BASE_URL/api/splits/$session_id/close"
)"

if [ "$blocked_code" -lt 400 ]; then
  echo "BUSINESS KPI GATE: BLOCKED"
  echo "Session closed without participant authorization"
  exit 1
fi

echo "Premature close correctly blocked (HTTP $blocked_code)"

echo
echo "[5/8] Authorize participants"

docker compose exec -T "$SERVICE" \
  curl -fsS \
  -X POST \
  "$BASE_URL/api/splits/$session_id/participants/$participant_one_id/authorize" \
  -H "Content-Type: application/json" \
  -d "{
    \"paymentReference\":\"PAY-KPI-A-$suffix\"
  }" \
  > /dev/null

docker compose exec -T "$SERVICE" \
  curl -fsS \
  -X POST \
  "$BASE_URL/api/splits/$session_id/participants/$participant_two_id/authorize" \
  -H "Content-Type: application/json" \
  -d "{
    \"paymentReference\":\"PAY-KPI-B-$suffix\"
  }" \
  > /dev/null

echo "Both participants authorized"

echo
echo "[6/8] Close Social Split"

close_json="$(
  docker compose exec -T "$SERVICE" \
    curl -fsS \
    -X POST \
    "$BASE_URL/api/splits/$session_id/close"
)"

if ! printf '%s' "$close_json" \
  | grep -q '"status":"COMPLETED"'; then

  echo "BUSINESS KPI GATE: BLOCKED"
  echo "Social Split did not reach COMPLETED"
  exit 1
fi

echo "Social Split completed"

echo
echo "[7/8] Calculate business KPI evidence"

after_initiated="$(metric bankpulse_social_split_sessions_initiated_total)"
after_completed="$(metric bankpulse_social_split_sessions_completed_total)"

after_added="$(metric bankpulse_social_split_participants_added_total)"
after_authorized="$(metric bankpulse_social_split_participants_authorized_total)"

after_close_attempts="$(metric bankpulse_social_split_sessions_close_attempts_total)"
after_close_blocked="$(metric bankpulse_social_split_sessions_close_blocked_total)"

after_duration_count="$(metric bankpulse_social_split_sessions_close_duration_seconds_count)"
after_duration_sum="$(metric bankpulse_social_split_sessions_close_duration_seconds_sum)"

after_valid="$(metric bankpulse_social_split_settlements_valid_total)"
after_invalid="$(metric bankpulse_social_split_settlements_invalid_total)"

initiated_delta="$(delta_int "$after_initiated" "$before_initiated")"
completed_delta="$(delta_int "$after_completed" "$before_completed")"

added_delta="$(delta_int "$after_added" "$before_added")"
authorized_delta="$(delta_int "$after_authorized" "$before_authorized")"

close_attempts_delta="$(
  delta_int "$after_close_attempts" "$before_close_attempts"
)"

close_blocked_delta="$(
  delta_int "$after_close_blocked" "$before_close_blocked"
)"

duration_count_delta="$(
  delta_int "$after_duration_count" "$before_duration_count"
)"

duration_sum_delta="$(
  delta_float "$after_duration_sum" "$before_duration_sum"
)"

valid_delta="$(delta_int "$after_valid" "$before_valid")"
invalid_delta="$(delta_int "$after_invalid" "$before_invalid")"

kpi_1="$(
  percentage "$completed_delta" "$initiated_delta"
)"

kpi_2="$(
  percentage "$authorized_delta" "$added_delta"
)"

kpi_4="$(
  percentage "$close_blocked_delta" "$close_attempts_delta"
)"

settlement_total="$(
  awk -v valid="$valid_delta" -v invalid="$invalid_delta" \
    'BEGIN {printf "%.0f", valid + invalid}'
)"

kpi_5="$(
  percentage "$valid_delta" "$settlement_total"
)"

kpi_3="$(
  awk \
    -v seconds="$duration_sum_delta" \
    -v count="$duration_count_delta" \
    'BEGIN {
      if (count == 0) {
        printf "0.000"
      } else {
        printf "%.3f", seconds / count
      }
    }'
)"

echo
echo "KPI 1 - Successful completion rate : ${kpi_1}%"
echo "KPI 2 - Participant adoption rate  : ${kpi_2}%"
echo "KPI 3 - Average completion time    : ${kpi_3}s"
echo "KPI 4 - Protected close rate       : ${kpi_4}%"
echo "KPI 5 - Settlement integrity       : ${kpi_5}%"

echo
echo "[8/8] Validate KPI expectations"

test "$initiated_delta" -eq 1
test "$completed_delta" -eq 1

test "$added_delta" -eq 2
test "$authorized_delta" -eq 2

test "$close_attempts_delta" -eq 2
test "$close_blocked_delta" -eq 1

test "$duration_count_delta" -eq 1

test "$valid_delta" -eq 1
test "$invalid_delta" -eq 0

echo
echo "=============================================="
echo " KPI 1 PASS - Social Split completed"
echo " KPI 2 PASS - Participants authorized"
echo " KPI 3 PASS - Completion time observed"
echo " KPI 4 PASS - Premature close blocked"
echo " KPI 5 PASS - Financial distribution balanced"
echo "=============================================="
echo "BUSINESS KPI GATE: PASS"