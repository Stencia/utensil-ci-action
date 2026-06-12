#!/usr/bin/env bash

set -euo pipefail

is_allowed_auth_token_url() {
  case "${1%/}" in
    "https://auth.utensil.tools/token") return 0 ;;
    *) return 1 ;;
  esac
}

form_urlencode() {
  local input="$1"
  local char encoded hex
  local i
  local LC_ALL=C

  encoded=""
  for ((i = 0; i < ${#input}; i++)); do
    char="${input:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-])
        encoded+="$char"
        ;;
      *)
        printf -v hex '%%%02X' "'$char"
        encoded+="$hex"
        ;;
    esac
  done

  printf '%s' "$encoded"
}

CURL_BIN="${CURL_BIN:-curl}"
AUTH_TOKEN_URL="${UTENSIL_AUTH_TOKEN_URL:-https://auth.utensil.tools/token}"
AUTH_TIMEOUT_SECONDS="${UTENSIL_AUTH_TIMEOUT_SECONDS:-10}"

if [ -z "${UTENSIL_LICENSE_KEY:-}" ]; then
  echo "UTENSIL_LICENSE_KEY is empty." >&2
  exit 2
fi

if ! is_allowed_auth_token_url "$AUTH_TOKEN_URL"; then
  echo "Refusing untrusted Utensil auth token URL." >&2
  exit 2
fi

ENCODED_LICENSE_KEY=$(form_urlencode "$UTENSIL_LICENSE_KEY")
REQUEST_BODY_PATH=$(mktemp "${RUNNER_TEMP:-/tmp}/utensil-access-token-request.XXXXXX")
RESPONSE_PATH=$(mktemp "${RUNNER_TEMP:-/tmp}/utensil-access-token-response.XXXXXX")
trap 'rm -f "$REQUEST_BODY_PATH" "$RESPONSE_PATH"' EXIT
chmod 600 "$REQUEST_BODY_PATH" "$RESPONSE_PATH" 2>/dev/null || true

{
  printf 'grant_type=client_credentials'
  printf '&client_id=%s' "$ENCODED_LICENSE_KEY"
  printf '&client_secret=%s' "$ENCODED_LICENSE_KEY"
} > "$REQUEST_BODY_PATH"

set +e
HTTP_CODE=$("$CURL_BIN" -sS --max-time "$AUTH_TIMEOUT_SECONDS" -o "$RESPONSE_PATH" -w "%{http_code}" \
  -X POST "${AUTH_TOKEN_URL%/}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data @"$REQUEST_BODY_PATH")
CURL_EXIT=$?
set -e

if [ "$CURL_EXIT" -ne 0 ] || [ -z "$HTTP_CODE" ]; then
  echo "Could not reach auth.utensil.tools to exchange the license key." >&2
  exit 1
fi

if [ "$HTTP_CODE" -ne 200 ]; then
  MESSAGE=$(jq -r '.error_description // .message // .error // empty' "$RESPONSE_PATH" 2>/dev/null || true)
  if [ -n "$MESSAGE" ]; then
    echo "$MESSAGE" >&2
  else
    echo "License key exchange failed with HTTP $HTTP_CODE." >&2
  fi
  exit 1
fi

ACCESS_TOKEN=$(jq -r 'if ((.token_type // "" | ascii_downcase) == "bearer") and ((.access_token // "") != "") then .access_token else empty end' "$RESPONSE_PATH" 2>/dev/null || true)
if [ -z "$ACCESS_TOKEN" ]; then
  echo "Auth service returned an invalid access token response." >&2
  exit 1
fi

printf '%s\n' "$ACCESS_TOKEN"
