#!/usr/bin/env bash
# Unit tests for the CI license-token diagnostics used by action.yml.
#
# Run: bash tests/test-license-token-diagnostics.sh

set -euo pipefail

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

b64_decode() {
  local input normalized remainder
  input="$(cat)"
  normalized="$(printf '%s' "$input" | tr -d '\r\n' | tr '_-' '/+')"

  remainder=$((${#normalized} % 4))
  if [ "$remainder" -eq 1 ]; then
    return 1
  elif [ "$remainder" -eq 2 ]; then
    normalized="${normalized}=="
  elif [ "$remainder" -eq 3 ]; then
    normalized="${normalized}="
  fi

  if base64 --help 2>/dev/null | grep -q -- '--decode'; then
    printf '%s' "$normalized" | base64 --decode
  else
    printf '%s' "$normalized" | base64 -D
  fi
}

b64_encode() {
  base64 | tr -d '\n'
}

b64url_encode() {
  base64 | tr -d '\n=' | tr '+/' '-_'
}

token_deadline_iso() {
  local deadline="$1"
  if date -u -r "$deadline" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    date -u -r "$deadline" '+%Y-%m-%dT%H:%M:%SZ'
  elif date -u -d "@$deadline" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    date -u -d "@$deadline" '+%Y-%m-%dT%H:%M:%SZ'
  else
    printf '%s' "$deadline"
  fi
}

diagnose_license_token() {
  LICENSE_TOKEN_STATUS=""
  LICENSE_TOKEN_HINT=""

  if [ -z "${UTENSIL_LICENSE_TOKEN:-}" ]; then
    LICENSE_TOKEN_STATUS="missing"
    LICENSE_TOKEN_HINT="The 'license-token' input is empty."
    return 0
  fi

  case "$UTENSIL_LICENSE_TOKEN" in
    *.*) ;;
    *)
      LICENSE_TOKEN_STATUS="malformed"
      LICENSE_TOKEN_HINT="The supplied Utensil license token is malformed."
      return 0
      ;;
  esac

  TOKEN_PAYLOAD=$(printf '%s' "$UTENSIL_LICENSE_TOKEN" | cut -d. -f1)
  if [ -z "$TOKEN_PAYLOAD" ]; then
    LICENSE_TOKEN_STATUS="malformed"
    LICENSE_TOKEN_HINT="The supplied Utensil license token is malformed."
    return 0
  fi

  TOKEN_JSON=$(printf '%s' "$TOKEN_PAYLOAD" | b64_decode 2>/dev/null || true)
  if [ -z "$TOKEN_JSON" ] || ! echo "$TOKEN_JSON" | jq -e '.exp? != null and .grace? != null' >/dev/null 2>&1; then
    LICENSE_TOKEN_STATUS="unreadable"
    LICENSE_TOKEN_HINT="The supplied Utensil license token could not be decoded for diagnostics."
    return 0
  fi

  EXP=$(echo "$TOKEN_JSON" | jq -r '.exp // empty')
  GRACE=$(echo "$TOKEN_JSON" | jq -r '.grace // 0')
  NOW=$(date +%s)
  if [ -n "$EXP" ] && [ "$EXP" != "null" ] && [ "$NOW" -ge $((EXP + GRACE)) ]; then
    LICENSE_TOKEN_STATUS="expired"
    LICENSE_TOKEN_HINT="The supplied Utensil license token expired on $(token_deadline_iso $((EXP + GRACE)))."
  fi
}

make_token() {
  local payload="$1"
  local encoder="${2:-b64_encode}"
  printf '%s.%s' "$(printf '%s' "$payload" | "$encoder")" "signature"
}

echo "License token diagnostics tests"
echo ""

echo "Missing token:"
unset UTENSIL_LICENSE_TOKEN || true
diagnose_license_token
[ "$LICENSE_TOKEN_STATUS" = "missing" ] && pass "missing token classified" || fail "expected missing, got $LICENSE_TOKEN_STATUS"
[ "$LICENSE_TOKEN_HINT" = "The 'license-token' input is empty." ] && pass "missing token hint" || fail "unexpected missing hint: $LICENSE_TOKEN_HINT"

echo ""
echo "Malformed token:"
UTENSIL_LICENSE_TOKEN="not-a-token"
diagnose_license_token
[ "$LICENSE_TOKEN_STATUS" = "malformed" ] && pass "malformed token classified" || fail "expected malformed, got $LICENSE_TOKEN_STATUS"

echo ""
echo "Base64url token:"
BASE64URL_PAYLOAD='{"exp":4102444800,"grace":0,"m":"Jo?"}'
UTENSIL_LICENSE_TOKEN=$(make_token "$BASE64URL_PAYLOAD" b64url_encode)
diagnose_license_token
[ -z "$LICENSE_TOKEN_STATUS" ] && pass "base64url token decodes without diagnostics" || fail "expected empty status for base64url token, got $LICENSE_TOKEN_STATUS"
[ -z "$LICENSE_TOKEN_HINT" ] && pass "base64url token hint empty" || fail "expected empty hint for base64url token, got $LICENSE_TOKEN_HINT"

echo ""
echo "Expired token:"
NOW=$(date +%s)
EXPIRED_PAYLOAD=$(jq -nc --argjson exp "$((NOW - 10))" --argjson grace 0 '{exp: $exp, grace: $grace}')
UTENSIL_LICENSE_TOKEN=$(make_token "$EXPIRED_PAYLOAD")
diagnose_license_token
[ "$LICENSE_TOKEN_STATUS" = "expired" ] && pass "expired token classified" || fail "expected expired, got $LICENSE_TOKEN_STATUS"
printf '%s' "$LICENSE_TOKEN_HINT" | grep -q "expired on" && pass "expired token hint includes deadline" || fail "expired token hint missing deadline"

echo ""
echo "Valid unexpired token:"
FRESH_PAYLOAD=$(jq -nc --argjson exp "$((NOW + 3600))" --argjson grace 3600 '{exp: $exp, grace: $grace}')
UTENSIL_LICENSE_TOKEN=$(make_token "$FRESH_PAYLOAD")
diagnose_license_token
[ -z "$LICENSE_TOKEN_STATUS" ] && pass "fresh token not flagged" || fail "expected empty status, got $LICENSE_TOKEN_STATUS"
[ -z "$LICENSE_TOKEN_HINT" ] && pass "fresh token hint empty" || fail "expected empty hint, got $LICENSE_TOKEN_HINT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
