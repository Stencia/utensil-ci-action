#!/usr/bin/env bash
# Install project dependencies for composition analysis.
#
# Without node_modules (or the equivalent for the ecosystem), the Utensil
# CLI's CodeCompositionAnalyzer cannot locate dependency source directories
# and falls back to estimating per-dependency LOC from the median of
# resolved packages. This inflates the reported dependency footprint by
# an order of magnitude.
#
# Walks up from SCAN_PATH to GITHUB_WORKSPACE (or /) looking for a lockfile,
# so monorepo subdirectory scans pick up the workspace-root install.
#
# Skips install if node_modules already exists at the lockfile directory.
#
# Install failures are non-fatal: the scan still runs with unresolved estimates.
#
# Usage:
#   SCAN_PATH=packages/app GITHUB_WORKSPACE=/github/workspace \
#     bash scripts/install-dependencies.sh

set -u

# Walk up from start_dir to find a directory containing a known lockfile.
# Stops at the given boundary (typically GITHUB_WORKSPACE) or /.
# On success, prints "<dir>\t<lockfile-name>" and returns 0.
# On failure, returns non-zero and prints nothing.
find_lockfile_dir() {
  local start_dir="$1"
  local boundary="$2"
  local dir boundary_abs parent

  dir="$(cd "$start_dir" 2>/dev/null && pwd)" || return 1
  boundary_abs="$(cd "$boundary" 2>/dev/null && pwd)" || boundary_abs="/"

  while :; do
    for name in package-lock.json yarn.lock pnpm-lock.yaml; do
      if [ -f "$dir/$name" ]; then
        printf '%s\t%s\n' "$dir" "$name"
        return 0
      fi
    done
    if [ "$dir" = "$boundary_abs" ] || [ "$dir" = "/" ]; then
      return 1
    fi
    parent="$(dirname "$dir")"
    if [ "$parent" = "$dir" ]; then
      return 1
    fi
    dir="$parent"
  done
}

# Run the npm, yarn, or pnpm install command appropriate for the detected
# lockfile. Must be called from the lockfile directory.
run_install() {
  local lockfile_name="$1"

  case "$lockfile_name" in
    package-lock.json)
      echo "Running npm ci --ignore-scripts..."
      if ! npm ci --ignore-scripts --no-audit --no-fund 2>&1 | tail -40; then
        echo "::warning::npm ci failed. Composition analysis will use estimates for unresolved dependencies."
      fi
      ;;
    yarn.lock)
      local yarn_version yarn_major
      yarn_version="$(yarn --version 2>/dev/null || echo "0")"
      yarn_major="${yarn_version%%.*}"
      if [ "$yarn_major" = "1" ] || [ "$yarn_major" = "0" ]; then
        echo "Running yarn install --frozen-lockfile --ignore-scripts (Yarn 1)..."
        if ! yarn install --frozen-lockfile --ignore-scripts 2>&1 | tail -40; then
          echo "::warning::yarn install failed. Composition analysis will use estimates for unresolved dependencies."
        fi
      else
        # Yarn 2+ ("Berry") removed --ignore-scripts (use YARN_ENABLE_SCRIPTS=false)
        # and --frozen-lockfile (use --immutable). Berry defaults to Plug'n'Play,
        # which stores deps in .yarn/cache/ as zips, not node_modules. Force the
        # node_modules linker so CodeCompositionAnalyzer can find dep source dirs.
        echo "Running yarn install --immutable with node_modules linker (Yarn $yarn_major)..."
        if ! YARN_ENABLE_SCRIPTS=false YARN_NODE_LINKER=node-modules yarn install --immutable 2>&1 | tail -40; then
          echo "::warning::yarn install failed. Composition analysis will use estimates for unresolved dependencies."
        fi
      fi
      ;;
    pnpm-lock.yaml)
      if ! command -v pnpm >/dev/null 2>&1; then
        npm install -g pnpm@latest >/dev/null 2>&1 || true
      fi
      if command -v pnpm >/dev/null 2>&1; then
        echo "Running pnpm install --frozen-lockfile --ignore-scripts..."
        if ! pnpm install --frozen-lockfile --ignore-scripts 2>&1 | tail -40; then
          echo "::warning::pnpm install failed. Composition analysis will use estimates for unresolved dependencies."
        fi
      else
        echo "::warning::pnpm-lock.yaml found but pnpm could not be installed. Composition analysis will use estimates for unresolved dependencies."
      fi
      ;;
  esac
}

main() {
  local scan_path="${SCAN_PATH:-.}"
  local workspace="${GITHUB_WORKSPACE:-$(pwd)}"
  local scan_dir result lockfile_dir lockfile_name

  scan_dir="$(cd "$scan_path" 2>/dev/null && pwd)" || {
    echo "scan path not accessible: $scan_path" >&2
    return 0
  }

  # If node_modules is already in the scan path (workflow installed deps),
  # skip without walking up.
  if [ -d "$scan_dir/node_modules" ]; then
    echo "node_modules already exists in $scan_dir; skipping install."
    return 0
  fi

  if ! result="$(find_lockfile_dir "$scan_dir" "$workspace")"; then
    echo "No npm/yarn/pnpm lockfile found between $scan_dir and $workspace; skipping install."
    return 0
  fi

  lockfile_dir="${result%$'\t'*}"
  lockfile_name="${result#*$'\t'}"

  if [ -d "$lockfile_dir/node_modules" ]; then
    echo "node_modules already exists in $lockfile_dir; skipping install."
    return 0
  fi

  echo "Installing dependencies from $lockfile_dir ($lockfile_name)..."
  cd "$lockfile_dir" || {
    echo "::warning::Failed to cd to $lockfile_dir."
    return 0
  }
  run_install "$lockfile_name"
}

# Only run main when executed directly, not when sourced for testing.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
