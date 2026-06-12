---
description: Run the ci-local harness and format all findings — single repo or fleet-wide (active repos, --public, --private, or --all). Surfaces SARIF findings + remediation plan; skips CANNOT-RUN and UPLOAD-ONLY-FAILED noise.
allowed-tools: Bash(make ci-local*), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/check-workspace-state.sh*), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/check-session-state.sh*), Bash(find * -name "*.sarif" -path "*/.ci-local/*"), Bash(ls */.ci-local/), Bash(gh repo view *), Bash(cd *)
---

Run the `ffreis-platform-ci-local` harness and report all findings.

## Step 1 — determine scope from $ARGUMENTS

Parse `$ARGUMENTS`:

| Input | Scope |
|---|---|
| empty, `.`, or omitted | current working directory repo |
| `<path>` (relative or absolute to a repo) | that specific repo |
| `--all` | all repos with pending work (active list from workspace state) |
| `--public` | active repos that are public on GitHub |
| `--private` | active repos that are private on GitHub |

For **single-repo** mode: proceed to Step 2.

For **fleet** mode (`--all`, `--public`, `--private`):
1. Run `bash /media/ffreis/second/projects/quality-kit/scripts/check-workspace-state.sh` to get the active repos list (repos with uncommitted, unpushed, or stashed work).
2. If `--public` or `--private`, filter by visibility: run `gh repo view <owner>/<repo> --json isPrivate --jq '.isPrivate'` per repo (batch as parallel Bash calls).
3. Then run Step 2 for each repo **in parallel using the Workflow tool** (one agent per repo, `isolation: "worktree"` not needed — findings are written to `.ci-local/` inside each repo's own tree, which is safe for parallel reads).

## Step 2 — run the harness (per repo)

```bash
cd <repo-path>
make ci-local ARGS="--findings"
```

This runs `act --bind`, captures SARIF to `.ci-local/`, classifies jobs, and aggregates findings via `ci-local-findings.py`. It exits non-zero if any ERROR-severity findings were found or if a job was REAL-FAIL.

If `make ci-local` is not defined in the repo's Makefile, fall back to:
```bash
bash /media/ffreis/second/projects/platform/ffreis-platform-standards/scripts/run-ci-local.sh --findings
```

Capture both stdout and exit code. Do not abort on non-zero exit — collect the output and classify it.

## Step 3 — collect output

After the run, collect:
- The stdout/stderr from the `make ci-local` call
- SARIF files: `find <repo>/.ci-local/ -name "*.sarif" 2>/dev/null`
- Aggregate report: `<repo>/.ci-local/findings-report.txt` or `.ci-local/findings.json` if present

## Step 4 — format the report

For **single repo**, present:

---

**CI Findings — `<repo-name>` ([branch])**

**Job summary**
| Job | Status |
|---|---|
| go-lint | PASS |
| gitleaks | FOUND-FINDINGS |
| ... | ... |

Statuses:
- ✅ PASS — clean
- ⚠️ FOUND-FINDINGS — scanner found issues (listed below)
- 🔇 UPLOAD-ONLY-FAILED — scanner ran, findings captured, only the GitHub upload step failed (treat as PASS for local purposes)
- ❌ REAL-FAIL — job failed before producing output (needs investigation)
- ⊘ CANNOT-RUN — job requires GitHub infra not available locally (skip, do not flag as a problem)

**Findings** (omit if zero)
Group by severity (ERROR first, then WARNING, then NOTE). For each finding:

```
[SEVERITY] tool/ruleId
  file:line — message
  ↳ fix: <remediation from the harness>
```

**Summary**
- X ERROR(s), Y WARNING(s), Z NOTE(s) across N jobs
- Gate: PASS / FAIL (fail = any ERROR present)

---

For **fleet** mode, show the single-repo block per repo, then a fleet summary:

---

**Fleet CI Findings — [date]**

| Repo | ERRORs | WARNINGs | Gate |
|---|---|---|---|
| petlook-lambdas-rust | 0 | 2 | ✅ |
| ffreis-posts | 1 | 0 | ❌ |
| ... | | | |

**Top findings across fleet** (ERRORs only, deduplicated by tool+ruleId):
List unique error patterns, how many repos they affect, and the fix.

---

## Step 5 — remediation offer

After the report, if any ERRORs were found, offer:

> Want me to apply remediations? I can run `make ci-local ARGS="--findings --remediate"` which uses `ci-local-remediate.py` to generate inline fixes (≤3 errors/category applied directly) or queued Claude prompts for larger batches.

Do not auto-apply — wait for explicit confirmation.
