# Create a new ILM test scenario

You are creating a new Kibana Dev Tools test scenario for this ILM restore test project.
Follow every instruction below precisely.

---

## Step 1 — Gather context (ask ALL questions before generating anything)

Ask the user the following questions. Ask them all together in one message — do NOT generate any files yet.

**Question set:**

1. **ES version** — Which Elasticsearch version is this scenario for?
   (e.g., `v9.6`, `v10.0`). Check existing versions with `ls scenarios/`.

2. **Variant** — What kind of test?
   - `base` — The standard flow: ILM moves a backing index to the frozen tier, deletes it, you restore from the ILM snapshot. The core reference scenario.
   - `slm` — Extends base to demonstrate that SLM is **not** a reliable backup for frozen-tier indices (shows the timing gap between ILM deletion and the next SLM snapshot).
   - `slm_waitfor` — Extends slm to demonstrate the `wait_for_snapshot` **permanent stall trap**: adding `wait_for_snapshot` to the ILM delete action appears safe but permanently stalls ILM when SLM is on a far-future schedule.
   - **Other** — Describe what you want to test; the scenario will be tailored to your description.

3. **Data stream namespace** — A short identifier for the test data stream.
   Drives all resource names: `logs-mytest-<namespace>-default`, policy name, template name, restore prefix.
   Examples: `default`, `v2`, `production`, `myapp`. Keep it short, lowercase, no spaces.

4. **ILM timing** — How long before the delete phase fires?
   - `fast` — frozen: `0m`, delete: `3m` ← recommended for quick testing
   - `realistic` — frozen: `0m`, delete: `1h`
   - `custom` — you specify both `frozen min_age` and `delete min_age`

5. **Backing index count** — How many docs to ingest and rollovers to trigger?
   Default is `3`. More indices means more restore steps to demonstrate.

6. **SLM settings** (only for `slm` and `slm_waitfor` variants):
   - SLM schedule (cron expression). Default: `"0 0 1 1 ? 2099"` (far future — ensures SLM never auto-runs during the test, exposing the gap or stall)
   - SLM max snapshot count (default: `3`)

Wait for the user's answers before proceeding.

---

## Step 2 — Validate before generating

After receiving answers:

1. **Check if the file already exists:**
   ```
   scenarios/<version>/<variant>.txt
   ```
   If it exists, **stop** and tell the user. Do not overwrite.

2. **Identify the best template to base this on:**
   - Same version + same variant → that file (but it exists, so you'd have stopped above)
   - Same version + different variant → use `scenarios/<version>/host_frozen_delete_keepsnapshot.txt`
   - Different version, same major (v8.x or v9.x) → use the existing version's `host_frozen_delete_keepsnapshot.txt`
   - New major version → read `docs/version-differences.md` carefully; pick the closest existing scenario

3. **Read the chosen template file fully** before generating anything.

4. **Read `docs/version-differences.md`** to confirm the correct version-specific details
   (snapshot naming pattern, rename_pattern, cleanup filter, index.hidden caveat, fm-clone prefix).

---

## Step 3 — Determine resource names

Derive all resource names from the user's inputs. Use this naming scheme:

| Resource | Pattern | Example (namespace=`myapp`) |
|---|---|---|
| Data stream | `logs-mytest-<namespace>-default` | `logs-mytest-myapp-default` |
| Index pattern (template) | `logs-mytest-<namespace>-*` | `logs-mytest-myapp-*` |
| ILM policy | `approach_a_<namespace>_policy` | `approach_a_myapp_policy` |
| Index template | `approach_a_<namespace>_template` | `approach_a_myapp_template` |
| SLM policy (if applicable) | `approach_a_<namespace>_slm_policy` | `approach_a_myapp_slm_policy` |
| Restore prefix | `restored-<namespace>-` | `restored-myapp-` |
| SLM restore prefix (if applicable) | `restored-<namespace>-slm-` | `restored-myapp-slm-` |

---

## Step 4 — Version-specific scenario rules

Apply these rules based on the version's major line:

### v8.x (including v8.19)
- **Snapshot naming:** `<YYYY.MM.DD>-<index-name>-<policy-name>-<uuid>` (date prefix)
- **Snapshot contains:** raw `.ds-...` backing index name (no `fm-clone-` prefix)
- **Restore `rename_pattern`:** `"\\.ds-(.+)"`
- **Cleanup filter (jq):** `test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-")`
- **After restore:** restored indices inherit `index.hidden = true` — must set to `false`
- **Scripts to reference:** `scripts/v8.19/restore_index.sh`, `scripts/v8.19/cleanup_old_snapshots.sh`
- **Header warning:** Include the "NO fm-clone step" note

### v9.x (v9.2 and later)
- **Snapshot naming:** `ilm-searchable-snapshot-<uuid>`
- **Snapshot contains:** `fm-clone-<uuid>-.ds-...` clone name
- **Restore `rename_pattern`:** `".*\\.ds-(.+)"`
- **Cleanup filter (jq):** `startswith("ilm-searchable-snapshot-")`
- **After restore:** No `index.hidden` issue
- **Scripts to reference:** `scripts/v9.4/restore_index.sh`, `scripts/v9.4/cleanup_old_snapshots.sh`
- **Header warning:** Include the "fm-clone step" note

---

## Step 5 — Scenario structure to generate

Generate the scenario file at `scenarios/<version>/<variant>.txt`.
Follow this step structure (match the style and comment density of the existing scenarios):

```
// =====================================================================
// Header block:
//   - Title line including version and variant name
//   - PURPOSE section explaining what this scenario tests
//   - Version-specific DIFFERENCE note (fm-clone or no fm-clone)
//   - RESOURCE NAMES table (for variants that differ from base)
// =====================================================================

Step 1:  PUT _cluster/settings  →  shorten ILM poll interval to 10s
Step 2:  PUT _ilm/policy/<policy_name>  →  ILM policy with user's timing
         [slm/slm_waitfor only] PUT _slm/policy/<slm_policy_name>
Step 3:  PUT _index_template/<template_name>  →  index template
Step 4:  POST logs-mytest-<namespace>-default/_doc  ×N  →  ingest docs
         (with "WAIT ~15 SECONDS" comment between each)
Step 5:  GET _cat/indices/.ds-logs-mytest-<namespace>-*?v  →  identify backing indices
         GET .ds-logs-mytest-<namespace>-default-<date>-000001  →  polling loop
Step 6:  Restore phase
         - Comment showing how to find the ILM snapshot
         - Version-appropriate rename_pattern
         - Manual Dev Tools restore commands for each backing index
         - [slm/slm_waitfor] Additional steps to attempt SLM restore and show failure
Step 7:  Query restored indices
         - PUT <restored_index>/_settings  { "index": { "hidden": false } }  [v8.x only]
         - GET restored-<namespace>-*/_search
Step 8:  Cleanup snapshots
         - Manual DELETE _snapshot/found-snapshots/<snapshot_name>
Step 9:  Environment cleanup
         - Reset ILM poll interval to null
         - DELETE _data_stream/logs-mytest-<namespace>-default
         - DELETE restored-<namespace>-*
```

For **`slm_waitfor`** variant, add between Step 1 and Step 2:
- A detailed PURPOSE comment explaining the two failure modes (permanent stall + false sense of security)
- The ILM delete phase must include `"wait_for_snapshot": { "policy": "<slm_policy_name>" }`
- Steps to demonstrate the stall: show ILM ERROR state, then show how to manually trigger SLM
- Steps to attempt restore from the "protecting" SLM snapshot and show it returns empty/fails

---

## Step 6 — Check if new version needs scripts

After writing the scenario file, check:

```bash
ls scripts/<version>/
```

If the `scripts/<version>/` directory does not exist:
1. Copy the closest version's scripts:
   - v8.x → copy from `scripts/v8.19/`
   - v9.x → copy from `scripts/v9.4/`
2. In each script, update the `source` line:
   - Change `.env` or `.env_v9.4` → `.env_<new_version>`
3. Update version comments in the script headers
4. Tell the user: "Created `scripts/<version>/`. You'll need to create `.env_<version>` from `.env.example` before running the scripts."

---

## Step 7 — Report

After generating all files, print a clear summary:

```
✅ Created: scenarios/<version>/<variant>.txt
[✅ Created: scripts/<version>/  (if new version)]

Resource names used:
  Data stream      : logs-mytest-<namespace>-default
  ILM policy       : approach_a_<namespace>_policy
  Index template   : approach_a_<namespace>_template
  [SLM policy      : approach_a_<namespace>_slm_policy]

Next steps:
  1. [If new version] Copy .env.example → .env_<version> and fill in ES_URL and API_KEY
  2. Open scenarios/<version>/<variant>.txt in Kibana Dev Tools to review
  3. Run the test with /run-ilm-test
```
