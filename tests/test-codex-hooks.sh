#!/usr/bin/env bash

set -euo pipefail

ROOT="$(CDPATH= cd -P -- "$(dirname "$0")/.." && pwd -P)"
HOOK="$ROOT/.codex/hooks/prevent_pr_merge.py"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_hook() {
  local command="$1"
  local input="$TMPDIR/input.json"
  python3 - "$command" > "$input" <<'PY'
import json
import sys

print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {
        "command": sys.argv[1],
    },
}))
PY
  python3 "$HOOK" < "$input"
}

assert_allows() {
  local command="$1"
  local output
  output="$(run_hook "$command")"
  if [[ -n "$output" ]]; then
    printf 'Expected command to be allowed, got hook output:\n%s\n' "$output" >&2
    exit 1
  fi
}

assert_blocks() {
  local command="$1"
  local output
  output="$(run_hook "$command")"
  if [[ "$output" != *'"permissionDecision": "deny"'* ]]; then
    printf 'Expected command to be blocked, got hook output:\n%s\n' "$output" >&2
    exit 1
  fi
}

assert_allows 'gh pr create --draft --base main --head codex/example'
assert_allows 'git merge feature/example'
assert_blocks 'gh pr merge 37'
assert_blocks 'gh -R Stencia/utensil-ci-action pr merge 37 --auto'
assert_blocks "bash -lc 'gh pr merge 37'"
assert_blocks 'gh api repos/Stencia/utensil-ci-action/pulls/37/merge -X PUT'
assert_blocks "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'"
