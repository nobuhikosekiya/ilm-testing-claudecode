# ILM Restore Behaviour: v8.19 vs v9.2+

This document summarises the key differences observed during testing. See
[`docs/findings/`](findings/) for full test run reports.

---

## Snapshot naming

| | v8.19 | v9.2+ |
|---|---|---|
| **ILM snapshot name format** | `<YYYY.MM.DD>-<index-name>-<policy-name>-<uuid>` | `ilm-searchable-snapshot-<uuid>` |
| **Index name stored inside snapshot** | Raw `.ds-...` backing index name | `fm-clone-<uuid>-.ds-...` (clone name) |

### What this means for restore
- **v8.19**: You can search all snapshots for one whose `.indices[]` contains the bare `.ds-...` name directly.
- **v9.2+**: The snapshot stores the `fm-clone-` clone name, not the original. Your `rename_pattern` must strip the prefix:
  ```
  rename_pattern:     ".*\\.ds-(.+)"
  rename_replacement: "restored-$1"
  ```

---

## Frozen-tier mount names

| | v8.19 | v9.2+ |
|---|---|---|
| **Live frozen mount visible in data stream** | `partial-.ds-<name>` | `partial-fm-clone-<uuid>-.ds-<name>` |

---

## Cleanup script filter

| | v8.19 | v9.2+ |
|---|---|---|
| **How to identify ILM snapshots** | `test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-")` | `startswith("ilm-searchable-snapshot-")` |

---

## `index.hidden` after restore

| | v8.19 | v9.2+ |
|---|---|---|
| **Restored index visibility** | Inherits `index.hidden = true` from the frozen mount; must be explicitly set to `false` | No hidden-flag issue observed |

After a v8.19 restore, run:
```json
PUT /restored2-<index-name>/_settings
{ "index": { "hidden": false } }
```

---

## SLM behaviour (both versions)

SLM snapshots are **not reliable** as a recovery mechanism for ILM-managed frozen-tier indices:

- SLM takes snapshots on a fixed schedule, not aligned with ILM phase transitions.
- There is a window — often hours — between ILM deleting the backing index and the next SLM snapshot, during which no external snapshot of the live index exists.
- Using `wait_for_snapshot` in an ILM delete action **permanently stalls** ILM if no SLM policy matches.
  ILM enters an ERROR state and the data stream stops rolling over. See
  [`docs/findings/v8.19-slm-waitfor.md`](findings/v8.19-slm-waitfor.md) for the full test report.

**Recommendation**: Rely on the ILM-managed searchable-snapshot step for recovery — not SLM — when working with frozen-tier data.

---

## Quick reference: which script to use

| Task | v8.19 | v9.4 |
|---|---|---|
| Restore a deleted backing index | `scripts/v8.19/restore_index.sh` | `scripts/v9.4/restore_index.sh` |
| Clean up old ILM snapshots | `scripts/v8.19/cleanup_old_snapshots.sh` | `scripts/v9.4/cleanup_old_snapshots.sh` |
| Audit snapshot storage | `scripts/v8.19/check_snapshot_datasize.sh` | `scripts/v9.4/check_snapshot_datasize.sh` |
| Kibana Dev Tools scenario | `scenarios/v8.19/base.txt` | `scenarios/v9.4/base.txt` |
