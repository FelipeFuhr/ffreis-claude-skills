---
description: LLM-as-judge check of whether a target artifact (a doc, page, or codebase) is in sync with a source of truth (a spec, roadmap, or feature implementation) — read-only, advisory, never edits either side.
allowed-tools: Bash(git log *), Bash(git diff *)
---

Compare a **target artifact** against a **source of truth** and report whether they
are in sync. You (the invoking agent) are the judge — no external LLM API call is
made; this skill exists because you already are the reasoning engine the pattern
needs. See "Future automation" at the end for the unattended-CI version of this
same idea.

**Directionality matters.** The *source* is authoritative — the spec, the roadmap,
the code that actually implements a feature. The *target* is the artifact being
checked for compliance with that truth — a legal page, a marketing page, a doc,
a changelog. Getting this backwards flips the meaning of every discrepancy: a
"missing" finding means the target failed to disclose something the source does;
reversed, it would wrongly mean the source failed to implement something the
target promised.

## Step 1 — identify source and target from $ARGUMENTS

| Reference | Accepted forms |
| --- | --- |
| **Source** (ground truth) | a doc file/dir path, a glob, one or more code paths that implement the feature, a git ref (`<repo>@<sha>:<path>`), a URL (fetched via WebFetch) |
| **Target** (artifact under check) | a doc file/dir path, a rendered page URL (fetched via WebFetch), a set of files |

If `$ARGUMENTS` gives only one reference, or the source/target roles are
ambiguous, ask which is which rather than guessing — do not silently pick a
direction.

## Step 2 — read both completely

- Read **every** file in scope end-to-end. For a directory or glob, read each
  matched file individually — do not sample or skim.
- When the source is code, read the actual logic (request handlers, form fields,
  database writes, third-party SDK calls, feature flags) — not just filenames,
  comments, or docstrings. Comments and code drift too.
- When either side is a live URL, fetch the rendered page with WebFetch rather
  than assuming a locally checked-out template matches what is actually served.
- Note the retrieval point for each side in the report — a commit SHA for a repo
  path, a fetch timestamp for a URL. Staleness is itself a finding: a doc read at
  `HEAD` and a page fetched live may reflect two different moments if the deploy
  pipeline lags the repo (use `git log -1 --format=%cI -- <path>` to date a file
  if useful).

## Step 3 — extract claims, extract facts, match them, form the verdict

**From the target**, walk it section by section. Every sentence that asserts a
fact about data handled, a feature offered, a price, a right granted, a limit
imposed, an integration used, etc. is a candidate **claim**. Quote it verbatim
with a file + line/section anchor.

**From the source**, do the same. For a doc, its own assertions are the
**facts**. For code, every mechanism that touches the same subject matter (an
input field, a DB write, a third-party API call, a price computation, a feature
gate) is a candidate fact. Cite file + line/function.

**Match every claim to the fact(s) it should correspond to.** Each pairing lands
in one of four buckets (silence is only ever a discrepancy in one of these
buckets — most claims should simply be covered):

| Kind | Meaning |
| --- | --- |
| `missing` | The source does something real that the target is silent on, and the target's role would reasonably be expected to disclose it (a privacy page silent on a live data-collection mechanism; a pricing page silent on a real fee). Use judgment for what "reasonably expected" means for this pair — a roadmap vs. a marketing page usually shouldn't restate every internal implementation detail; say so in the rationale when you deliberately don't flag something for this reason. |
| `overstated` | The target claims something the source does not support — a feature, guarantee, or scope that doesn't exist in the implementation. |
| `conflicting` | Both sides address the same point but disagree (different numbers, different scope, contradictory statements). |
| `stale` | The target refers to something the source shows has since changed or been removed. |

**Verdict shape** — mirrors `claude_judge.py`'s `Verdict` (argue, *then* conclude,
*then* summarize — field order there exists so the model commits to reasoning
before a number; the same discipline applies here before a status):

| Field | Mirrors `Verdict` | Content |
| --- | --- | --- |
| `rationale` | `rationale` | 2-4 sentences walking the specific comparisons that drove the call — name concrete claims/facts, not a vibe. |
| `status` | `score` (categorical here, not `[0,1]`) | One of `in-sync`, `partial`, `out-of-sync`. |
| `severity` | *(new — a doc-consistency finding can carry legal/compliance weight a game-concept score never did)* | `none`\|`low`\|`medium`\|`high`\|`critical`, overall = the max across `discrepancies[]`. |
| `comment` | `comment` | One sentence a human can skim first. |
| `discrepancies[]` | *(new — a doc diff is inherently multi-item; the judge's per-lens comment was deliberately singular, this isn't)* | See below. |

Each `discrepancies[]` entry:

- `kind` — one of the four buckets above
- `severity` — `none`\|`low`\|`medium`\|`high`\|`critical` for this item alone
- `target_claim` — verbatim quote + file:line/section, or `(absent)` for `missing`
- `source_fact` — verbatim quote/description + file:line/function, or `(absent)` for `overstated`

## Step 4 — format the report

---

**Consistency Judge — `<target>` vs `<source>`**
*(source read @ `<sha or timestamp>`, target read @ `<sha or timestamp>`)*

**Verdict: IN-SYNC | PARTIAL | OUT-OF-SYNC**  (severity: NONE | LOW | MEDIUM | HIGH | CRITICAL)

**Rationale**
2-4 sentences.

**Discrepancies** (omit entirely if none)

| # | Kind | Severity | Target claim | Source fact |
|---|---|---|---|---|
| 1 | missing | high | `privacy.md:42` — "we collect only X" | `checkout.py:88` — also writes `phone_number` to the order record |

Below the table, give each row's full citation (both quotes in full, not
truncated) so a human can jump straight to the lines in question.

**Comment**
One sentence.

---

## This is advisory — it never edits anything

This skill's `allowed-tools` deliberately grants no `Edit`/`Write`/`MultiEdit`
access to the target or source. Its only output is the report above. Discrepancy
findings are for a human to review and act on — do not open a PR, do not patch
the target artifact, and do not treat a "confident" verdict as license to fix it
yourself. If asked to also fix what you found, treat that as a distinct,
separate task the human must explicitly request.

## Worked examples

### Example 1 — the motivating case: legal pages vs. implemented data practices

```text
/consistency-judge source=ffreis-website+ffreis-urbs (code) target=ffreis-website-data/data/en/site.d/60-pages.yaml (privacy/cookies/terms)
```

Source facts actually found in this workspace: `ffreis-website/src/assets/js/analytics.js`
sets a 4-hour `analytics_session_id` cookie, tracks scroll depth, and tracks
form-start events by field *identifier* only (`trackFormStart`, line ~179); an
`ab_variant` cookie is read for A/B bucketing. The target's `cookies` entry
describes exactly this (4-hour analytics session, A/B variant, "never what you
typed into it") — that pairing is **covered**, not a discrepancy.

Now widen the source to `ffreis-urbs/src/templates/pages/checkout.gohtml`: its
checkout form collects `email` and `full name` client-side (both `required`
inputs) as part of a course-purchase flow. `ffreis-website-data`'s privacy page
only discusses `ffreis.com`'s own contact form, cookies, and reCAPTCHA — it says
nothing about a checkout flow collecting contact details for a purchase. That is
a real `missing` candidate: the source (urbs' checkout template) does something
the target (the shared legal pages) is silent on. Report it as `missing`,
severity depends on whether urbs is covered by the same legal pages in practice
or has (or needs) its own — flag that ambiguity explicitly in the rationale
rather than guessing.

### Example 2 — a doc claim vs. actual fleet wiring

```text
/consistency-judge source=quality-kit/scripts/pr-ready.sh + the repos it targets target=AGENTS.md's "Draft-first PRs & GitHub Actions CI" section
```

The doc claims `/ready` promotes a draft PR and fires full CI. The workspace's
own tracked history already surfaced a real case of exactly this drift: roughly
28 repos' `ready_for_review` trigger wasn't wired the way the doc assumes, so
promotion silently didn't fire CI on those repos (see auto-memory
`feedback_ready_for_review_unwired_policy`). That is a textbook `stale`/`conflicting`
finding — the doc's claim was accurate for most of the fleet but not all of it —
and it is exactly the shape of gap this skill exists to surface before someone
trusts a green promotion that never actually ran.

### Example 3 — a business-model doc vs. entitlement code

```text
/consistency-judge source=<checkout/entitlement Lambda + section-gate registry code> target=<course page copy in ffreis-website-data, e.g. "lifetime access", "N modules">
```

If the course page copy promises "lifetime access" but the entitlement grant in
the checkout Lambda writes a time-boxed record (or the section-gate registry
enforces a renewal), that is a `conflicting` finding at `high` or `critical`
severity — it's a paying customer being told something the system doesn't
enforce. Conversely, if the entitlement logic grants access to a bonus module
the page copy never lists, that's a (harmless, low-severity) `missing` — the
product is more generous than advertised, not less, but still worth a maintainer
knowing the copy is out of date.

## Future automation

`ffreis-foundry-recombinator/src/foundry_recombinator/claude_judge.py` (and its
sibling `claude_scorer.py`) already implement this same argue-then-score
structured-output pattern as a **standalone, API-calling** `Judge`/`Scorer` —
built for a different use case (game-concept panel scoring), dormant because no
`ANTHROPIC_API_KEY` was available when it was written, but the shape (a
Pydantic `Verdict`, a prompt-assembly function, an injectable `complete`/`llm`
seam for offline testing) is directly reusable for this domain: swap the
per-lens system prompts for a doc-consistency system prompt, swap `Verdict`'s
`score: float` for this skill's `status`/`severity`/`discrepancies[]` shape, and
the same three-seam contract (`complete` | `llm` | direct Anthropic) applies.

That standalone pattern could back an **unattended CI gate** — triggered on a
legal-page change, a pricing-copy change, or a feature-flag change, running the
judge headlessly and failing the check (or opening an issue) on `out-of-sync`.
This skill is deliberately the **interactive, on-demand** version of that same
idea: no API key is provisioned in CI, and the cost/frequency tradeoff of a
per-PR LLM call hasn't been decided. Building the CI gate is future work, not
part of this skill — it needs: (1) an `ANTHROPIC_API_KEY` in the target repo's
CI secrets, (2) a decision on trigger scope (path filters on legal/pricing/flag
files, not every PR), and (3) a decision on failure mode (block merge vs.
comment-only, given false positives are more likely from an unattended pass
than from an interactive session that can ask a clarifying question first).
