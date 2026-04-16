#!/usr/bin/env bash
# Unit tests for the parse-results logic extracted from action.yml.
# Tests vulnerability and finding counts from the parsed report.
#
# Run: bash tests/test-parse-results.sh

set -euo pipefail

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Helper: create a mock report ---
make_report() {
  local findings="$1"
  cat > "$TMPDIR/report.json" << REPORT_EOF
{
  "vulnerabilities": { "vulnerablePackages": [] },
  "intelligence": $findings
}
REPORT_EOF
  echo "$TMPDIR/report.json"
}

# --- Helper: run the parse logic ---
parse_report() {
  local report="$1"
  if [ -f "$report" ]; then
    VULN_COUNT=$(jq '[.vulnerabilities.vulnerablePackages[]?.totalCount // 0] | add // 0' "$report" 2>/dev/null || echo 0)
    FINDING_COUNT=$(jq '[.intelligence[]? | select(.category == "securityRisk" and (.key | endswith("Summary") | not))] | length' "$report" 2>/dev/null || echo 0)
  else
    VULN_COUNT=0
    FINDING_COUNT=0
  fi
}

# ---- Tests ----

echo "Parse results tests"
echo ""

# Test 1: Empty intelligence array
echo "Empty report:"
REPORT=$(make_report '[]')
parse_report "$REPORT"
[ "$FINDING_COUNT" -eq 0 ] && pass "zero findings" || fail "expected 0, got $FINDING_COUNT"
[ "$VULN_COUNT" -eq 0 ] && pass "zero vulns" || fail "expected 0 vulns, got $VULN_COUNT"

# Test 2: One security finding
echo ""
echo "One security finding:"
REPORT=$(make_report '[
  {"category": "securityRisk", "key": "piiDatabaseCredentials", "value": 1,
   "evidence": [{"type": "sourceFile", "filePath": "scripts/migrate.py", "lineNumber": 6}]}
]')
parse_report "$REPORT"
[ "$FINDING_COUNT" -eq 1 ] && pass "one finding" || fail "expected 1, got $FINDING_COUNT"

# Test 3: Summary findings excluded
echo ""
echo "Summary findings excluded:"
REPORT=$(make_report '[
  {"category": "securityRisk", "key": "swiftSecuritySummary", "value": "clean"},
  {"category": "securityRisk", "key": "goSecuritySummary", "value": "review"},
  {"category": "securityRisk", "key": "swift-weak-hash", "value": 1}
]')
parse_report "$REPORT"
[ "$FINDING_COUNT" -eq 1 ] && pass "summaries excluded, 1 real finding" || fail "expected 1, got $FINDING_COUNT"

# Test 4: Non-security findings excluded
echo ""
echo "Non-security findings excluded:"
REPORT=$(make_report '[
  {"category": "repoCharacteristics", "key": "repoType", "value": "app"},
  {"category": "securityRisk", "key": "go-sql-concat", "value": 2}
]')
parse_report "$REPORT"
[ "$FINDING_COUNT" -eq 1 ] && pass "non-security excluded, 1 finding" || fail "expected 1, got $FINDING_COUNT"

# Test 5: Multiple findings
echo ""
echo "Multiple findings:"
REPORT=$(make_report '[
  {"category": "securityRisk", "key": "piiDatabaseCredentials", "value": 1},
  {"category": "securityRisk", "key": "swift-weak-hash", "value": 1},
  {"category": "securityRisk", "key": "go-sql-concat", "value": 2},
  {"category": "securityRisk", "key": "goSecuritySummary", "value": "review"}
]')
parse_report "$REPORT"
[ "$FINDING_COUNT" -eq 3 ] && pass "3 findings (summary excluded)" || fail "expected 3, got $FINDING_COUNT"

# Test 6: Missing report file
echo ""
echo "Missing report file:"
parse_report "/nonexistent/report.json"
[ "$FINDING_COUNT" -eq 0 ] && pass "zero findings for missing file" || fail "expected 0, got $FINDING_COUNT"

# Test 7: Vulnerability count
echo ""
echo "Vulnerability count:"
cat > "$TMPDIR/vuln-report.json" << 'EOF'
{
  "vulnerabilities": {
    "vulnerablePackages": [
      {"totalCount": 3},
      {"totalCount": 2}
    ]
  },
  "intelligence": []
}
EOF
parse_report "$TMPDIR/vuln-report.json"
[ "$VULN_COUNT" -eq 5 ] && pass "5 total vulns" || fail "expected 5, got $VULN_COUNT"
[ "$FINDING_COUNT" -eq 0 ] && pass "zero findings" || fail "expected 0 findings, got $FINDING_COUNT"

# Test 8: has-findings flag
echo ""
echo "has-findings flag:"
REPORT=$(make_report '[{"category": "securityRisk", "key": "test-rule", "value": 1}]')
parse_report "$REPORT"
if [ "$FINDING_COUNT" -gt 0 ]; then
  HAS_FINDINGS="true"
else
  HAS_FINDINGS="false"
fi
[ "$HAS_FINDINGS" = "true" ] && pass "has-findings is true when findings > 0" || fail "expected has-findings=true, got $HAS_FINDINGS"

REPORT=$(make_report '[]')
parse_report "$REPORT"
if [ "$FINDING_COUNT" -gt 0 ]; then
  HAS_FINDINGS="true"
else
  HAS_FINDINGS="false"
fi
[ "$HAS_FINDINGS" = "false" ] && pass "has-findings is false when findings = 0" || fail "expected has-findings=false, got $HAS_FINDINGS"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
