#!/usr/bin/env bash
# Unit tests for the scan-argument assembly used by action.yml.

set -euo pipefail

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

EXTRA_ARGS=()

extra_args_contain() {
  local needle="$1"
  local arg
  if [ "${#EXTRA_ARGS[@]}" -eq 0 ]; then
    return 1
  fi
  for arg in "${EXTRA_ARGS[@]}"; do
    if [ "$arg" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

build_args() {
  local input_full="$1"
  local effective_debian_suite="$2"
  local effective_debian_arch="$3"
  local effective_native_resolvers="$4"
  local scan_target_source="$5"
  local input_fail_on="$6"
  local input_args="$7"

  EXTRA_ARGS=()
  if [ -n "$input_args" ]; then
    read -r -a EXTRA_ARGS <<< "$input_args"
  fi

  local args=(--json)
  if [ "$input_full" = "true" ]; then args+=(--full); fi
  if [ -n "$effective_debian_suite" ] && ! extra_args_contain "--debian-suite"; then args+=(--debian-suite "$effective_debian_suite"); fi
  if [ -n "$effective_debian_arch" ] && ! extra_args_contain "--debian-arch"; then args+=(--debian-arch "$effective_debian_arch"); fi
  if [ "$effective_native_resolvers" = "true" ] && ! extra_args_contain "--native-resolvers"; then args+=(--native-resolvers); fi
  if [ -n "$scan_target_source" ] && ! extra_args_contain "--scan-target-source"; then args+=(--scan-target-source "$scan_target_source"); fi
  if [ -n "$input_fail_on" ]; then args+=(--fail-on "$input_fail_on"); fi
  if [ "${#EXTRA_ARGS[@]}" -gt 0 ]; then args+=("${EXTRA_ARGS[@]}"); fi

  printf '%s\n' "${args[@]}"
}

echo "Scan argument assembly tests"
echo ""

echo "Args override scan target defaults without duplicate flags:"
RESULT=$(build_args false bookworm amd64 true stored "" "--debian-suite bullseye --scan-target-source explicit")
[ "$(printf '%s\n' "$RESULT" | grep -c '^--debian-suite$')" -eq 1 ] && pass "debian-suite only appears once" || fail "expected one --debian-suite flag"
[ "$(printf '%s\n' "$RESULT" | grep -c '^--scan-target-source$')" -eq 1 ] && pass "scan-target-source only appears once" || fail "expected one --scan-target-source flag"
printf '%s\n' "$RESULT" | grep -qx 'bullseye' && pass "args-provided suite survives" || fail "args-provided suite missing"
printf '%s\n' "$RESULT" | grep -qx 'explicit' && pass "args-provided source survives" || fail "args-provided source missing"
! printf '%s\n' "$RESULT" | grep -qx 'bookworm' && pass "stored suite is not duplicated" || fail "stored suite should not be present"
! printf '%s\n' "$RESULT" | grep -qx 'stored' && pass "stored source is not duplicated" || fail "stored source should not be present"

echo ""
echo "Hosted defaults still apply when args do not override them:"
RESULT=$(build_args false bookworm amd64 true stored critical "")
printf '%s\n' "$RESULT" | grep -qx 'bookworm' && pass "hosted suite applied" || fail "hosted suite missing"
printf '%s\n' "$RESULT" | grep -qx 'amd64' && pass "hosted arch applied" || fail "hosted arch missing"
printf '%s\n' "$RESULT" | grep -qx 'stored' && pass "hosted source applied" || fail "hosted source missing"
printf '%s\n' "$RESULT" | grep -qx 'critical' && pass "fail-on preserved" || fail "fail-on missing"
[ "$(printf '%s\n' "$RESULT" | grep -c '^--native-resolvers$')" -eq 1 ] && pass "native-resolvers added once" || fail "expected one --native-resolvers flag"

echo ""
echo "Args-provided native-resolvers suppresses duplicate injection:"
RESULT=$(build_args false bookworm amd64 true stored "" "--native-resolvers")
[ "$(printf '%s\n' "$RESULT" | grep -c '^--native-resolvers$')" -eq 1 ] && pass "native-resolvers only appears once" || fail "expected one --native-resolvers flag"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit "$FAIL"
