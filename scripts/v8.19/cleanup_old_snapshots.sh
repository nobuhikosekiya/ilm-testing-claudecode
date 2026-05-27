#!/bin/bash

# ==========================================
# v8.19 — Delete ILM snapshots older than N minutes
#
# In v8.19, ILM snapshots use a date-based naming prefix:
#   <YYYY.MM.DD>-<index-name>-<policy-name>-<uuid>
# This is distinct from v9.x which uses "ilm-searchable-snapshot-" prefix.
#
# Credentials are loaded from the project-root .env_v8.19 file.
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env_v8.19"

REPOSITORY="found-snapshots"

# How many minutes old a snapshot must be to get deleted (default: 10)
MINUTES_OLD="${1:-10}"
THRESHOLD_MS=$((MINUTES_OLD * 60 * 1000))

echo "=== v8.19 Cleanup — ILM snapshots older than $MINUTES_OLD minutes ==="

# v8.19 ILM snapshots are identified by the YYYY.MM.DD- date prefix.
# (v9.x uses "ilm-searchable-snapshot-..." — NOT applicable here.)
echo "Searching for target snapshots..."
SNAPSHOTS_TO_DELETE=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/_all" \
  -H "Authorization: ApiKey $API_KEY" | \
  jq -r --argjson ms "$THRESHOLD_MS" '
    .snapshots[] |
    select(.snapshot | test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-")) |
    select(.start_time_in_millis < ((now * 1000) - $ms)) |
    .snapshot
  ')

if [ -z "$SNAPSHOTS_TO_DELETE" ]; then
  echo "No snapshots older than $MINUTES_OLD minutes found."
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
