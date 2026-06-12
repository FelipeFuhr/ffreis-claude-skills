---
description: Run the ci-local harness and format all findings — single repo or fleet-wide (active repos, --public, --private, or --all). Supports act-only (default), act+sonar (--sonar-local), sonar-only (--sonar-local-only), or SonarCloud (--sonar-cloud). Surfaces SARIF findings + remediation plan; skips CANNOT-RUN and UPLOAD-ONLY-FAILED noise.
allowed-tools: Bash(make ci-local*), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/check-workspace-state.sh*), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/check-session-state.sh*), Bash(find * -name "*.sarif" -path "*/.ci-local/*"), Bash(ls */.ci-local/), Bash(gh repo view *), Bash(cd *)
---

Run the `ffreis-platform-ci-local` harness and report all findings.

## Step 1 — determine scope and mode from $ARGUMENTS

### Scope flags

| Input | Scope |
|---|---|
| empty, `.`, or omitted | current working directory repo |
| `<path>` (relative or absolute to a repo) | that specific repo |
| `--all` | all repos with pending work (active list from workspace state) |
| `--public` | active repos that are public on GitHub |
| `--private` | active repos that are private on GitHub |

### Lane flags (can combine with scope flags)

| Flag | Harness args | What runs |
|---|---|---|
| *(none)* | `--findings` | Lane A only — act runs all CI jobs, captures SARIF |
| `--sonar-local` | `--full` | Lane A + B — act **and** local SonarQube container |
| `--sonar-local-only` | `--lane-b-only` | Lane B only — SonarQube container, skips act |
| `--sonar-cloud` | `--lane-b-only --sonar-cloud` | SonarCloud PR analysis instead of local container |

**SonarQube container notes:**
- First boot takes ~4.5 min; warm reuse skips it.
- Requires ≥10 GB disk and ≥6 GB RAM — the harness checks and falls back to `--sonar-cloud` if either is tight.
- Only runs on repos with a `.github/workflows/*.yml` referencing a sonar step (the harness probes before starting the container).
- `--sonar-cloud` requires `SONAR_TOKEN` env var and a non-`main` branch (won't clobber the main analysis).

For **single-repo** mode: proceed to Step 2.

For **fleet** mode (`--all`, `--public`, `--private`):
1. Run `bash /media/ffreis/second/projects/quality-kit/scripts/check-workspace-state.sh` to get the active repos list.
2. If `--public` or `--private`, filter: `gh repo view <owner>/<repo> --json isPrivate --jq '.isPrivate'` per repo (parallel Bash calls).
3. Run Step 2 for each repo **in parallel using the Workflow tool** (findings go to each repo's own `.ci-local/` — no collision).
4. **Fleet + `--sonar-local` / `--sonar-local-only`**: run repos sequentially, not in parallel — the SonarQube container is shared and can't serve multiple analyses at once.

## Step 2 — run the harness (per repo)

Determine the `ARGS` value from the lane flag (see table in Step 1), then:

```bash
cd <repo-path>
make ci-local ARGS="<harness-args>"
```

**Fallback** — if `make ci-local` is absent or doesn't support the requested flag (e.g. repo is on an old standards SHA that pre-dates `--full`):
```bash
bash /media/ffreis/second/projects/platform/ffreis-platform-ci-local/scripts/run-ci-local.sh <harness-args>
```

Capture stdout and exit code. Do not abort on non-zero exit — collect and classify.

## Step 3 — collect output

After the run, collect:
- The stdout/stderr from the harness call
- SARIF files: `find <repo>/.ci-local/ -name "*.sarif" 2>/dev/null`
- Aggregate report: `<repo>/.ci-local/findings-report.txt` or `.ci-local/findings.json` if present
- Lane B report: `<repo>/.ci-local/lane-b.json` if present (SonarQube issues)

## Step 4 — format the report

For **single repo**, present:

---

**CI Findings — `<repo-name>` ([branch]) [lanes run]**

**Job summary**
| Job | Lane | Status |
|---|---|---|
| go-lint | A (act) | PASS |
| gitleaks | A (act) | FOUND-FINDINGS |
| sonarqube | B (sonar) | FOUND-FINDINGS |
| ... | | ... |

Statuses:
- ✅ PASS — clean
- ⚠️ FOUND-FINDINGS — scanner found issues (listed below)
- 🔇 UPLOAD-ONLY-FAILED — scanner ran, findings captured, only the GitHub upload step failed (treat as PASS for local purposes)
- ❌ REAL-FAIL — job failed before producing output (needs investigation)
- ⊘ CANNOT-RUN — job requires GitHub infra not available locally (skip, not a problem)
- ⏭ CANNOT-RUN-FAITHFULLY — tool ran but results are unreliable locally (e.g. trivy-action PATH bug)

**Findings** (omit if zero)
Group by lane first (A then B), then by severity (ERROR → WARNING → NOTE). For each finding:

```
[LANE A | SEVERITY] tool/ruleId
  file:line — message
  ↳ fix: <remediation from the harness>

[LANE B | SEVERITY] sonar/ruleKey
  file:line — message
  ↳ fix: <remediation from the harness>
```

**Summary**
- Lane A: X ERROR(s), Y WARNING(s)
- Lane B: X ERROR(s), Y WARNING(s)  *(omit if lane B didn't run)*
- Gate: PASS / FAIL (fail = any ERROR in either lane)

---

For **fleet** mode, per-repo blocks then a fleet summary:

**Fleet CI Findings — [date] [lanes]**

| Repo | A ERRORs | B ERRORs | WARNINGs | Gate |
|---|---|---|---|---|
| petlook-lambdas-rust | 0 | 2 | 1 | ❌ |
| ffreis-posts | 0 | 0 | 0 | ✅ |

**Top findings across fleet** (ERRORs only, deduped by tool+ruleId, both lanes):

---

## Step 5 — remediation offer

After the report, if any ERRORs were found, offer:

> Want me to apply remediations? I can run the harness with `--remediate` added, which uses `ci-local-remediate.py` to generate inline fixes (≤3 errors/category applied directly) or queued Claude prompts for larger batches.

Do not auto-apply — wait for explicit confirmation.
