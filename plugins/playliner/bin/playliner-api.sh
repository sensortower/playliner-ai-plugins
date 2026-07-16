#!/usr/bin/env bash
#
# Thin wrapper around the Playliner /api/v1/external/* search API.
#
# Usage:
#   playliner-api.sh <endpoint> [json-body]
#
#   endpoint : articles | games | tags | genres | analytics
#   json-body: Typesense search payload as a JSON string (defaults to '{}')
#
# Reads credentials from $PLAYLINER_CRED_FILE (default ~/.config/playliner/credentials),
# a shell-sourced file that MUST define:
#   PLAYLINER_TOKEN="<API token>"
# and MAY define:
#   PLAYLINER_BASE_URL="https://app.sensortower.com/playliner/api"
#
# Prints the JSON response body to stdout. On a non-2xx HTTP status it also
# prints "HTTP <code>" to stderr and exits 1, so the caller can detect errors.
set -euo pipefail

CRED_FILE="${PLAYLINER_CRED_FILE:-$HOME/.config/playliner/credentials}"

if [[ ! -f "$CRED_FILE" ]]; then
  echo "ERROR: credentials file not found at $CRED_FILE — run the skill setup step first." >&2
  exit 3
fi

# shellcheck disable=SC1090
source "$CRED_FILE"

if [[ -z "${PLAYLINER_TOKEN:-}" ]]; then
  echo "ERROR: PLAYLINER_TOKEN is not set in $CRED_FILE" >&2
  exit 3
fi

BASE_URL="${PLAYLINER_BASE_URL:-https://app.sensortower.com/playliner/api}"
BASE_URL="${BASE_URL%/}"

endpoint="${1:?endpoint required: articles|games|tags|genres|analytics|usage}"
if [[ $# -ge 2 ]]; then body="$2"; else body='{}'; fi

case "$endpoint" in
  articles|games|tags|genres|analytics)
    resp="$(printf '%s' "$body" | curl -sS -X POST "$BASE_URL/v1/external/$endpoint" \
      -H "Authorization: Bearer $PLAYLINER_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      --data-binary @- \
      -w $'\n%{http_code}')"
    ;;
  usage)
    resp="$(curl -sS -X GET "$BASE_URL/v1/external/usage${body:+?$body}" \
      -H "Authorization: Bearer $PLAYLINER_TOKEN" \
      -H "Accept: application/json" \
      -w $'\n%{http_code}')"
    ;;
  *)
    echo "ERROR: unknown endpoint '$endpoint' (expected articles|games|tags|genres|analytics|usage)" >&2
    exit 2
    ;;
esac

code="${resp##*$'\n'}"
json="${resp%$'\n'*}"

echo "$json"

if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
  echo "HTTP $code" >&2
  exit 1
fi
