#!/usr/bin/env bash

set -euo pipefail

lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

bool_json() {
  if [ "$(lower "${1:-}")" = "true" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

emit_result() {
  jq -nc \
    --arg debianSuite "$EFFECTIVE_DEBIAN_SUITE" \
    --arg debianArch "$EFFECTIVE_DEBIAN_ARCH" \
    --arg scanTargetSource "$SCAN_TARGET_SOURCE" \
    --arg configFetchStatus "$CONFIG_FETCH_STATUS" \
    --argjson nativeResolversEnabled "$(bool_json "$EFFECTIVE_NATIVE_RESOLVERS")" \
    '{
      debianSuite: (if $debianSuite == "" then null else $debianSuite end),
      debianArch: (if $debianArch == "" then null else $debianArch end),
      nativeResolversEnabled: $nativeResolversEnabled,
      scanTargetSource: (if $scanTargetSource == "" then null else $scanTargetSource end),
      configFetchStatus: $configFetchStatus
    }'
}

is_allowed_scan_config_url() {
  case "${1%/}" in
    "https://api.utensil.tools/api/scan-config") return 0 ;;
    *) return 1 ;;
  esac
}

CURL_BIN="${CURL_BIN:-curl}"
SCAN_CONFIG_TIMEOUT_SECONDS="${SCAN_CONFIG_TIMEOUT_SECONDS:-5}"

EFFECTIVE_DEBIAN_SUITE="${INPUT_DEBIAN_SUITE:-}"
EFFECTIVE_DEBIAN_ARCH="${INPUT_DEBIAN_ARCH:-}"
NATIVE_RESOLVERS_INPUT="$(lower "${INPUT_NATIVE_RESOLVERS:-}")"
EFFECTIVE_NATIVE_RESOLVERS="$NATIVE_RESOLVERS_INPUT"
SCAN_TARGET_SOURCE=""
CONFIG_FETCH_STATUS="skipped"

FETCH_SCAN_CONFIG="$(lower "${INPUT_FETCH_SCAN_CONFIG:-true}")"
SCAN_CONFIG_URL="${UTENSIL_SCAN_CONFIG_URL:-https://api.utensil.tools/api/scan-config}"
REPO_OWNER="${REPO_OWNER:-}"
REPO_NAME="${REPO_NAME:-}"

if [ "$FETCH_SCAN_CONFIG" = "true" ]; then
  if [ -z "${UTENSIL_LICENSE_TOKEN:-}" ]; then
    CONFIG_FETCH_STATUS="skipped_no_token"
  elif ! is_allowed_scan_config_url "$SCAN_CONFIG_URL"; then
    CONFIG_FETCH_STATUS="skipped_untrusted_url"
  else
    CONFIG_RESPONSE="${RUNNER_TEMP:-/tmp}/utensil-scan-config.json"
    set +e
    CONFIG_HTTP_CODE=$("$CURL_BIN" -sS --max-time "$SCAN_CONFIG_TIMEOUT_SECONDS" -o "$CONFIG_RESPONSE" -w "%{http_code}" \
      -H "Authorization: Bearer $UTENSIL_LICENSE_TOKEN" \
      "${SCAN_CONFIG_URL%/}/$REPO_OWNER/$REPO_NAME")
    CONFIG_CURL_EXIT=$?
    set -e

    if [ "$CONFIG_CURL_EXIT" -eq 0 ] && [ "$CONFIG_HTTP_CODE" -eq 200 ]; then
      if ! jq empty "$CONFIG_RESPONSE" >/dev/null 2>&1; then
        CONFIG_FETCH_STATUS="failed"
      else
        if [ -z "$EFFECTIVE_DEBIAN_SUITE" ]; then
          EFFECTIVE_DEBIAN_SUITE=$(jq -r '.debianSuite // empty' "$CONFIG_RESPONSE" 2>/dev/null || true)
        fi
        if [ -z "$EFFECTIVE_DEBIAN_ARCH" ]; then
          EFFECTIVE_DEBIAN_ARCH=$(jq -r '.debianArch // empty' "$CONFIG_RESPONSE" 2>/dev/null || true)
        fi
        if [ -z "$NATIVE_RESOLVERS_INPUT" ]; then
          EFFECTIVE_NATIVE_RESOLVERS=$(jq -r 'if .nativeResolversEnabled == true then "true" else "false" end' "$CONFIG_RESPONSE" 2>/dev/null || echo "false")
        fi
        CONFIG_FETCH_STATUS="fetched"
      fi
    elif [ "$CONFIG_CURL_EXIT" -eq 0 ] && [ "$CONFIG_HTTP_CODE" -eq 404 ]; then
      CONFIG_FETCH_STATUS="missing"
    else
      CONFIG_FETCH_STATUS="failed"
    fi
  fi
fi

if [ -n "${INPUT_DEBIAN_SUITE:-}" ] || [ -n "${INPUT_DEBIAN_ARCH:-}" ] || [ -n "$NATIVE_RESOLVERS_INPUT" ]; then
  SCAN_TARGET_SOURCE="explicit"
elif [ "$CONFIG_FETCH_STATUS" = "fetched" ]; then
  CONFIG_HAS_NATIVE_SETTING=$(jq -r 'has("nativeResolversEnabled")' "$CONFIG_RESPONSE" 2>/dev/null || echo "false")
  if [ -n "$EFFECTIVE_DEBIAN_SUITE" ] || [ -n "$EFFECTIVE_DEBIAN_ARCH" ] || [ "$CONFIG_HAS_NATIVE_SETTING" = "true" ]; then
    SCAN_TARGET_SOURCE="stored"
  fi
fi

emit_result
