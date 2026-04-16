#!/usr/bin/env bash
# Unit tests for hosted scan-config resolution used by action.yml.

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
    -w)
      shift 2
      ;;
    --max-time|-H)
      shift 2
      ;;
    -sS)
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
    printf '%s' "$MOCK_BODY" > "$out"
    printf '200'
    ;;
  404)
    printf '{}' > "$out"
    printf '404'
    ;;
  fail)
    exit 28
    ;;
esac
MOCK
chmod +x "$MOCK_CURL"

run_resolver() {
  RUNNER_TEMP="$TMPDIR" \
  CURL_BIN="$MOCK_CURL" \
  MOCK_CURL_COUNT="$TMPDIR/curl-count" \
  MOCK_HTTP="${MOCK_HTTP:-200}" \
  MOCK_BODY="${MOCK_BODY:-}" \
  INPUT_FETCH_SCAN_CONFIG="${INPUT_FETCH_SCAN_CONFIG:-true}" \
  UTENSIL_SCAN_CONFIG_URL="${UTENSIL_SCAN_CONFIG_URL:-https://api.utensil.tools/api/scan-config}" \
  INPUT_DEBIAN_SUITE="${INPUT_DEBIAN_SUITE:-}" \
  INPUT_DEBIAN_ARCH="${INPUT_DEBIAN_ARCH:-}" \
  INPUT_NATIVE_RESOLVERS="${INPUT_NATIVE_RESOLVERS:-}" \
  REPO_OWNER="vyos" \
  REPO_NAME="vyos-1x" \
  UTENSIL_LICENSE_TOKEN="${UTENSIL_LICENSE_TOKEN:-token}" \
  "$ROOT/scripts/resolve-scan-config.sh"
}

echo "Scan config resolution tests"
echo ""

echo "Explicit inputs override hosted config:"
MOCK_HTTP=200
MOCK_BODY='{"debianSuite":"trixie","debianArch":"arm64","nativeResolversEnabled":true}'
INPUT_DEBIAN_SUITE="bookworm"
INPUT_DEBIAN_ARCH=""
INPUT_NATIVE_RESOLVERS="false"
RESULT=$(run_resolver)
[ "$(jq -r '.debianSuite' <<< "$RESULT")" = "bookworm" ] && pass "explicit suite wins" || fail "explicit suite was not preserved"
[ "$(jq -r '.debianArch' <<< "$RESULT")" = "arm64" ] && pass "hosted arch fills unset input" || fail "hosted arch did not apply"
[ "$(jq -r '.nativeResolversEnabled' <<< "$RESULT")" = "false" ] && pass "explicit native false wins" || fail "native false was overwritten"
[ "$(jq -r '.scanTargetSource' <<< "$RESULT")" = "explicit" ] && pass "source is explicit" || fail "source was not explicit"

echo ""
echo "Missing hosted config:"
MOCK_HTTP=404
MOCK_BODY='{}'
INPUT_DEBIAN_SUITE=""
INPUT_DEBIAN_ARCH=""
INPUT_NATIVE_RESOLVERS=""
UTENSIL_SCAN_CONFIG_URL=""
RESULT=$(run_resolver)
[ "$(jq -r '.configFetchStatus' <<< "$RESULT")" = "missing" ] && pass "404 maps to missing" || fail "404 did not map to missing"

echo ""
echo "Native-only hosted config:"
MOCK_HTTP=200
MOCK_BODY='{"nativeResolversEnabled":true}'
UTENSIL_SCAN_CONFIG_URL="https://api.utensil.tools/api/scan-config"
RESULT=$(run_resolver)
[ "$(jq -r '.nativeResolversEnabled' <<< "$RESULT")" = "true" ] && pass "hosted native setting applies" || fail "hosted native setting did not apply"
[ "$(jq -r '.scanTargetSource' <<< "$RESULT")" = "stored" ] && pass "native-only config marks source stored" || fail "native-only source was not stored"

echo ""
echo "Untrusted URL is skipped without token exfiltration:"
rm -f "$TMPDIR/curl-count"
MOCK_HTTP=200
MOCK_BODY='{"debianSuite":"trixie"}'
UTENSIL_SCAN_CONFIG_URL="https://evil.example/api/scan-config"
RESULT=$(run_resolver)
[ "$(jq -r '.configFetchStatus' <<< "$RESULT")" = "skipped_untrusted_url" ] && pass "untrusted URL skipped" || fail "untrusted URL was not skipped"
[ ! -f "$TMPDIR/curl-count" ] && pass "curl not called for untrusted URL" || fail "curl was called for untrusted URL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit "$FAIL"
