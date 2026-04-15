#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$ROOT/.githooks"
PRIMARY_CHECKOUT="${UTENSIL_PRIMARY_CHECKOUT:-}"

chmod +x \
  "$HOOKS_DIR/_block_primary_main.sh" \
  "$HOOKS_DIR/pre-commit" \
  "$HOOKS_DIR/pre-merge-commit" \
  "$HOOKS_DIR/pre-push"

git -C "$ROOT" config core.hooksPath "$HOOKS_DIR"

if [ "$PRIMARY_CHECKOUT" = "current" ] || [ "$PRIMARY_CHECKOUT" = "1" ] || [ "$PRIMARY_CHECKOUT" = "true" ]; then
  PRIMARY_CHECKOUT="$ROOT"
fi

if [ -n "$PRIMARY_CHECKOUT" ]; then
  git -C "$ROOT" config utensil.primaryCheckout "$PRIMARY_CHECKOUT"
fi

printf 'Configured core.hooksPath=%s\n' "$HOOKS_DIR"
if [ -n "$PRIMARY_CHECKOUT" ]; then
  printf 'Configured utensil.primaryCheckout=%s\n' "$PRIMARY_CHECKOUT"
else
  printf '%s\n' "Primary-checkout guardrail is disabled until utensil.primaryCheckout is set."
  printf '%s\n' "Set UTENSIL_PRIMARY_CHECKOUT=current when installing hooks in the primary checkout."
fi
