#!/bin/sh

set -eu

TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || printf '')"
PRIMARY_CHECKOUT="$(git config --path --get utensil.primaryCheckout 2>/dev/null || printf '')"

if [ -z "$PRIMARY_CHECKOUT" ] || [ "$TOPLEVEL" != "$PRIMARY_CHECKOUT" ]; then
  exit 0
fi

cat >&2 <<EOF
Blocked: refusing to write history from the primary checkout.

Allowed:
- git pull in the primary checkout to sync the default branch

Not allowed here:
- git commit
- merge commits
- git push

Next step:
  git -C "$PRIMARY_CHECKOUT" worktree add <worktree-path> -b codex/<topic>

Then make edits and commits in that worktree.
EOF

exit 1
