#!/usr/bin/env bash
# Unit tests for the PR comment findings-table formatting in action.yml.
#
# Run: bash tests/test-pr-comment-format.sh

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

comment_rows() {
  local response="$1"
  while IFS=$'\t' read -r ruleLabel filePath severity verdict; do
    ruleLabel=${ruleLabel//|/\\|}
    filePath=${filePath//|/\\|}
    severity=${severity//|/\\|}
    verdict=${verdict//|/\\|}
    printf '%s\t%s\t%s\t%s\n' "$ruleLabel" "$filePath" "$severity" "$verdict"
  done < <(jq -r -f "$REPO_ROOT/scripts/pr-comment-findings-table.jq" "$response")
}

echo "PR comment format tests"
echo ""

echo "PII findings use user-facing labels:"
RESPONSE=$(make_response '[
  {
    "key": "piiEmail",
    "filePath": "config/app.env",
    "severity": "low",
    "aiVerdict": "context_dependent",
    "evidence": [
      {"type": "inference", "reason": "Severity: Low. Email address"}
    ]
  }
]')
ROWS=$(comment_rows "$RESPONSE")
[[ "$ROWS" == $'Email address\tconfig/app.env\tlow\tReview' ]] \
  && pass "uses inferred display label for PII findings" \
  || fail "expected Email address row, got: $ROWS"

echo ""
echo "Security-rule findings use the rule title, not the internal key:"
RESPONSE=$(make_response '[
  {
    "key": "go-sql-concat",
    "filePath": "server/query.go",
    "severity": "high",
    "aiVerdict": "real_risk",
    "evidence": [
      {"type": "inference", "reason": "Severity: High. SQL injection via string concatenation. CWE-89. Query built from string interpolation"}
    ]
  }
]')
ROWS=$(comment_rows "$RESPONSE")
[[ "$ROWS" == $'SQL injection via string concatenation\tserver/query.go\thigh\tRisk' ]] \
  && pass "uses rule title from severity inference" \
  || fail "expected rule-title row, got: $ROWS"

echo ""
echo "Dotted API names are preserved in inferred labels:"
RESPONSE=$(make_response '[
  {
    "key": "py-tempfile-mktemp",
    "filePath": "scripts/build.py",
    "severity": "high",
    "aiVerdict": "real_risk",
    "evidence": [
      {"type": "inference", "reason": "Severity: High. Insecure usage of tempfile.mktemp(). Predictable temporary filename can be guessed."}
    ]
  }
]')
ROWS=$(comment_rows "$RESPONSE")
[[ "$ROWS" == $'Insecure usage of tempfile.mktemp()\tscripts/build.py\thigh\tRisk' ]] \
  && pass "keeps dotted API names in inferred titles" \
  || fail "expected dotted API title row, got: $ROWS"

echo ""
echo "Resolution order prefers the most user-facing metadata:"
RESPONSE=$(make_response '[
  {
    "displayName": "Display wins",
    "title": "Title fallback",
    "ruleLabel": "RuleLabel fallback",
    "key": "internal-key",
    "filePath": "src/order.swift",
    "severity": "low",
    "aiVerdict": "context_dependent"
  },
  {
    "title": "Title wins",
    "ruleLabel": "RuleLabel fallback",
    "key": "internal-key-2",
    "filePath": "src/order-two.swift",
    "severity": "medium",
    "aiVerdict": "real_risk"
  },
  {
    "ruleLabel": "RuleLabel wins",
    "key": "internal-key-3",
    "filePath": "src/order-three.swift",
    "severity": "high",
    "aiVerdict": "context_dependent"
  }
]')
ROWS=$(comment_rows "$RESPONSE")
EXPECTED=$'Display wins\tsrc/order.swift\tlow\tReview\nTitle wins\tsrc/order-two.swift\tmedium\tRisk\nRuleLabel wins\tsrc/order-three.swift\thigh\tReview'
[[ "$ROWS" == "$EXPECTED" ]] \
  && pass "prefers displayName, title, and ruleLabel before deeper fallbacks" \
  || fail "expected precedence rows, got: $ROWS"

echo ""
echo "Fallback to key when no user-facing label is available:"
RESPONSE=$(make_response '[
  {
    "key": "custom-rule-key",
    "filePath": "src/main.swift",
    "severity": "medium",
    "aiVerdict": "real_risk"
  }
]')
ROWS=$(comment_rows "$RESPONSE")
[[ "$ROWS" == $'custom-rule-key\tsrc/main.swift\tmedium\tRisk' ]] \
  && pass "falls back to key when metadata is absent" \
  || fail "expected fallback row, got: $ROWS"

echo ""
echo "Markdown table cells are sanitized before rendering:"
RESPONSE=$(make_response '[
  {
    "displayName": "PII | secrets\nsummary",
    "key": "pii-summary",
    "filePath": "docs/notes.md",
    "severity": "medium",
    "aiVerdict": "context_dependent"
  }
]')
ROWS=$(comment_rows "$RESPONSE")
[[ "$ROWS" == $'PII \\| secrets summary\tdocs/notes.md\tmedium\tReview' ]] \
  && pass "escapes markdown pipes and flattens line breaks" \
  || fail "expected sanitized markdown cell, got: $ROWS"

echo ""
echo "Only actionable verdicts render table rows:"
RESPONSE=$(make_response '[
  {
    "displayName": "Actionable risk",
    "filePath": "src/risk.swift",
    "severity": "high",
    "aiVerdict": "real_risk"
  },
  {
    "displayName": "Needs review",
    "filePath": "src/review.swift",
    "severity": "medium",
    "aiVerdict": "context_dependent"
  },
  {
    "displayName": "Dismissed finding",
    "filePath": "src/dismissed.swift",
    "severity": "low",
    "aiVerdict": "false_positive"
  },
  {
    "displayName": "Missing verdict",
    "filePath": "src/missing.swift",
    "severity": "low"
  }
]')
ROWS=$(comment_rows "$RESPONSE")
EXPECTED=$'Actionable risk\tsrc/risk.swift\thigh\tRisk\nNeeds review\tsrc/review.swift\tmedium\tReview'
[[ "$ROWS" == "$EXPECTED" ]] \
  && pass "renders only real_risk and context_dependent findings" \
  || fail "expected only actionable rows, got: $ROWS"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
