#!/bin/bash

# ==========================================
# v9.4 — Delete ILM snapshots older than N minutes
#
# In v9.2+, ILM snapshots use the "ilm-searchable-snapshot-<uuid>" naming.
# This script identifies and deletes them by that prefix.
#
# Credentials are loaded from the project-root .env_v9.4 file.
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env_v9.4"

REPOSITORY="found-snapshots"

# How many minutes old a snapshot must be to get deleted (default: 10)
MINUTES_OLD="${1:-10}"
THRESHOLD_MS=$((MINUTES_OLD * 60 * 1000))

echo "=== v9.4 Cleanup — ILM snapshots older than $MINUTES_OLD minutes ==="

# v9.x ILM snapshots are identified by the "ilm-searchable-snapshot-" prefix.
# (v8.x uses a YYYY.MM.DD- date prefix — NOT applicable here.)
echo "Searching for target snapshots..."
SNAPSHOTS_TO_DELETE=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/_all" \
  -H "Authorization: ApiKey $API_KEY" | \
  jq -r --argjson ms "$THRESHOLD_MS" '
    .snapshots[] |
    select(.snapshot | startswith("ilm-searchable-snapshot-")) |
    select(.start_time_in_millis < ((now * 1000) - $ms)) |
    .snapshot
  ')

if [ -z "$SNAPSHOTS_TO_DELETE" ]; then
  echo "No snapshots older than $MINUTES_OLD minutes were found."
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
