#!/bin/bash

# ==========================================
# v8.19 variant — cleanup ILM snapshots
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

REPOSITORY="found-snapshots"

# For testing: how many minutes old a snapshot must be to get deleted
MINUTES_OLD="${1:-10}"
THRESHOLD_MS=$((MINUTES_OLD * 60 * 1000))

echo "=== v8.19 Cleanup — ILM snapshots older than $MINUTES_OLD minutes ==="

# v8.19 ILM snapshot naming: <YYYY.MM.DD>-<index-name>-<policy-name>-<uuid>
# (v9.x uses "ilm-searchable-snapshot-..." prefix — NOT applicable here)
# We identify ILM snapshots by their date-prefix pattern: starts with YYYY.MM.DD-
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
