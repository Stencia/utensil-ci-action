#!/usr/bin/env bash
# Tests for scripts/install-dependencies.sh
#
# Covers the lockfile-discovery logic (find_lockfile_dir). The actual install
# commands (npm ci, yarn install, pnpm install) are not exercised here because
# they require network and a real project; those are integration-tested by
# running the action against live repos.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/../scripts/install-dependencies.sh"

# shellcheck source=../scripts/install-dependencies.sh
source "$INSTALL_SCRIPT"

PASS=0
FAIL=0

expect_eq() {
  if [ "$1" = "$2" ]; then
    echo "  PASS: $3"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $3"
    echo "    expected: $1"
    echo "    got:      $2"
    FAIL=$((FAIL + 1))
  fi
}

expect_nonzero() {
  if [ "$1" -ne 0 ]; then
    echo "  PASS: $2"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $2 (expected non-zero exit)"
    FAIL=$((FAIL + 1))
  fi
}

TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

echo "find_lockfile_dir"
echo "----------------"

# Scenario 1: lockfile in the scan directory itself
mkdir -p "$TMP/s1"
touch "$TMP/s1/package-lock.json"
result=$(find_lockfile_dir "$TMP/s1" "$TMP/s1")
expect_eq "$(cd "$TMP/s1" && pwd)"$'\t'"package-lock.json" "$result" "finds lockfile in scan dir"

# Scenario 2: monorepo with lockfile at workspace root, scan at package subdir
mkdir -p "$TMP/s2/packages/app"
touch "$TMP/s2/yarn.lock"
result=$(find_lockfile_dir "$TMP/s2/packages/app" "$TMP/s2")
expect_eq "$(cd "$TMP/s2" && pwd)"$'\t'"yarn.lock" "$result" "walks up to workspace root for monorepo scan"

# Scenario 3: no lockfile anywhere
mkdir -p "$TMP/s3/sub"
find_lockfile_dir "$TMP/s3/sub" "$TMP/s3" >/dev/null 2>&1
expect_nonzero $? "returns non-zero when no lockfile exists"

# Scenario 4: lockfile outside workspace boundary must not be picked up
mkdir -p "$TMP/s4/outside"
touch "$TMP/s4/outside/package-lock.json"
mkdir -p "$TMP/s4/inside/deep"
find_lockfile_dir "$TMP/s4/inside/deep" "$TMP/s4/inside" >/dev/null 2>&1
expect_nonzero $? "does not escape workspace boundary"

# Scenario 5: closest lockfile wins when multiple exist up the tree
mkdir -p "$TMP/s5/packages/app"
touch "$TMP/s5/package-lock.json"
touch "$TMP/s5/packages/app/yarn.lock"
result=$(find_lockfile_dir "$TMP/s5/packages/app" "$TMP/s5")
expect_eq "$(cd "$TMP/s5/packages/app" && pwd)"$'\t'"yarn.lock" "$result" "prefers closest lockfile to the scan dir"

# Scenario 6: pnpm-lock.yaml detection
mkdir -p "$TMP/s6"
touch "$TMP/s6/pnpm-lock.yaml"
result=$(find_lockfile_dir "$TMP/s6" "$TMP/s6")
expect_eq "$(cd "$TMP/s6" && pwd)"$'\t'"pnpm-lock.yaml" "$result" "detects pnpm-lock.yaml"

# Scenario 7: scan dir is workspace boundary (root scan)
mkdir -p "$TMP/s7"
touch "$TMP/s7/package-lock.json"
result=$(find_lockfile_dir "$TMP/s7" "$TMP/s7")
expect_eq "$(cd "$TMP/s7" && pwd)"$'\t'"package-lock.json" "$result" "finds lockfile when scan dir equals boundary"

# Scenario 8: when multiple lockfile types are in the same dir, preference order is
# package-lock.json > yarn.lock > pnpm-lock.yaml (npm ecosystem is most common and
# the order matters only for picking one to drive the install)
mkdir -p "$TMP/s8"
touch "$TMP/s8/package-lock.json" "$TMP/s8/yarn.lock" "$TMP/s8/pnpm-lock.yaml"
result=$(find_lockfile_dir "$TMP/s8" "$TMP/s8")
expect_eq "$(cd "$TMP/s8" && pwd)"$'\t'"package-lock.json" "$result" "picks package-lock.json when multiple lockfiles coexist"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -eq 0 ]; then
  exit 0
else
  exit 1
fi
