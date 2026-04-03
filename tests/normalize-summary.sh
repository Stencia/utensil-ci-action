#!/usr/bin/env bash
set -euo pipefail

COUNT_FILTER='
  def security_findings:
    [.intelligence[]?
      | select(.category == "securityRisk" and ((.key // "") | endswith("Summary") | not))
    ];
  def run_summary:
    .runSummary // .summary // {};
  def dismissed_flag:
    .dismissedAtScanTime // .dismissed // .isDismissed // false;
  def reported_count:
    if (run_summary.reportedFindingCount? != null) then run_summary.reportedFindingCount
    elif (run_summary.findingCount? != null) then run_summary.findingCount
    else (security_findings | length)
    end;
  def dismissed_count:
    if (run_summary.dismissedFindingCount? != null) then run_summary.dismissedFindingCount
    else ([security_findings[] | select(dismissed_flag == true)] | length)
    end;
  def active_count:
    (
      if (run_summary.activeFindingCount? != null) then run_summary.activeFindingCount
      elif (run_summary.findingCount? != null and run_summary.dismissedFindingCount? != null) then
        (run_summary.findingCount - run_summary.dismissedFindingCount)
      else (reported_count - dismissed_count)
      end
    ) | if . < 0 then 0 else . end;
  {
    reported: (reported_count // 0),
    active: (active_count // 0),
    dismissed: (dismissed_count // 0)
  }
'

assert_counts() {
  local json="$1"
  local expected="$2"
  local actual
  actual="$(jq -c "$COUNT_FILTER" <<<"$json")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $expected"
    echo "actual   $actual"
    return 1
  fi
}

assert_redaction() {
  local input="$1"
  local expected="$2"
  local redacted="$input"
  redacted="${redacted%%\?*}"
  redacted="${redacted%%\#*}"
  if [[ "$redacted" == *"://"* ]]; then
    local scheme="${redacted%%://*}"
    local rest="${redacted#*://}"
    local authority="${rest%%/*}"
    local path="/${rest#*/}"
    if [[ "$rest" == "$authority" ]]; then
      path=""
    fi
    authority="${authority##*@}"
    redacted="${scheme}://${authority}${path}"
  fi

  if [[ "$redacted" != "$expected" ]]; then
    echo "expected $expected"
    echo "actual   $redacted"
    return 1
  fi
}

assert_counts \
  '{"runSummary":{"reportedFindingCount":0,"activeFindingCount":0,"dismissedFindingCount":0},"intelligence":[]}' \
  '{"reported":0,"active":0,"dismissed":0}'

assert_counts \
  '{"runSummary":{"reportedFindingCount":1,"dismissedFindingCount":3},"intelligence":[]}' \
  '{"reported":1,"active":0,"dismissed":3}'

assert_counts \
  '{"findingCount":2,"intelligence":[{"category":"securityRisk","key":"js-eval","dismissedAtScanTime":true},{"category":"securityRisk","key":"js-innerhtml"},{"category":"securityRisk","key":"jsSummary"}]}' \
  '{"reported":2,"active":1,"dismissed":1}'

assert_redaction \
  'https://token@example.com/api/ingest?license=secret#frag' \
  'https://example.com/api/ingest'

echo "normalize-summary tests passed"
