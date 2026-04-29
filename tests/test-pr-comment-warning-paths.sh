#!/usr/bin/env bash
# Regression tests for the PR comment table warning paths in action.yml.
#
# Run: bash tests/test-pr-comment-warning-paths.sh

set -euo pipefail

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_response() {
  local findings="$1"
  cat > "$TMPDIR/response.json" << RESPONSE_EOF
{
  "findings": $findings
}
RESPONSE_EOF
  echo "$TMPDIR/response.json"
}

extract_warning_guard() {
  awk '
    /if \[ ! -f "\$FORMATTER_JQ" \]; then/ {capture=1}
    capture {
      sub(/^ {12}/, "")
      print
      if ($0 == "fi") exit
    }
  ' "$REPO_ROOT/action.yml"
}

make_warning_guard_runner() {
  local runner="$TMPDIR/render-warning-guard.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'COMMENT="${COMMENT:-}"'
    extract_warning_guard
    echo 'printf "__COMMENT__%s\n" "$COMMENT"'
  } > "$runner"
  chmod +x "$runner"
  echo "$runner"
}

run_warning_guard() {
  local runner="$1"
  local response="$2"
  local formatter="$3"
  RESPONSE="$response" FORMATTER_JQ="$formatter" COMMENT="seed" bash "$runner" 2>&1
}

echo "PR comment warning-path tests"
echo ""

RUNNER=$(make_warning_guard_runner)
RESPONSE=$(make_response '[
  {
    "displayName": "Actionable risk",
    "filePath": "src/risk.swift",
    "severity": "high",
    "aiVerdict": "real_risk"
  }
]')

echo "Missing formatter file emits a warning and preserves the comment buffer:"
OUT=$(run_warning_guard "$RUNNER" "$RESPONSE" "$TMPDIR/missing-formatter.jq")
[[ "$OUT" == *"::warning::Missing PR comment formatter script at $TMPDIR/missing-formatter.jq"* ]] \
  && pass "warns when the formatter file is missing" \
  || fail "expected missing-formatter warning, got: $OUT"
[[ "$OUT" == *"__COMMENT__seed"* ]] \
  && pass "does not append rows when the formatter file is missing" \
  || fail "expected unchanged comment buffer, got: $OUT"

echo ""
echo "Broken formatter file emits a warning and preserves the comment buffer:"
cat > "$TMPDIR/bad-formatter.jq" <<'BAD_JQ'
def broken:
BAD_JQ
OUT=$(run_warning_guard "$RUNNER" "$RESPONSE" "$TMPDIR/bad-formatter.jq")
[[ "$OUT" == *"::warning::Failed to render PR comment findings table with $TMPDIR/bad-formatter.jq"* ]] \
  && pass "warns when jq cannot render the formatter" \
  || fail "expected failed-render warning, got: $OUT"
[[ "$OUT" == *"__COMMENT__seed"* ]] \
  && pass "does not append rows when jq rendering fails" \
  || fail "expected unchanged comment buffer after jq failure, got: $OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
