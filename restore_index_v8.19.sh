#!/bin/bash

# ==========================================
# v8.19 variant — no fm-clone step
# ILM snapshots contain the raw .ds-... backing index name directly.
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

REPOSITORY="found-snapshots"
TARGET_INDEX="${1:-}"   # Pass the .ds-... backing index name as $1
RESTORE_PREFIX="restored2-"

if [ -z "$TARGET_INDEX" ]; then
  echo "Usage: $0 <backing-index-name>"
  echo "  e.g. $0 .ds-logs-mytest-default-2026.05.27-000001"
  exit 1
fi

echo "=== v8.19 Restore — starting ==="
echo "Target index : $TARGET_INDEX"
echo "Repository   : $REPOSITORY"

# 1. Find the ILM snapshot that contains this backing index.
#    In v8.x, ILM snapshot names use a date-based prefix:
#      <YYYY.MM.DD>-<index-name>-<policy-name>-<uuid>
#    (NOT "ilm-searchable-snapshot-..." as in v9.x)
#    So we search all snapshots for one whose .indices array contains TARGET_INDEX.
echo ""
echo "[1] Searching for ILM snapshot containing '$TARGET_INDEX'..."
SNAPSHOT_NAME=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/_all?sort=start_time&order=desc" \
  -H "Authorization: ApiKey $API_KEY" | \
  jq -r --arg idx "$TARGET_INDEX" \
    '.snapshots[] | select(.indices | index($idx)) | .snapshot' \
  | head -n 1)

if [ -z "$SNAPSHOT_NAME" ] || [ "$SNAPSHOT_NAME" == "null" ]; then
  echo "ERROR: No ILM snapshot found containing '$TARGET_INDEX'."
  exit 1
fi
echo "Found snapshot: $SNAPSHOT_NAME"

# 2. Restore — rename_pattern strips ".ds-" prefix → restored-<rest>
#    (No fm-clone prefix to deal with in v8.19.)
echo ""
echo "[2] Executing restore..."
RESTORE_RESPONSE=$(curl -s -X POST "$ES_URL/_snapshot/$REPOSITORY/$SNAPSHOT_NAME/_restore" \
  -H "Authorization: ApiKey $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "indices": "'"$TARGET_INDEX"'",
    "ignore_unavailable": true,
    "include_global_state": false,
    "rename_pattern": "\\.ds-(.+)",
    "rename_replacement": "'"$RESTORE_PREFIX"'$1",
    "index_settings": {
      "index.lifecycle.name": null,
      "index.routing.allocation.include._tier_preference": "data_hot"
    }
  }')

echo "Response: $RESTORE_RESPONSE"

ACCEPTED=$(echo "$RESTORE_RESPONSE" | jq -r '.accepted')
if [ "$ACCEPTED" == "true" ]; then
  # Derive the restored name by applying the same rename logic
  RESTORED_NAME="${RESTORE_PREFIX}$(echo "$TARGET_INDEX" | sed 's/^.*\.ds-//')"
  echo ""
  echo "SUCCESS: Restore request accepted."
  echo "Restored index name : $RESTORED_NAME"
  echo "Check recovery      : GET _cat/recovery/$RESTORED_NAME?v"

  # 3. Un-hide the restored index so wildcard searches work
  echo ""
  echo "[3] Un-hiding restored index (index.hidden = false)..."
  sleep 5
  UNHIDE_RESP=$(curl -s -X PUT "$ES_URL/$RESTORED_NAME/_settings" \
    -H "Authorization: ApiKey $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"index": {"hidden": false}}')
  echo "Un-hide response: $UNHIDE_RESP"
else
  echo "ERROR: Restore failed."
  exit 1
fi

echo ""
echo "=== v8.19 Restore — done ==="
