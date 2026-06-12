#!/usr/bin/env bash
# Unit tests for the license-key to access-token exchange helper.

set -euo pipefail

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

ROOT="$(CDPATH= cd -P -- "$(dirname "$0")/.." && pwd -P)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_CURL="$TMPDIR/curl"
cat > "$MOCK_CURL" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -w|--max-time|-H|--data-urlencode)
      shift 2
      ;;
    -sS|-X)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s\n' "called" >> "$MOCK_CURL_COUNT"
case "${MOCK_HTTP:-200}" in
  200)
    printf '%s' '{"access_token":"access-token-123","token_type":"Bearer","expires_in":3600}' > "$out"
    printf '200'
    ;;
  401)
    printf '%s' '{"error":"invalid_client","error_description":"License key invalid or revoked."}' > "$out"
    printf '401'
    ;;
  fail)
    exit 28
    ;;
esac
MOCK
chmod +x "$MOCK_CURL"

run_helper() {
  RUNNER_TEMP="$TMPDIR" \
  CURL_BIN="$MOCK_CURL" \
  MOCK_CURL_COUNT="$TMPDIR/curl-count" \
  MOCK_HTTP="${MOCK_HTTP:-200}" \
  UTENSIL_LICENSE_KEY="${UTENSIL_LICENSE_KEY-}" \
  UTENSIL_AUTH_TOKEN_URL="${UTENSIL_AUTH_TOKEN_URL-}" \
  "$ROOT/scripts/mint-access-token.sh"
}

echo "Access token mint tests"
echo ""

echo "Successful exchange:"
MOCK_HTTP=200
UTENSIL_LICENSE_KEY="license-key-123"
TOKEN=$(run_helper)
[ "$TOKEN" = "access-token-123" ] && pass "access token emitted" || fail "unexpected token: $TOKEN"
if compgen -G "$TMPDIR/utensil-access-token-response.*" > /dev/null; then
  fail "auth response file was not removed"
else
  pass "auth response file removed"
fi

echo ""
echo "Missing license key:"
UTENSIL_LICENSE_KEY=""
set +e
OUTPUT=$(run_helper 2>"$TMPDIR/missing.err")
STATUS=$?
set -e
[ "$STATUS" -eq 2 ] && pass "missing key exits 2" || fail "missing key exit was $STATUS"
grep -q "UTENSIL_LICENSE_KEY is empty" "$TMPDIR/missing.err" && pass "missing key message" || fail "missing key message absent"

echo ""
echo "Auth failure:"
MOCK_HTTP=401
UTENSIL_LICENSE_KEY="license-key-123"
set +e
OUTPUT=$(run_helper 2>"$TMPDIR/auth.err")
STATUS=$?
set -e
[ "$STATUS" -eq 1 ] && pass "auth failure exits 1" || fail "auth failure exit was $STATUS"
grep -q "License key invalid or revoked" "$TMPDIR/auth.err" && pass "auth failure message" || fail "auth failure message absent"

echo ""
echo "Untrusted URL:"
UTENSIL_LICENSE_KEY="license-key-123"
UTENSIL_AUTH_TOKEN_URL="https://evil.example/token"
set +e
OUTPUT=$(run_helper 2>"$TMPDIR/url.err")
STATUS=$?
set -e
unset UTENSIL_AUTH_TOKEN_URL
[ "$STATUS" -eq 2 ] && pass "untrusted URL exits 2" || fail "untrusted URL exit was $STATUS"
grep -q "Refusing untrusted" "$TMPDIR/url.err" && pass "untrusted URL message" || fail "untrusted URL message absent"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit "$FAIL"
