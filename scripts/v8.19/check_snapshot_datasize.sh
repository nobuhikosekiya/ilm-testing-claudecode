#!/bin/bash

# ==========================================
# v8.19 — Audit incremental/total snapshot storage for a backing index
#
# Reports how much storage each ILM and SLM snapshot consumes for a
# specific backing index. Useful for understanding snapshot overhead
# before deleting old snapshots.
#
# Required .env_v8.19 parameters:
# ---------------------------------
# ES_URL    — Full Elasticsearch cluster URL, e.g.:
#               ES_URL="https://<cluster-id>.es.<region>.gcp.cloud.es.io"
#
# API_KEY   — Base64-encoded Elasticsearch API key with at least:
#               - cluster privilege: monitor (for _snapshot APIs)
#               - index privilege:   monitor on target indices
#             Generate in Kibana → Stack Management → API Keys, or via:
#               POST /_security/api_key
#               { "name": "snapshot-audit", "role_descriptors": {
#                   "snapshot_reader": {
#                     "cluster": ["monitor"],
#                     "indices": [{"names":["*"],"privileges":["monitor"]}]
#                   }
#               }}
#             Then set: API_KEY="<api_key>"  (the base64 encoded form)
# ---------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env_v8.19"

REPOSITORY="found-snapshots"

# The specific backing index you want to audit (pass as $1, or uses default)
TARGET_INDEX="${1:-.ds-logs-mytest-v8-default-2026.05.27-000001}"

echo "=== Analyzing snapshot footprint for index: $TARGET_INDEX ==="

# 1. Get all snapshots that contain this specific index
echo "Fetching snapshot list..."
SNAPSHOTS=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/_all" \
  -H "Authorization: ApiKey $API_KEY" | \
  jq -r --arg idx "$TARGET_INDEX" '.snapshots[] | select(.indices | index($idx)) | .snapshot')

if [ -z "$SNAPSHOTS" ] || [ "$SNAPSHOTS" == "null" ]; then
  echo "No snapshots found containing the index: $TARGET_INDEX"
  exit 0
fi

# Initialize counters
ILM_COUNT=0
SLM_COUNT=0
ILM_TOTAL_INC=0
SLM_TOTAL_INC=0

echo "--------------------------------------------------------------------------------"
printf "%-10s | %-70s | %-15s | %-15s\n" "TYPE" "SNAPSHOT NAME" "INCREMENTAL (B)" "TOTAL (B)"
echo "--------------------------------------------------------------------------------"

# 2. Loop through each snapshot to get the specific index size
for snap in $SNAPSHOTS; do
  # v8.19 ILM snapshots: <YYYY.MM.DD>-<index>-<policy>-<uuid>
  # v8.19 SLM snapshots: cloud-snapshot-<date>-<uuid> (or similar)
  if [[ "$snap" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}- ]]; then
    TYPE="ILM"
  else
    TYPE="SLM"
  fi

  # Query the _status API and extract stats for our target index
  STATS=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/$snap/_status" \
    -H "Authorization: ApiKey $API_KEY" | \
    jq -r --arg idx "$TARGET_INDEX" '
      .snapshots[0].indices[$idx].stats |
      "\(.incremental.size_in_bytes) \(.total.size_in_bytes)"
    ')

  INC_BYTES=$(echo "$STATS" | awk '{print $1}')
  TOT_BYTES=$(echo "$STATS" | awk '{print $2}')

  if [ "$INC_BYTES" == "null" ] || [ -z "$INC_BYTES" ]; then continue; fi

  printf "%-10s | %-70s | %-15s | %-15s\n" "$TYPE" "$snap" "$INC_BYTES" "$TOT_BYTES"

  if [ "$TYPE" == "ILM" ]; then
    ((ILM_COUNT++))
    ILM_TOTAL_INC=$((ILM_TOTAL_INC + INC_BYTES))
  else
    ((SLM_COUNT++))
    SLM_TOTAL_INC=$((SLM_TOTAL_INC + INC_BYTES))
  fi
done

echo "--------------------------------------------------------------------------------"
echo "=== SUMMARY REPORT ==="
echo "Index: $TARGET_INDEX"
echo ""
echo "[ ILM Snapshots ]"
echo "  Times taken : $ILM_COUNT"
echo "  Total actual storage consumed (Incremental) : $ILM_TOTAL_INC bytes"
echo ""
echo "[ SLM Snapshots ]"
echo "  Times taken : $SLM_COUNT"
echo "  Total actual storage consumed (Incremental) : $SLM_TOTAL_INC bytes"
echo ""
echo "[ GRAND TOTAL ]"
echo "  Combined actual storage consumed : $((ILM_TOTAL_INC + SLM_TOTAL_INC)) bytes"
echo "================================================================================"
