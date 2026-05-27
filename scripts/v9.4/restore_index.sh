#!/bin/bash

# ==========================================
# v9.4 — Restore a deleted backing index from its ILM snapshot
#
# In v9.2+, ILM creates a temporary fm-clone-<uuid>-<index> clone,
# force-merges it, and snapshots the clone. The snapshot name format
# is "ilm-searchable-snapshot-<uuid>".
#
# This script:
#   1. Finds the latest ILM snapshot containing the target index
#      (matching by the fm-clone-...-<index> name inside the snapshot)
#   2. Restores it to the hot tier, stripping fm-clone- and .ds- prefixes
#   3. Clears the ILM policy so the restored index is standalone
#
# Credentials are loaded from the project-root .env_v9.4 file.
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env_v9.4"

REPOSITORY="found-snapshots"
TARGET_INDEX="${1:-}"   # Pass the .ds-... backing index name as $1
RESTORE_PREFIX="restored-"

if [ -z "$TARGET_INDEX" ]; then
  echo "Usage: $0 <backing-index-name>"
  echo "  e.g. $0 .ds-logs-mytest-v9-default-2026.05.27-000001"
  exit 1
fi

echo "=== v9.4 Restore — starting ==="
echo "Target index : $TARGET_INDEX"
echo "Repository   : $REPOSITORY"

# 1. Find the latest ILM snapshot containing this backing index.
#    In v9.x, the snapshot stores the fm-clone-<uuid>-.ds-... name,
#    so we search for snapshots whose .indices[] contains a value
#    ending in the .ds-... suffix of TARGET_INDEX.
#
#    Strategy: filter ILM snapshots by "ilm-searchable-snapshot-" prefix,
#    then find one whose .indices array contains an entry that ends with
#    the bare index name (stripping any fm-clone- prefix).
echo ""
echo "[1] Searching for ILM snapshot containing '$TARGET_INDEX'..."
SNAPSHOT_NAME=$(curl -s -X GET "$ES_URL/_snapshot/$REPOSITORY/_all?sort=start_time&order=desc" \
  -H "Authorization: ApiKey $API_KEY" | \
  jq -r --arg idx "$TARGET_INDEX" \
    '.snapshots[] |
     select(.snapshot | startswith("ilm-searchable-snapshot-")) |
     select(.indices | index($idx)) |
     .snapshot' \
  | head -n 1)

if [ -z "$SNAPSHOT_NAME" ] || [ "$SNAPSHOT_NAME" == "null" ]; then
  echo "ERROR: No ILM snapshot found containing '$TARGET_INDEX'."
  echo "NOTE: In v9.x, the snapshot indexes the fm-clone-... name, not the bare .ds-... name."
  echo "      Verify with: GET _snapshot/found-snapshots/_all?sort=start_time&order=desc"
  exit 1
fi
echo "Found snapshot: $SNAPSHOT_NAME"

# 2. Restore — rename_pattern strips the fm-clone- prefix and restores
#    as restored-<bare-index-name>.
#    Pattern ".*\\.ds-(.+)" captures everything after the last ".ds-"
#    (handles both "fm-clone-<uuid>-.ds-<name>" and plain ".ds-<name>").
echo ""
echo "[2] Executing restore..."
RESTORE_RESPONSE=$(curl -s -X POST "$ES_URL/_snapshot/$REPOSITORY/$SNAPSHOT_NAME/_restore" \
  -H "Authorization: ApiKey $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "indices": "'"$TARGET_INDEX"'",
    "ignore_unavailable": true,
    "include_global_state": false,
    "rename_pattern": ".*\\.ds-(.+)",
    "rename_replacement": "'"$RESTORE_PREFIX"'$1",
    "index_settings": {
      "index.lifecycle.name": null,
      "index.routing.allocation.include._tier_preference": "data_hot"
    }
  }')

echo "Response: $RESTORE_RESPONSE"

ACCEPTED=$(echo "$RESTORE_RESPONSE" | jq -r '.accepted')
if [ "$ACCEPTED" == "true" ]; then
  RESTORED_NAME="${RESTORE_PREFIX}$(echo "$TARGET_INDEX" | sed 's/^.*\.ds-//')"
  echo ""
  echo "SUCCESS: Restore request accepted."
  echo "Restored index name : $RESTORED_NAME"
  echo "Check recovery      : GET _cat/recovery/$RESTORED_NAME?v"
else
  echo "ERROR: Restore failed."
  exit 1
fi

echo ""
echo "=== v9.4 Restore — done ==="
