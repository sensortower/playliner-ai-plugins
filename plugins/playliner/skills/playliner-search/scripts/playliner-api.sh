#!/usr/bin/env bash
#
# Thin wrapper around the Playliner /api/v1/external/* search API.
#
# Usage:
#   bash <path-to-this-skill>/scripts/playliner-api.sh <endpoint> [json-body]
#
#   The script lives inside the playliner-search skill directory and is NOT on
#   PATH — always invoke it by its resolved absolute path (see SKILL.md,
#   "Locate the helper script").
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

# Read the shell-style credentials file WITHOUT sourcing it, so a value with
# shell metacharacters (`, $, ", \) can't run as code. Handles KEY=value,
# KEY="value", and KEY='value'; last assignment wins.
read_cred() {
  local key="$1" line val
  line=$(grep -E "^[[:space:]]*${key}=" "$CRED_FILE" | tail -n 1) || true
  [[ -z "$line" ]] && return 0
  val="${line#*=}"
  val="${val%%[[:space:]]}"
  # strip one layer of matching surrounding quotes
  if [[ "$val" == \"*\" ]]; then val="${val#\"}"; val="${val%\"}";
  elif [[ "$val" == \'*\' ]]; then val="${val#\'}"; val="${val%\'}"; fi
  printf '%s' "$val"
}

PLAYLINER_TOKEN="$(read_cred PLAYLINER_TOKEN)"
PLAYLINER_BASE_URL="$(read_cred PLAYLINER_BASE_URL)"

if [[ -z "${PLAYLINER_TOKEN:-}" ]]; then
  echo "ERROR: PLAYLINER_TOKEN is not set in $CRED_FILE" >&2
  exit 3
fi

BASE_URL="${PLAYLINER_BASE_URL:-https://app.sensortower.com/playliner/api}"
BASE_URL="${BASE_URL%/}"

endpoint="${1:?endpoint required: articles|games|tags|genres|analytics}"
if [[ $# -ge 2 ]]; then body="$2"; else body='{}'; fi

# Pass the bearer token via a curl config file (fd/temp file) instead of a
# command-line argument, so it never appears in the process argv (`ps`).
# `printf` is a bash builtin, so the token is not exposed while writing it either.
AUTH_CFG="$(mktemp)"
chmod 600 "$AUTH_CFG"
trap 'rm -f "$AUTH_CFG"' EXIT
printf 'header = "Authorization: Bearer %s"\n' "$PLAYLINER_TOKEN" > "$AUTH_CFG"

case "$endpoint" in
  articles|games|tags|genres|analytics)
    resp="$(printf '%s' "$body" | curl -sS -X POST "$BASE_URL/v1/external/$endpoint" \
      --config "$AUTH_CFG" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      --data-binary @- \
      -w $'\n%{http_code}')"
    ;;
  *)
    echo "ERROR: unknown endpoint '$endpoint' (expected articles|games|tags|genres|analytics)" >&2
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
