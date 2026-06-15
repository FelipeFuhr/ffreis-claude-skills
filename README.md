# ffreis-claude-skills

<!-- ffreis-badges:start -->
[![CI](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-claude-skills/ci.json)](https://github.com/FelipeFuhr/ffreis-claude-skills/actions) [![License](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-claude-skills/license.json)](https://github.com/FelipeFuhr/ffreis-claude-skills/blob/main/LICENSE)
<!-- ffreis-badges:end -->

Reusable Claude Code slash commands (`/skill-name`) for the Felipe Fuhr
workspace. Skills are not code: each is a Markdown file with YAML frontmatter
that the Claude Code harness loads automatically. The canonical copies live
here; the `ffreis-claude-config` repo (the workspace `.claude/` directory)
syncs local copies from a pinned SHA, so skills are edited here and consumed
there by pinned reference.

## Skills

- `/aws-billing` — AWS billing dashboard: account-wide month-to-date spend,
  per-product `CostCenter` breakdown, forecast, and usage metrics for Bedrock,
  Lambda, CloudFront, and API Gateway. Runs Cost Explorer + CloudWatch queries
  in parallel via the `ffreis-platform` AWS profile.
- `/ci-findings` — Run the `ffreis-platform-ci-local` harness and format all
  findings, for a single repo or fleet-wide (`--all`, `--public`, `--private`).
  Supports act-only (default), act+sonar (`--sonar-local`), sonar-only
  (`--sonar-local-only`), or SonarCloud (`--sonar-cloud`). Surfaces SARIF
  findings grouped by lane and severity plus a remediation offer; skips
  CANNOT-RUN and UPLOAD-ONLY-FAILED noise.

## Layout

```
commands/   Claude Code skill files (*.md) — one per slash command
tests/      Bats tests: skill-structure (CI) + aws-billing-integration (local)
scripts/    lefthook bootstrap + git-hook helpers
.github/    CI workflows (ci, devops-automation, devops-security, etc.)
```

Each `commands/<name>.md` file has two mandatory frontmatter keys:

- `description:` — the one-line trigger description shown in the skills list.
- `allowed-tools:` — comma-separated `Bash(prefix *)` patterns pre-approved
  when the skill runs (e.g. `Bash(AWS_PROFILE=ffreis-platform aws ce *)`).

The frontmatter is followed by the skill body — the instructions Claude
follows when the command is invoked.

## How they're used

The Claude Code harness reads `commands/*.md` automatically when a session
starts inside a `.claude/` directory. Consumers do not reference this repo at
runtime directly: `ffreis-claude-config` keeps local copies of the skill files,
synced from this repo at a pinned SHA via `make sync-skills` there. CI in
`ffreis-claude-config` has a drift gate that fails if the local copies diverge
from the pinned SHA. Always edit a skill here, never in the config repo.

Adding a skill: create `commands/<name>.md` with the two frontmatter keys plus
a body, add structural tests to `tests/skill-structure.bats`, run `make ci`
(markdownlint + structural bats tests), and open a PR (CI also runs gitleaks).
After merge, `ffreis-claude-config` bumps its `SKILLS_SHA` and re-syncs.

Build and run:

```bash
make setup            # install lefthook git hooks + verify dev tools
make ci               # markdownlint + structural bats tests (no credentials)
make test-integration # live-AWS bats tests (requires ffreis-platform profile)
```

`tests/aws-billing-integration.bats` needs the `ffreis-platform` AWS profile
and is excluded from CI; run it locally with `make test-integration`.

## License

Proprietary — Copyright (c) 2026 Felipe Fuhr, All rights reserved. The source
is proprietary and confidential; viewing it on a public platform does not grant
any license to use, copy, modify, or distribute it.
