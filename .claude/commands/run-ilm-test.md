# Run an ILM test scenario end-to-end

Execute an ILM test scenario, capture all output to a file, and create a findings summary.
Follow every rule in `CLAUDE.md` exactly.

---

## ⚠️ HARD STOP — Production cluster check

**Before asking anything else, read the cluster URL from `.env_<version>` and show it to the user.**

Then display this warning verbatim, in full, every time — no matter what:

```
╔══════════════════════════════════════════════════════════════════════╗
║              ⛔  DO NOT RUN ON A PRODUCTION CLUSTER  ⛔              ║
╠══════════════════════════════════════════════════════════════════════╣
║  This test WILL:                                                     ║
║    • Create and DELETE a data stream and all its backing indices     ║
║    • Create and DELETE ILM policies and index templates              ║
║    • Take and DELETE snapshots in found-snapshots                    ║
║    • Temporarily shorten the cluster-wide ILM poll interval          ║
║                                                                      ║
║  These operations are DESTRUCTIVE and affect the entire cluster.     ║
║  Run this ONLY on a dedicated, disposable test deployment.           ║
╚══════════════════════════════════════════════════════════════════════╝

Target cluster: <ES_URL from .env_<version>>
```

Then ask explicitly:
**"Is this a dedicated test cluster with no production data? (yes / no)"**

- If the user answers **anything other than "yes"** → **STOP immediately. Do not proceed.**
  Tell the user: "Aborting. Re-run /run-ilm-test once you have a dedicated test cluster."

- If the user answers **"yes"** → continue to Step 1.

---

## Step 1 — Pre-flight questions

Ask the user ALL of the following before executing anything:

1. **Version** — Which version to test?
   Show available versions:
   ```bash
   ls scenarios/
   ```

2. **Variant** — Which scenario to run?
   Show available variants for the chosen version:
   ```bash
   ls scenarios/<version>/
   ```

3. **Output file** — Confirm the output file name.
   - Check existing run files:
     ```bash
     ls runs/<version>/
     ```
   - For `base` scenarios: determine the next run number
     - If `run1.txt` does not exist → `run1.txt`
     - If `run1.txt` exists but `run2.txt` does not → `run2.txt`
     - etc.
   - For `slm` and `slm_waitfor` variants: output goes to `runs/<version>/<variant>.txt`
     - If it already exists, warn the user and ask if they want to create `<variant>_run2.txt` etc.
   - Show the user what the output file will be called and ask them to confirm.

4. **Stop-at step** — Should the run stop at a specific step?
   Default is to run all steps to completion. If the user names a step (e.g., "stop after Step 5"),
   stop exactly there and do not continue.

Wait for the user to confirm before proceeding.

---

## Step 2 — Pre-run checks

```bash
# Read the scenario file fully before starting
cat scenarios/<version>/<variant>.txt

# Read the restore script to know current RESTORE_PREFIX
cat scripts/<version>/restore_index.sh

# Source credentials
source .env_<version>

# Verify cluster connectivity
curl -s "$ES_URL/" -H "Authorization: ApiKey $API_KEY" | \
  jq '{version: .version.number, cluster_name: .cluster_name}'
```

Confirm the cluster version matches the test version. If it does not match, **stop and warn the user**.

Check for leftover resources from a previous run:
```bash
# Data stream
curl -s "$ES_URL/_data_stream/logs-mytest-*" -H "Authorization: ApiKey $API_KEY" | jq '.'

# Restored indices
curl -s "$ES_URL/_cat/indices/restored-*?v" -H "Authorization: ApiKey $API_KEY"

# ILM policy
curl -s "$ES_URL/_ilm/policy/approach_a_*" -H "Authorization: ApiKey $API_KEY" | jq 'keys'

# ILM snapshots
curl -s "$ES_URL/_snapshot/found-snapshots/_all" -H "Authorization: ApiKey $API_KEY" | \
  jq '[.snapshots[] | select(.snapshot | (startswith("ilm-searchable-snapshot-") or test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-"))) | .snapshot]'
```

If any leftover resources are found, **stop and tell the user** what was found.
Do not proceed until the user says the cluster is clean.

---

## Step 3 — Open the output file

Set up the output file. All subsequent output MUST be written with `tee -a`:

```bash
OUTPUT_FILE="runs/<version>/<output_name>"
mkdir -p "runs/<version>"

{
  echo "======================================================================"
  echo "<VERSION> <VARIANT> Test Scenario — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "======================================================================"
  echo ""
  echo "Scenario file : scenarios/<version>/<variant>.txt"
  echo "Output file   : $OUTPUT_FILE"
  echo "Cluster       : $ES_URL"
  echo ""
} | tee "$OUTPUT_FILE"
```

From this point, **every command's output must be appended to the output file using `tee -a "$OUTPUT_FILE"`**.

---

## Step 4 — Execute each step

Work through the scenario file in order. For each step:

1. Print the step label:
   ```
   ── STEP N: <description from scenario comment> ──
   ```

2. Execute the API call as a `curl` command.

3. Print the raw JSON response.

4. Append everything to the output file.

Do **not** skip steps. Do **not** combine steps that the scenario treats separately.

### Translating Dev Tools syntax to curl

The scenario file uses Kibana Dev Tools format. Translate each command as follows:

- `PUT <path>` + JSON body → `curl -s -X PUT "$ES_URL/<path>" -H "Authorization: ApiKey $API_KEY" -H "Content-Type: application/json" -d '<json>'`
- `POST <path>` + JSON body → `curl -s -X POST "$ES_URL/<path>" -H "Authorization: ApiKey $API_KEY" -H "Content-Type: application/json" -d '<json>'`
- `GET <path>` → `curl -s "$ES_URL/<path>" -H "Authorization: ApiKey $API_KEY"`
- `DELETE <path>` → `curl -s -X DELETE "$ES_URL/<path>" -H "Authorization: ApiKey $API_KEY"`

### ILM monitoring loop (Step 5)

When waiting for ILM to progress through phases:

- Poll every 10 seconds
- On each tick, print a `[HH:MM:SS]` timestamp (use `date -u +%H:%M:%S`)
- On each tick, log:
  - Current backing index list: `GET _cat/indices/.ds-logs-mytest-<namespace>-*?v`
  - ILM snapshot count in `found-snapshots`
  - ILM explain state for each backing index

Exit the loop when the target condition is met (e.g., 000001 and 000002 no longer appear in the index list, confirming ILM has deleted them).

Example poll structure:
```bash
while true; do
  TIMESTAMP=$(date -u +%H:%M:%S)
  echo "" | tee -a "$OUTPUT_FILE"
  echo "[$TIMESTAMP] --- poll ---" | tee -a "$OUTPUT_FILE"

  echo "[$TIMESTAMP] Backing indices:" | tee -a "$OUTPUT_FILE"
  curl -s "$ES_URL/_cat/indices/.ds-logs-mytest-<namespace>-*?v" \
    -H "Authorization: ApiKey $API_KEY" | tee -a "$OUTPUT_FILE"

  SNAP_COUNT=$(curl -s "$ES_URL/_snapshot/found-snapshots/_all" \
    -H "Authorization: ApiKey $API_KEY" | \
    jq '[.snapshots[] | select(.snapshot | (startswith("ilm-searchable-snapshot-") or test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-")))] | length')
  echo "[$TIMESTAMP] ILM snapshot count: $SNAP_COUNT" | tee -a "$OUTPUT_FILE"

  # Check termination condition (adapt based on scenario)
  STATUS=$(curl -s "$ES_URL/.ds-logs-mytest-<namespace>-default-*-000001" \
    -H "Authorization: ApiKey $API_KEY" | jq -r '.status // "not_found"')
  if [ "$STATUS" == "404" ] || echo "$STATUS" | grep -q "index_not_found"; then
    echo "[$TIMESTAMP] Target index deleted — proceeding." | tee -a "$OUTPUT_FILE"
    break
  fi

  sleep 10
done
```

### Restore step

When the scenario calls for restore:
```bash
echo "" | tee -a "$OUTPUT_FILE"
echo "── STEP 6: Restore backing indices ──" | tee -a "$OUTPUT_FILE"
echo "Using restore prefix: <RESTORE_PREFIX from script>" | tee -a "$OUTPUT_FILE"

./scripts/<version>/restore_index.sh .ds-logs-mytest-<namespace>-default-<date>-000001 \
  | tee -a "$OUTPUT_FILE"
```

Repeat for each backing index that needs restoring.

---

## Step 5 — Stopping

If the user specified a stop-at step:
- When you reach that step, execute it, then **stop**.
- Print to terminal and append to output file:
  ```
  ══════════════════════════════════════════════════════════════════════
  RUN STOPPED — completed through Step N at [HH:MM:SS]
  Cluster is in the state as of Step N. No cleanup has been run.
  ══════════════════════════════════════════════════════════════════════
  ```
- Do not run any further steps. Do not run cleanup.
- Report the output file location.

---

## Step 6 — Write the run footer

When the full run completes (or is stopped):
```bash
{
  echo ""
  echo "======================================================================"
  echo "RUN COMPLETE — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Output file: $OUTPUT_FILE"
  echo "======================================================================"
} | tee -a "$OUTPUT_FILE"
```

---

## Step 7 — Create findings summary (full runs only)

After a **complete** run (not a stopped run), create the summary **before** any cleanup.

1. Check if `docs/findings/<version>-<variant>.md` exists:
   - If **no**: create it fresh
   - If **yes**: read it first; append a dated "Run N update" section

2. Write the summary by reading the output file. Do not rely on memory.
   Required sections (follow CLAUDE.md format):

   ```markdown
   # ILM Restore Test — <VERSION> <VARIANT>

   ## Run metadata
   | Field | Value |
   |---|---|
   | Cluster | ... |
   | ES version (confirmed) | ... |
   | Run date | ... |
   | Duration | ... |
   | Output file | runs/<version>/<output_name> |
   | Scenario file | scenarios/<version>/<variant>.txt |
   | Data stream | logs-mytest-<namespace>-default |
   | ILM policy | approach_a_<namespace>_policy |

   ## Timeline
   (key events with HH:MM:SS timestamps from the output file)

   ## Findings
   (one clearly labelled finding per observed behaviour)

   ## ILM snapshot names
   (snapshot names captured during the run, for traceability)

   ## Notes for the scenario file
   (anything in the .txt scenario that needs correcting or improving)
   ```

---

## Step 8 — Final report

Print a clean summary to the terminal:

```
✅ Test complete
   Version  : <version>
   Variant  : <variant>
   Output   : runs/<version>/<output_name>
   Summary  : docs/findings/<version>-<variant>.md

Next steps:
  • Review the findings summary
  • Run cleanup when ready (tell me "cleanup" to start)
```

**Do not run cleanup automatically.** Only run cleanup if the user explicitly says "cleanup" or "clean up".
