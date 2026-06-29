#!/usr/bin/env bash

set -euo pipefail

ROOT="$(CDPATH= cd -P -- "$(dirname "$0")/.." && pwd -P)"
MERGE_HOOK="$ROOT/.codex/hooks/prevent_pr_merge.py"
PRIMARY_CHECKOUT_HOOK="$ROOT/.codex/hooks/prevent_primary_checkout_branch.py"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_hook() {
  local hook="$1"
  local command="$2"
  local cwd="${3:-$ROOT}"
  local input="$TMPDIR/input.json"

  python3 - "$command" "$cwd" > "$input" <<'PY'
import json
import sys

print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {
        "command": sys.argv[1],
        "workdir": sys.argv[2],
    },
}))
PY

  (cd "$cwd" && python3 "$hook" < "$input")
}

assert_allows_hook() {
  local hook="$1"
  local command="$2"
  local cwd="${3:-$ROOT}"
  local output

  output="$(run_hook "$hook" "$command" "$cwd")"
  if [[ -n "$output" ]]; then
    printf 'Expected command to be allowed, got hook output:\n%s\n' "$output" >&2
    exit 1
  fi
}

assert_blocks_hook() {
  local hook="$1"
  local command="$2"
  local cwd="${3:-$ROOT}"
  local output

  output="$(run_hook "$hook" "$command" "$cwd")"
  if [[ "$output" != *'"permissionDecision": "deny"'* ]]; then
    printf 'Expected command to be blocked, got hook output:\n%s\n' "$output" >&2
    exit 1
  fi
}

assert_allows() {
  local command="$1"
  assert_allows_hook "$MERGE_HOOK" "$command"
}

assert_blocks() {
  local command="$1"
  assert_blocks_hook "$MERGE_HOOK" "$command"
}

create_fixture_repo() {
  local primary="$1"
  local linked="$2"

  git init -q "$primary"
  git -C "$primary" symbolic-ref HEAD refs/heads/main
  git -C "$primary" config user.email "codex@example.com"
  git -C "$primary" config user.name "Codex"
  printf '%s\n' "initial" > "$primary/README.md"
  git -C "$primary" add README.md
  git -C "$primary" commit -q -m "Initial commit"
  git -C "$primary" branch codex/example
  git -C "$primary" branch codex/other
  git -C "$primary" config utensil.primaryCheckout "$primary"
  git -C "$primary" worktree add -q "$linked" codex/example
}

assert_primary_allows() {
  local command="$1"
  local cwd="${2:-$PRIMARY}"
  assert_allows_hook "$PRIMARY_CHECKOUT_HOOK" "$command" "$cwd"
}

assert_primary_blocks() {
  local command="$1"
  local cwd="${2:-$PRIMARY}"
  assert_blocks_hook "$PRIMARY_CHECKOUT_HOOK" "$command" "$cwd"
}

test_pr_merge_hook() {
  assert_allows 'gh pr create --draft --base main --head codex/example'
  assert_allows 'git merge feature/example'
  assert_allows 'CODEX_ALLOW_PR_MERGE=1 gh pr merge 37'
  assert_allows "bash -lc 'CODEX_ALLOW_PR_MERGE=1 gh pr merge 37'"
  assert_blocks 'gh pr merge 37'
  assert_blocks 'gh -R Stencia/utensil-ci-action pr merge 37 --auto'
  assert_blocks 'CODEX_ALLOW_PR_MERGE=1 echo ok && gh pr merge 37'
  assert_blocks 'CODEX_ALLOW_PR_MERGE=1 echo ok&&gh pr merge 37'
  assert_blocks 'CODEX_ALLOW_PR_MERGE=1 echo ok;gh pr merge 37'
  assert_blocks 'CODEX_ALLOW_PR_MERGE=1 gh pr merge 37&&gh pr merge 38'
  assert_blocks "bash -lc 'gh pr merge 37'"
  assert_blocks 'gh api repos/Stencia/utensil-ci-action/pulls/37/merge -X PUT'
  assert_blocks "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'"
}

test_primary_checkout_hook() {
  PRIMARY="$TMPDIR/primary"
  LINKED="$TMPDIR/linked"
  create_fixture_repo "$PRIMARY" "$LINKED"

  assert_primary_allows 'git switch main'
  assert_primary_allows 'git checkout main'
  assert_primary_allows 'git pull --ff-only'
  assert_primary_allows 'git worktree add /tmp/example -b codex/new main'
  assert_primary_blocks 'git switch codex/example'
  assert_primary_blocks 'git checkout codex/example'
  assert_primary_blocks 'git switch -c codex/new-topic'
  assert_primary_blocks 'git checkout -b codex/new-topic'
  assert_primary_blocks 'git status && git switch codex/example'
  assert_primary_blocks 'git status&&git switch codex/example'
  assert_primary_blocks 'git status;git switch codex/example'
  assert_primary_blocks "bash -lc 'git switch codex/example'"
  assert_primary_blocks "bash -lc 'git status && git switch codex/example'"
  assert_primary_blocks "bash -lc 'git status&&git switch codex/example'"
  assert_primary_blocks "git -C '$PRIMARY' switch codex/example" "$ROOT"
  assert_primary_allows 'git switch codex/other' "$LINKED"

  git -C "$PRIMARY" config --unset utensil.primaryCheckout
  assert_primary_blocks 'git switch codex/example'
}

test_pr_merge_hook
test_primary_checkout_hook
