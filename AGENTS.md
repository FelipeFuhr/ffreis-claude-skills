# Agent Context

**This repo:** `ffreis-claude-skills` — Reusable Claude Code slash commands (`/skill-name`)
for the Felipe Fuhr workspace. Skills live in `commands/*.md`; callers reference them
at a pinned SHA via `make sync-skills` in `ffreis-claude-config`.

## Non-obvious facts

- **Skills are `.md` files with YAML frontmatter**, not code. The Claude Code harness
  reads `commands/*.md` automatically when the session starts inside `.claude/`.
- **Frontmatter contract** (every skill must have both):
  - `description:` — one-line trigger description shown in the skills list
  - `allowed-tools:` — comma-separated `Bash(prefix *)` patterns pre-approved for this skill
- **Consumer pattern:** `ffreis-claude-config` keeps local copies of `commands/*.md`,
  synced from this repo at a pinned SHA. Edit skills here, not in the config repo.
  CI in `ffreis-claude-config` has a drift gate that fails if local copies diverge from
  the pinned SHA.
- **Structural tests** in `tests/skill-structure.bats` run in CI (no credentials).
  `tests/aws-billing-integration.bats` requires the `ffreis-platform` AWS profile and
  is excluded from CI — run locally with `make test-integration`.

## Adding a new skill

1. Create `commands/<name>.md` with YAML frontmatter (`description:`, `allowed-tools:`)
   followed by the skill body (what Claude should do when invoked).
2. Add structural tests to `tests/skill-structure.bats` — at minimum: file exists,
   description non-empty, allowed-tools non-empty, key invariants in the body.
3. Validate: `make ci`
4. Open a PR — CI runs markdownlint + structural tests + gitleaks.
5. After merge, `ffreis-claude-config` bumps `SKILLS_SHA` + runs `make sync-skills`.

## Skills in this repo

| Skill | Description |
|---|---|
| `/aws-billing` | AWS billing dashboard — MTD spend, per-product CostCenter breakdown, forecast, usage metrics |
| `/ci-findings` | Run the ci-local harness and format findings — single repo or fleet-wide |

## Structure

```
commands/       Claude Code skill files (*.md)
tests/          Bats tests for skill structure and integration
```

## Build and run

```bash
make setup            # install lefthook git hooks
make ci               # lint + structural tests
make test-integration # live AWS tests (needs ffreis-platform profile)
```

## Keeping this file current

- When a new skill is added, update the skills table and add tests to `skill-structure.bats`.
- If you discover a non-obvious constraint, add it to "Non-obvious facts".
