#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ACTION_REPO="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
WEB_REPO="${1:-$ACTION_REPO/../utensil-web}"

if [ ! -d "$WEB_REPO/.git" ] && [ ! -f "$WEB_REPO/.git" ]; then
  echo "utensil-web repo not found at $WEB_REPO" >&2
  exit 1
fi

echo "Updating dashboard workflow templates in $WEB_REPO from tags in $ACTION_REPO"
(cd "$WEB_REPO" && node ./scripts/update-dashboard-workflow-templates.mjs "$ACTION_REPO")

cat <<EOF

Dashboard workflow templates updated.
Next step:
  git -C "$WEB_REPO" diff -- src/lib/dashboard-workflow-templates.ts src/components/dashboard/CIDashboard.tsx package.json
EOF
