#!/bin/bash

# ==========================================
# v9.4 — Delete ILM snapshots older than N minutes
#
# In v9.2+, ILM snapshots use the "ilm-searchable-snapshot-<uuid>" naming.
# This script identifies and deletes them by that prefix.
#
# Credentials are loaded from the project-root .env file.
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: required env file not found: $ENV_FILE"
  exit 1
fi
source "$ENV_FILE"

REPOSITORY="found-snapshots"

# Require explicit execution mode to perform deletion.
EXECUTE=false

# Require a keyword to avoid broad accidental deletions.
KEYWORD=""
MINUTES_OLD="5256000"
MINUTES_SET=false

for arg in "$@"; do
  case "$arg" in
    --execute)
      EXECUTE=true
      ;;
    *)
      if [ -z "$KEYWORD" ]; then
        KEYWORD="$arg"
      elif [ "$MINUTES_SET" = false ]; then
        MINUTES_OLD="$arg"
        MINUTES_SET=true
      else
        echo "Error: unexpected argument: $arg"
        echo "Usage: $0 <keyword> [minutes_old] [--execute]"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$KEYWORD" ]; then
  echo "Usage: $0 <keyword> [minutes_old] [--execute]"
  echo "Example (dry-run): $0 mytest 10"
  echo "Example (delete):  $0 mytest 10 --execute"
  exit 1
fi

# Strict keyword checks for safety.
if [ ${#KEYWORD} -lt 5 ]; then
  echo "Error: keyword must be at least 5 characters."
  exit 1
fi

KEYWORD_LOWER="$(printf '%s' "$KEYWORD" | tr '[:upper:]' '[:lower:]')"
if [ "$KEYWORD_LOWER" = "metrics" ]; then
  echo "Error: keyword 'metrics' is not allowed."
  exit 1
fi

if [[ "$KEYWORD" =~ ^[0-9.]+$ ]]; then
  echo "Error: keyword cannot be only numbers and dots (example of invalid: 2026.05)."
  exit 1
fi

if ! [[ "$MINUTES_OLD" =~ ^[0-9]+$ ]]; then
  echo "Error: minutes_old must be a positive integer."
  exit 1
fi

if [ "$MINUTES_OLD" -le 0 ]; then
  echo "Error: minutes_old must be greater than 0."
  exit 1
fi

THRESHOLD_MS=$((MINUTES_OLD * 60 * 1000))

echo "=== v9.4 Cleanup — ILM snapshots older than $MINUTES_OLD minutes (keyword: $KEYWORD) ==="

# v9.x ILM snapshots are identified by the "ilm-searchable-snapshot-" prefix.
# (v8.x uses a YYYY.MM.DD- date prefix — NOT applicable here.)
echo "Searching for target snapshots..."
SNAPSHOTS_TO_DELETE=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/_all" \
  -H "Authorization: ApiKey $API_KEY" | \
  jq -r --arg kw "$KEYWORD" --argjson ms "$THRESHOLD_MS" '
    .snapshots[] |
    select(.snapshot | startswith("ilm-searchable-snapshot-")) |
    select(.snapshot | contains($kw)) |
    select(.start_time_in_millis < ((now * 1000) - $ms)) |
    .snapshot
  ')

if [ -z "$SNAPSHOTS_TO_DELETE" ]; then
  echo "No snapshots older than $MINUTES_OLD minutes were found."
  exit 0
fi

echo ""
echo "Snapshots selected for deletion:"
echo "$SNAPSHOTS_TO_DELETE" | nl -w2 -s'. '
echo ""

if [ "$EXECUTE" != "true" ]; then
  echo "Dry-run mode: no deletions were performed."
  echo "Re-run with --execute to delete the snapshots listed above."
  exit 0
fi

COUNT=0
for snap in $SNAPSHOTS_TO_DELETE; do
  echo "Deleting: $snap"
  DELETE_RESPONSE=$(curl -s -X DELETE "$ES_URL/_snapshot/$REPOSITORY/$snap" \
    -H "Authorization: ApiKey $API_KEY")

  ACK=$(echo "$DELETE_RESPONSE" | jq -r '.acknowledged')
  if [ "$ACK" == "true" ]; then
    echo " -> Successfully deleted"
    ((COUNT++))
  else
    echo " -> Error deleting: $DELETE_RESPONSE"
  fi
done

echo ""
echo "=== v9.4 Cleanup — done ==="
echo "Successfully deleted $COUNT old snapshot(s)."
