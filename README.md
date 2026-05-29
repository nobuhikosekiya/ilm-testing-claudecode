# Elasticsearch ILM Behaviour Tests

> [!CAUTION]
> **Use a NEW, dedicated test cluster — never run this against a shared or production deployment.**
>
> These scenarios make **cluster-level changes** and execute **destructive deletion APIs** that affect shared state:
>
> - **Cluster settings** — `PUT _cluster/settings` modifies `indices.lifecycle.poll_interval` globally, affecting ILM timing for every index on the cluster, not just the test index.
> - **Snapshot deletion** — `cleanup_old_snapshots.sh` deletes snapshots from the shared `found-snapshots` repository. A poorly chosen keyword could match and permanently delete snapshots that belong to other indices.
> - **Data stream and index deletion** — cleanup removes the test data stream and all restored indices. On a shared cluster, a naming collision could silently wipe unrelated data.
> - **ILM policy and template deletion** — Step 9 teardown removes named policies and templates which could conflict with or replace existing ones if names are reused.
>
> Spin up a fresh Elastic Cloud deployment, run the tests, then tear it down. Do not point this at any cluster that holds data you care about.

A test suite for verifying **ILM (Index Lifecycle Management)** behaviour on Elastic Cloud deployments — covering phase transitions, snapshot lifecycle, SLM integration, tiered storage, and operational pitfalls.

Tests cover multiple Elasticsearch versions. Each scenario is a self-contained end-to-end flow: from policy creation and data ingestion through phase transitions to deletion. Manually restoring a deleted backing index from its ILM snapshot is supported as an optional step for users who need to verify recoverability, but it is not the primary focus of most scenarios.

This repo is designed to be driven entirely through **Claude Code**. Two slash commands handle all test operations; no direct API calls or manual script execution are needed.

---

## Prerequisites

- [Claude Code](https://claude.ai/code) with this repo open as the working directory
- An Elastic Cloud deployment running the version you want to test (dedicated test cluster — **not production**)
- An API key with: `manage`, `monitor`, `manage_ilm`, `manage_slm`, `manage_index_templates` cluster privileges and `all` index privileges on `logs-mytest-*`

---

## Quick start

### 1. Set up credentials

```bash
cp .env.example .env
# Edit .env — fill in ES_URL and API_KEY for your test cluster
```

### 2. Create a new scenario

To create a scenario for a new version or a new test variant, type:

```
/new-ilm-scenario
```

Claude will ask you for the version, variant type, timing, and namespace, then generate the scenario file at `scenarios/<version>/<variant>.txt` and scaffold any missing scripts.

### 3. Run a test scenario

In Claude Code, type:

```
/run-ilm-test
```

Claude will:
1. Show the target cluster URL and ask you to confirm it is a dedicated test cluster
2. Ask which version and scenario variant to run
3. Check for leftover resources from previous runs
4. Execute the scenario end-to-end, writing timestamped output to `runs/<version>/<variant>.txt`
5. Write a findings summary to `docs/findings/<version>-<variant>.md`
6. Stop and wait for you to say **"cleanup"** before deleting anything

Scenarios that include a restore step will execute it as part of the flow. For scenarios that don't, manual restore is available separately via the scripts in `scripts/<version>/` if needed.

### 4. Clean up after a test

Tell Claude:

```
cleanup
```

Claude will delete all resources created during the run: data stream, restored indices, ILM/SLM policies, index template, and snapshots. Cleanup never runs automatically.

---

## What's in this repo

```
scenarios/         Kibana Dev Tools command sequences
  v8.19/
    host_frozen_delete_keepsnapshot.txt              Base ILM restore test
    normal_slm_usage_with_frozen.txt               Extended: demonstrates SLM snapshot unreliability
    longslm_restore_post_frozen.txt        Positive SLM path: SLM as a reliable sole backup
    hot_cold_frozen_delete.txt   Hot → Cold → Frozen tiered migration
    slm_storage_cost.txt  SLM snapshot storage cost analysis
  v9.4/
    host_frozen_delete_keepsnapshot.txt              Base ILM restore test for v9.x
    normal_slm_usage_with_frozen.txt               SLM variant for v9.x

scripts/           Shell utilities (used internally by /run-ilm-test)
  v8.19/
    restore_index.sh          Restore one backing index from its ILM snapshot
    cleanup_old_snapshots.sh  Delete ILM snapshots older than N minutes
    check_snapshot_datasize.sh  Audit incremental/total storage per snapshot
  v9.4/
    (same scripts, v9.4-aware)

docs/
  version-differences.md    Side-by-side v8.19 vs v9.x behaviour reference
  findings/
    v8.19-host_frozen_delete_keepsnapshot.md           Results — base restore scenario
    v8.19-longslm_restore_post_frozen.md     Results — SLM as a reliable backup (positive path)
    v8.19-slm-storage-cost.md  Results — SLM snapshot storage cost
    v8.19-hot_cold_frozen_delete.md   Results — hot/cold/frozen tiered migration
    v9.4-host_frozen_delete_keepsnapshot.md            Results — v9.4 base restore

runs/              Raw timestamped output from completed test runs
  v8.19/
    run1.txt, run2.txt, run3.txt, run4.txt, run5.txt
    normal_slm_usage_with_frozen.txt, longslm_restore_post_frozen.txt, hot_cold_frozen.txt, hot_cold_frozen_run2.txt, slm_storage_cost.txt
  v9.4/
    run1.txt
```

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
