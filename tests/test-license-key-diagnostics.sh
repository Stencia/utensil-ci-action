#!/usr/bin/env bash
# Unit tests for the CI license-key diagnostics used by action.yml.
#
# Run: bash tests/test-license-key-diagnostics.sh

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

diagnose_license_key() {
  LICENSE_KEY_STATUS=""
  LICENSE_KEY_HINT=""

  if [ -z "${UTENSIL_LICENSE_KEY:-}" ]; then
    LICENSE_KEY_STATUS="missing"
    LICENSE_KEY_HINT="The 'license-key' input is empty."
    return 0
  fi

  case "$UTENSIL_LICENSE_KEY" in
    *.*) ;;
    *)
      LICENSE_KEY_STATUS="malformed"
      LICENSE_KEY_HINT="The supplied Utensil license key is malformed."
      return 0
      ;;
  esac

  KEY_PAYLOAD=$(printf '%s' "$UTENSIL_LICENSE_KEY" | cut -d. -f1)
  if [ -z "$KEY_PAYLOAD" ]; then
    LICENSE_KEY_STATUS="malformed"
    LICENSE_KEY_HINT="The supplied Utensil license key is malformed."
    return 0
  fi

  KEY_JSON=$(printf '%s' "$KEY_PAYLOAD" | b64_decode 2>/dev/null || true)
  if [ -z "$KEY_JSON" ] || ! echo "$KEY_JSON" | jq -e '.kind == "license_key" and ((.jti? // "") != "")' >/dev/null 2>&1; then
    LICENSE_KEY_STATUS="wrong_kind"
    LICENSE_KEY_HINT="The supplied credential is not a current Utensil license key. Run 'utensil login --force' and store the new key in UTENSIL_LICENSE_KEY."
    return 0
  fi

  EXP=$(echo "$KEY_JSON" | jq -r '.exp // empty')
  NOW=$(date +%s)
  if [ -n "$EXP" ] && [ "$EXP" != "null" ] && [ "$NOW" -ge "$EXP" ]; then
    LICENSE_KEY_STATUS="expired"
    LICENSE_KEY_HINT="The supplied Utensil license key expired on $(token_deadline_iso "$EXP")."
  fi
}

make_token() {
  local payload="$1"
  local encoder="${2:-b64_encode}"
  printf '%s.%s' "$(printf '%s' "$payload" | "$encoder")" "signature"
}

echo "License key diagnostics tests"
echo ""

echo "Missing key:"
unset UTENSIL_LICENSE_KEY || true
diagnose_license_key
[ "$LICENSE_KEY_STATUS" = "missing" ] && pass "missing key classified" || fail "expected missing, got $LICENSE_KEY_STATUS"
[ "$LICENSE_KEY_HINT" = "The 'license-key' input is empty." ] && pass "missing key hint" || fail "unexpected missing hint: $LICENSE_KEY_HINT"

echo ""
echo "Malformed key:"
UTENSIL_LICENSE_KEY="not-a-key"
diagnose_license_key
[ "$LICENSE_KEY_STATUS" = "malformed" ] && pass "malformed key classified" || fail "expected malformed, got $LICENSE_KEY_STATUS"

echo ""
echo "Base64url key:"
BASE64URL_PAYLOAD='{"kind":"license_key","jti":"key-123","m":"Jo?"}'
UTENSIL_LICENSE_KEY=$(make_token "$BASE64URL_PAYLOAD" b64url_encode)
diagnose_license_key
[ -z "$LICENSE_KEY_STATUS" ] && pass "base64url key decodes without diagnostics" || fail "expected empty status for base64url key, got $LICENSE_KEY_STATUS"
[ -z "$LICENSE_KEY_HINT" ] && pass "base64url key hint empty" || fail "expected empty hint for base64url key, got $LICENSE_KEY_HINT"

echo ""
echo "Legacy access token:"
ACCESS_TOKEN_PAYLOAD='{"kind":"access_token","exp":4102444800,"grace":0}'
UTENSIL_LICENSE_KEY=$(make_token "$ACCESS_TOKEN_PAYLOAD" b64url_encode)
diagnose_license_key
[ "$LICENSE_KEY_STATUS" = "wrong_kind" ] && pass "access token rejected as license key" || fail "expected wrong_kind, got $LICENSE_KEY_STATUS"

echo ""
echo "Expired key:"
NOW=$(date +%s)
EXPIRED_PAYLOAD=$(jq -nc --argjson exp "$((NOW - 10))" '{kind: "license_key", jti: "expired-key", exp: $exp}')
UTENSIL_LICENSE_KEY=$(make_token "$EXPIRED_PAYLOAD")
diagnose_license_key
[ "$LICENSE_KEY_STATUS" = "expired" ] && pass "expired key classified" || fail "expected expired, got $LICENSE_KEY_STATUS"
printf '%s' "$LICENSE_KEY_HINT" | grep -q "expired on" && pass "expired key hint includes deadline" || fail "expired key hint missing deadline"

echo ""
echo "Valid unexpired key:"
FRESH_PAYLOAD=$(jq -nc --argjson exp "$((NOW + 3600))" '{kind: "license_key", jti: "fresh-key", exp: $exp}')
UTENSIL_LICENSE_KEY=$(make_token "$FRESH_PAYLOAD")
diagnose_license_key
[ -z "$LICENSE_KEY_STATUS" ] && pass "fresh key not flagged" || fail "expected empty status, got $LICENSE_KEY_STATUS"
[ -z "$LICENSE_KEY_HINT" ] && pass "fresh key hint empty" || fail "expected empty hint, got $LICENSE_KEY_HINT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
