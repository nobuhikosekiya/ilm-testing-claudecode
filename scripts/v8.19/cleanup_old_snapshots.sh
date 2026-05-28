#!/bin/bash

# ==========================================
# v8.19 — Delete ILM snapshots older than N minutes
#
# In v8.19, ILM snapshots use a date-based naming prefix:
#   <YYYY.MM.DD>-<index-name>-<policy-name>-<uuid>
# This is distinct from v9.x which uses "ilm-searchable-snapshot-" prefix.
#
# Credentials are loaded from the project-root .env file.
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env"

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

echo "=== v8.19 Cleanup — ILM snapshots older than $MINUTES_OLD minutes (keyword: $KEYWORD) ==="

# v8.19 ILM snapshots are identified by the YYYY.MM.DD- date prefix.
# (v9.x uses "ilm-searchable-snapshot-..." — NOT applicable here.)
echo "Searching for target snapshots..."
SNAPSHOTS_TO_DELETE=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/_all" \
  -H "Authorization: ApiKey $API_KEY" | \
  jq -r --arg kw "$KEYWORD" --argjson ms "$THRESHOLD_MS" '
    .snapshots[] |
    select(.snapshot | test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-")) |
    select(.snapshot | contains($kw)) |
    select(.start_time_in_millis < ((now * 1000) - $ms)) |
    .snapshot
  ')

if [ -z "$SNAPSHOTS_TO_DELETE" ]; then
  echo "No snapshots older than $MINUTES_OLD minutes found."
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
    echo " -> Deleted successfully"
    ((COUNT++))
  else
    echo " -> Error: $DELETE_RESPONSE"
  fi
done

echo ""
echo "=== v8.19 Cleanup — done ==="
echo "Deleted $COUNT snapshot(s)."
