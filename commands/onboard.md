---
description: Onboard a new product into the workspace — from a prototype zip or an existing repo — through workspace registration, repo creation, fleet-standards parity, inventory/deploy wiring and infra. Encodes the verification discipline past onboardings got wrong. Usage: /onboard <path-to-zip|repo-name> [--workspace ws-<id>] [--dry-run].
allowed-tools: Bash(cd *), Bash(uv run --project ffreis-workspace-manager ws *), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/check-session-state.sh*), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/audit-repo-standards.sh*), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/session-worktree.sh*), Bash(bash /media/ffreis/second/projects/quality-kit/scripts/check-ci.sh*), Bash(git fetch *), Bash(git show origin/*), Bash(git log *), Bash(git status*), Bash(git ls-remote *), Bash(git rev-list *), Bash(gh pr list *), Bash(gh pr view *), Bash(gh repo list *), Bash(gh api *), Bash(unzip *), Bash(ls *), Bash(grep *), Bash(make ci*), Bash(make lint*), Bash(make fmt-check*)
---

Onboard a new product into this workspace. `$ARGUMENTS` is either a prototype
archive (a `.zip` built elsewhere) or the name of an existing repo.

`ws repo new` already automates the happy path. This skill exists because the
onboardings that came before (Forma 2026-08-29, ws-media 2026-09-02, Editify
2026-09-04) each repeated the same **verification** mistakes, not the same
procedural ones. **Step 0 and Step 5 are the reason this skill exists — do not
skip them to save time.**

---

## Step 0 — Verification discipline (read before anything else)

### 0a. Audit against `origin`, never a local checkout

Local checkouts here are routinely stale, on abandoned branches, or diverged.
Two separate onboarding errors traced to exactly this:

- A reviewer declared `compiler.clean_urls` "a no-op the deployer never reads"
  and wrote that warning into a live inventory file. It had been fixed 8 days
  earlier; they had grepped a checkout ~11 commits behind on a dead branch.
- An agent declared Forma's inventory entry "unmerged, only on a branch". It was
  merged; that checkout was 14 commits behind.

Before asserting any fact about a repo:

```bash
git fetch origin --quiet
git rev-list --left-right --count HEAD...origin/main   # local-only / origin-only
git show origin/main:<path>                            # read THIS, not the worktree

```

Never `grep` a working tree to establish what the fleet currently does. If local
and origin differ, say so explicitly.

### 0b. Verify a claimed gap still exists before documenting it

Never copy a "KNOWN GAP" comment from a sibling repo's config into a new one.
Re-verify against `origin` first. A stale warning written into a config file is
worse than no comment: it tells future readers to distrust something that works,
and it propagates. If the gap is real, cite evidence (PR number, SHA, live
check). If it is fixed, delete the warning.

Prefer an empirical check over reading code where one exists — e.g. list the
deployed S3 bucket to see what the pipeline actually emitted, rather than
inferring it from a workflow file.

### 0c. Never declare a quality floor you have no tests to meet

Editify shipped `.c8rc.json` with `check-coverage: true` at 75% over two JS
files with **zero** unit tests — measured coverage 0%. It was masked by dropping
`coverage-gate` from the `ci` target while the CI job kept the name
"check + lint + test + **coverage**".

A declared-but-unenforced floor is worse than an honest absence: it reads as
covered in every audit. Either write the tests in the same PR, or omit the
config — and never let a job name claim a gate that does not run.

---

## Step 1 — Route and register the workspace

1. Decide the spoke. A product unrelated to an existing domain gets its own, per
   `PLATFORM-TARGET-ARCHITECTURE-2026-09-01.md` §9 (the media-plane precedent):
   folding it elsewhere "would misrepresent it, not simplify it". Unsure? Use the
   `workspace-router` agent.
2. Reconcile `ffreis-workspace-manager` against `origin/main` FIRST — it is often
   behind and other sessions leave in-flight branches there. Never discard them.
3. Pick an unused accent with `ws palette`. It is a closed-enum name, never a hex.
4. Register (this regenerates contexts + anchors automatically):

```bash
uv run --project ffreis-workspace-manager ws new ws-<id> \
  --title "<Product> product" --summary "<one line>" \
  --accent <unused> --consumes <caps>

```

## Step 2 — Create the repos

Typical product shape is three repos: site, `-infra`, `-lambdas-rust`.

```bash
ws repo new terraform-infra <name>-infra --to ws-<id>
ws repo new rust-lambda <name>-lambdas-rust --to ws-<id> --data first_lambda_name=<x>

```

**The site repo is a hand-import, not a Copier scaffold.** No archetype fits a
no-build static site; the fleet documents this as a "Template parity exception".
Commit 1 must be the prototype imported **verbatim** — no reformatting, no
renames — so it stays diffable against what the human reviewed. Fleet standards
land in commit 2+.

Confirm the org resolves to `ffreis-org` (`.wsmgr/config.toml`): self-hosted
runners are org-scoped and a personal-account repo queues forever.

Licence per workspace policy: products AGPL-3.0, public shared libs MIT,
everything else All Rights Reserved.

## Step 3 — Fleet standards parity

```bash
bash quality-kit/scripts/audit-repo-standards.sh --brief <repo>

```

Fix CRITICAL in this PR; note IMPORTANT; add NICE if already touching them.

Then diff `.github/workflows/` against the two closest siblings. Check:

- **Every `pull_request` trigger declares
  `types: [opened, synchronize, reopened, ready_for_review]`.** The bare
  `on: [pull_request]` form does NOT fire when a draft is promoted — and this
  workspace is draft-first, so the workflow silently never runs at the one moment
  it matters. This has recurred at least three times fleet-wide.
- Port `tests/regression/workflow-invariants.test.js` from `ffreis-forma`, which
  asserts that across every workflow file. That is the durable fix; editing
  triggers by hand is the one-off.
- Per-job `permissions`; `concurrency.cancel-in-progress`; `timeout-minutes` on
  direct jobs only, never on `uses:` caller jobs (GitHub rejects it).

## Step 4 — Always set `sonar-project.properties`

**This is a backfill, not a decision.** Every repo gets a correct
`sonar-project.properties`, whether analysis runs in SonarCloud (public repos) or
the local SonarQube containers (private repos). The file is cheap, and a missing
one silently excludes the repo from every quality sweep.

```properties
sonar.projectKey=<repo-name>
sonar.organization=<org>

```

Take `sonar.organization` from `SONARQUBE_ORG` in `~/.config/ffreis/secret.env` —
do not copy it from a sibling. Two values are live in the fleet (`felipefuhr`,
`ffreis-org`) and repos disagree. Add `.scannerwork/` to `.gitignore`.

**If sibling repos are missing this file, that is a finding to report, not a
licence to skip it.** Several website repos currently have none. Add it to the
repo being onboarded and report the others as a follow-up for another session.
Never conclude "the fleet doesn't do this, so we won't either."

**This generalises: level up, never down.** Whenever a reference repo turns out
to lack a standard, the standard still applies to the repo being onboarded, and
the reference's absence becomes a separate reported finding. A gap in the fleet
is a wider problem to fix, never a permission to propagate it.

## Step 5 — Report parity in BOTH directions

State where the new repo is behind the fleet **and where it is ahead**, and name
disagreements between references rather than silently picking one.

Real example: Editify was behind on unit tests, but ahead of 3 of 5 references on
lefthook (it had the pinned `remotes:` block) and was the most licence-compliant
of six repos. Meanwhile "the fleet standard" for lefthook had three different
implementations and coverage had three different philosophies. Reporting only the
deficit would have misled; copying "what the fleet does" would have copied a
policy violation.

Log every reference-repo violation found (an MIT licence on a product, a missing
`SECURITY.md` or `sonar-project.properties`) as a distinct follow-up finding.

## Step 6 — Inventory and deploy wiring

Only for sites built by the shared `ffreis-website-compiler`. Add
`inventory/<name>/<name>-dev.yaml` modelled on the closest existing entry, and
**merge it before wiring `deploy.yml`** — a workflow dispatching at a deployer
with no entry for it fails confusingly.

There is **no schema or validator** for inventory YAML: unknown keys are silently
tolerated and a typo silently takes the default. Re-read field names against the
deployer's actual parsing code, not against another entry.

If the product will have a dev deploy, adopt `develop` + a promote gate at
repo-creation time and set branch protection **then**. Forma deferred it and had
work bypass `develop` three times.

## Step 7 — Close out

Run `make ci` in every repo touched. Open every PR `--draft`. Verify with
`bash quality-kit/scripts/check-ci.sh <repo>` — never `gh pr checks`, which hides
`startup_failure` as PENDING. Update the spoke's `NEXT.md`.

Report end-to-end honestly: "done" means merged, deployed and live.
