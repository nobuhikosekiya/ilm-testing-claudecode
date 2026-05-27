# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This project tests ILM/SLM restore behaviour on Elastic Cloud deployments.
Follow these rules every time a test is executed.

---

## Repository layout

```
scenarios/         Kibana Dev Tools command sequences
  v<X.Y>/
    base.txt             Base ILM restore test
    slm.txt              Extended: SLM unreliability demo
    slm_waitfor.txt      Extended: wait_for_snapshot stall trap

scripts/           Shell utilities
  v<X.Y>/
    restore_index.sh
    cleanup_old_snapshots.sh
    check_snapshot_datasize.sh

docs/
  version-differences.md
  findings/
    v<X.Y>-base.md         Human-readable findings summary
    v<X.Y>-slm-waitfor.md  Findings for the slm_waitfor variant
  slides/

runs/              Raw captured test output
  v<X.Y>/
    run1.txt, run2.txt, ...
    slm.txt, slm_waitfor.txt
```

| Path pattern | Purpose |
|---|---|
| `scenarios/<version>/base.txt` | Kibana Dev Tools sequence for the base ILM restore test |
| `scenarios/<version>/slm.txt` | Extended variant demonstrating SLM unreliability |
| `scenarios/<version>/slm_waitfor.txt` | Variant demonstrating the `wait_for_snapshot` trap |
| `runs/<version>/run<N>.txt` | Raw captured output from a completed test run |
| `docs/findings/<version>-<variant>.md` | Human-readable findings summary |
| `scripts/<version>/restore_index.sh` | Restore one named backing index from its ILM snapshot |
| `scripts/<version>/cleanup_old_snapshots.sh` | Delete ILM snapshots older than N minutes |
| `scripts/<version>/check_snapshot_datasize.sh` | Audit incremental/total storage across all snapshots |
| `.env_<version>` | `ES_URL` and `API_KEY` for that version's Elastic Cloud deployment (gitignored) |

---

## Common commands

All scripts resolve the project root from their own location. Run from anywhere.

```bash
# Verify cluster connectivity (confirm version before every test)
source .env_v8.19
curl -s "$ES_URL/" -H "Authorization: ApiKey $API_KEY" | \
  jq '{version: .version.number, cluster_name: .cluster_name}'

# Restore a deleted backing index from its ILM snapshot
./scripts/v8.19/restore_index.sh .ds-logs-mytest-v8-default-2026.05.27-000001

# Delete ILM snapshots older than N minutes (default: 10)
./scripts/v8.19/cleanup_old_snapshots.sh [minutes_old]

# Audit snapshot storage for a specific backing index
./scripts/v8.19/check_snapshot_datasize.sh .ds-logs-mytest-v8-default-2026.05.27-000001
```

---

## File naming

- Scenario files live under `scenarios/<version>/` with short names: `base.txt`, `slm.txt`, `slm_waitfor.txt`.
- Scripts live under `scripts/<version>/` with short names: `restore_index.sh`, etc.
- Never overwrite or modify an existing file. Check before creating.
- Output files: `runs/<version>/run<N>.txt`
  - First run: `runs/v8.19/run1.txt`
  - Subsequent runs: `runs/v8.19/run2.txt`, `run3.txt`, …
  - Variant runs: `runs/v8.19/slm.txt`, `runs/v8.19/slm_waitfor.txt`
- Before creating any output file, list existing files and confirm the next available name.

---

## Credentials

- Each version has its own env file: `.env_v8.19`, `.env_v9.4`, etc. — all gitignored.
- Copy `.env.example` → `.env_v<X.Y>` and fill in `ES_URL` and `API_KEY`.
- Always `source` the correct env file at the start of every shell command block.
- Never hardcode credentials in scripts or output files.

---

## Before starting a test

1. Verify cluster connectivity and confirm the version matches what is being tested:
   ```bash
   source .env_v8.19
   curl -s "$ES_URL/" -H "Authorization: ApiKey $API_KEY" | jq '{version: .version.number, cluster_name: .cluster_name}'
   ```
2. Confirm no leftover resources from a previous run (data stream, restored indices, ILM snapshots, policy, template).

---

## Running the test

- Execute each step in order, mirroring the corresponding `scenarios/<version>/base.txt`.
- Write **all** output — both the command labels and raw API responses — to the output file using `tee`.
- Print a `[HH:MM:SS]` timestamp on every monitoring poll line so the timeline is clear in the output file.
- During the ILM monitoring loop (Step 5), log both the current backing index list and the ILM snapshot count on every tick.
- Do not skip steps or combine steps that the scenario file treats separately.

---

## After the test

After every completed test run, create a summary file **before** starting cleanup:

- **Filename:** `docs/findings/<version>-<variant>.md`
  - Match the variant: a run of `scenarios/v8.19/slm_waitfor.txt` → `docs/findings/v8.19-slm-waitfor.md`
  - First run of a variant: no run counter in the summary filename (one summary covers all runs unless findings differ significantly).
- **Never overwrite an existing summary.** Read it first; if the new run produced different findings, append a dated "Run N update" section rather than replacing.
- **Required sections:**
  - Header block: cluster, version, run date, duration, output file, scenario file, data stream, policy names
  - **Timeline** — key events with approximate timestamps
  - **Findings** — one clearly labelled finding per observed behaviour (failures, unexpected results, confirmations)
  - **ILM snapshot names** produced during the run (for traceability)
  - **Notes for the scenario file** — anything in the scenario `.txt` that needs correcting or improving based on what was observed
- Write the summary from the captured output file (`tee` output) — do not rely on memory alone.

---

## Stopping

- Stop exactly at the step the user specifies. Do not run any further steps automatically.
- State clearly in the terminal and in the output file that the run is stopped and at which step.
- Leave the cluster in whatever state it is at the stopping point — do not auto-cleanup.

---

## Cleanup

- Never run cleanup unless the user explicitly says "cleanup" or "clean up".
- Cleanup must cover all resources created in that run:
  - ILM poll interval (reset to null)
  - Data stream
  - Restored indices (check both `restored-` and `restored2-` prefixes, or whatever prefix the restore script uses)
  - ILM snapshots (via `scripts/<version>/cleanup_old_snapshots.sh`)
  - ILM policy
  - Index template

---

## Scripts

- Always use the versioned script for the version under test: `scripts/v8.19/restore_index.sh`, etc.
- Read the script before running it to pick up any changes the user may have made (e.g. `RESTORE_PREFIX`), and reflect the current behaviour in the output.
- If a script behaviour has changed (e.g. restore prefix changed from `restored-` to `restored2-`), note it in the terminal output.

---

## Version-specific behaviour to remember

### v8.19
- ILM snapshots contain the **raw** `.ds-...` backing index name — no `fm-clone-` prefix.
- ILM snapshot naming: `<YYYY.MM.DD>-<index-name>-<policy-name>-<uuid>` (not `ilm-searchable-snapshot-...`).
- Frozen tier mounts appear as `partial-.ds-...` in the data stream while alive; the snapshot stores the bare `.ds-...` name.
- Restored indices inherit `index.hidden = true` and must be explicitly set to `false`.
- Snapshot lookup in restore script: match by `.indices[]` content, not by snapshot name prefix.
- Cleanup script filter: `test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-")` to identify ILM snapshots.

### v9.2+
- ILM creates a `fm-clone-<uuid>-.ds-...` clone, force-merges it, and snapshots the clone.
- Snapshot contains the `fm-clone-...` name, not the bare `.ds-...` name.
- ILM snapshot naming: `ilm-searchable-snapshot-<uuid>`.
- Restore `rename_pattern` must strip the `fm-clone-` prefix: `".*\\.ds-(.+)"`.
