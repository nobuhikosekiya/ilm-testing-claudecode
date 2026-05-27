# Elasticsearch ILM Restore Tests

A test suite for verifying **ILM (Index Lifecycle Management) snapshot restore** behaviour on Elastic Cloud deployments — specifically, recovering a deleted frozen-tier backing index from the snapshot that ILM preserves before deletion.

Tests cover multiple Elasticsearch versions and explore both the correct restore path and common operational pitfalls.

---

## The Problem

When ILM transitions a data-stream backing index through the frozen tier and eventually deletes it, it first takes a searchable-snapshot. That snapshot remains in the cluster's snapshot repository (`found-snapshots`) and can be used to recover the data.

**But the restore workflow differs between Elasticsearch versions:**

| | v8.x | v9.2+ |
|---|---|---|
| Snapshot stores | raw `.ds-...` index name | `fm-clone-<uuid>-.ds-...` clone name |
| Snapshot naming | `YYYY.MM.DD-<index>-<policy>-<uuid>` | `ilm-searchable-snapshot-<uuid>` |
| Restore rename pattern | `"\\.ds-(.+)"` | `".*\\.ds-(.+)"` |
| `index.hidden` after restore | must set to `false` | no issue |

See [`docs/version-differences.md`](docs/version-differences.md) for the full comparison.

---

## What's in this repo

```
scenarios/         Kibana Dev Tools command sequences (paste into Dev Tools console)
  v8.19/
    base.txt           Base ILM restore test
    slm.txt            Extended: demonstrates SLM snapshot unreliability
    slm_waitfor.txt    Extended: demonstrates the wait_for_snapshot stall trap
  v9.4/
    base.txt           Base ILM restore test for v9.x
    slm.txt            SLM variant for v9.x

scripts/           Shell utilities (require curl and jq)
  v8.19/
    restore_index.sh          Restore one backing index from its ILM snapshot
    cleanup_old_snapshots.sh  Delete ILM snapshots older than N minutes
    check_snapshot_datasize.sh  Audit incremental/total storage per snapshot
  v9.4/
    restore_index.sh
    cleanup_old_snapshots.sh
    check_snapshot_datasize.sh

docs/
  version-differences.md    Side-by-side v8.19 vs v9.x behaviour table
  findings/
    v8.19-base.md           Test results — base restore scenario
    v8.19-slm-waitfor.md    Test results — wait_for_snapshot trap
    v9.4-base.md            Test results — v9.4 base restore
  slides/
    data_lifecycle_slm_v8.19.html  Presentation: data lifecycle & SLM pitfalls

runs/              Raw captured output from completed test runs
  v8.19/
    run1.txt, run2.txt, run3.txt
    slm.txt, slm_waitfor.txt
  v9.4/
    run1.txt
```

---

## Prerequisites

- `curl` and `jq` installed
- An Elastic Cloud deployment (ESS or ECE) running the version you want to test
- An API key with at minimum: `monitor`, `manage_ilm`, `manage_slm`, `manage_index_templates` cluster privileges and `all` index privileges on `logs-mytest-*`

---

## Quick start

### 1. Set up credentials

```bash
cp .env.example .env
# Edit .env and fill in ES_URL and API_KEY
```

### 2. Verify connectivity

```bash
source .env
curl -s "$ES_URL/" -H "Authorization: ApiKey $API_KEY" | \
  jq '{version: .version.number, cluster_name: .cluster_name}'
```

### 3. Run the scenario

Open Kibana → Dev Tools, paste the contents of `scenarios/v8.19/base.txt`, and execute each step in order.

For an automated run (writes output to file), Claude Code can drive the scenario end-to-end — see `CLAUDE.md`.

### 4. Restore a deleted backing index

```bash
./scripts/v8.19/restore_index.sh .ds-logs-mytest-v8-default-2026.05.27-000001
```

### 5. Clean up test snapshots

```bash
./scripts/v8.19/cleanup_old_snapshots.sh 10   # delete snapshots older than 10 min
```

---

## Key findings

### ✅ ILM restore works reliably

After ILM deletes a frozen-tier backing index, the ILM-managed snapshot can be used to restore it. The restore process is version-dependent (see above) but consistently reproducible.

### ⚠️ SLM is not a reliable backup for frozen-tier indices

SLM snapshots are taken on a schedule, not triggered by ILM events. There is a window — potentially hours — between when ILM deletes the live index and when the next SLM snapshot runs. During that window, the only copy of the data is the ILM snapshot.

### 🚫 `wait_for_snapshot` in a delete action stalls ILM permanently

If you configure an ILM delete action with `wait_for_snapshot` pointing to a policy that doesn't match (or hasn't run yet), ILM enters an `ERROR` state and the data stream stops rolling over. The cluster requires manual intervention to recover.

Full details: [`docs/findings/v8.19-slm-waitfor.md`](docs/findings/v8.19-slm-waitfor.md)

---

## Adding a new version

1. Create `.env_v<X.Y>` from `.env.example`
2. Copy the closest existing scenario to `scenarios/v<X.Y>/base.txt` and adjust for version-specific behaviour (see `docs/version-differences.md`)
3. Copy and update scripts to `scripts/v<X.Y>/`
4. Run the scenario and save output to `runs/v<X.Y>/run1.txt`
5. Write a summary to `docs/findings/v<X.Y>-base.md`

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
