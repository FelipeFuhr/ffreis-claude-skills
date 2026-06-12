#!/usr/bin/env bats
# Structural tests for .claude/commands/*.md skill files.
# Validates frontmatter and body without requiring live credentials or Docker.

COMMANDS_DIR="$BATS_TEST_DIRNAME/../commands"

# ── helper ─────────────────────────────────────────────────────────────────

# Extract the YAML frontmatter block (between the two --- lines).
frontmatter() {
  awk '/^---$/{p++; if(p==2) exit} p==1 && !/^---$/{print}' "$1"
}

# ── aws-billing ─────────────────────────────────────────────────────────────

@test "aws-billing: file exists" {
  [ -f "$COMMANDS_DIR/aws-billing.md" ]
}

@test "aws-billing: has non-empty description in frontmatter" {
  val=$(frontmatter "$COMMANDS_DIR/aws-billing.md" | grep '^description:' | sed 's/^description: *//')
  [ -n "$val" ]
}

@test "aws-billing: has non-empty allowed-tools in frontmatter" {
  val=$(frontmatter "$COMMANDS_DIR/aws-billing.md" | grep '^allowed-tools:' | sed 's/^allowed-tools: *//')
  [ -n "$val" ]
}

@test "aws-billing: allowed-tools contains aws ce entry" {
  grep -q 'aws ce' "$COMMANDS_DIR/aws-billing.md"
}

@test "aws-billing: allowed-tools contains cloudwatch entry" {
  grep -q 'cloudwatch' "$COMMANDS_DIR/aws-billing.md"
}

@test "aws-billing: CloudFront query targets us-east-1" {
  grep -A5 'CloudFront requests' "$COMMANDS_DIR/aws-billing.md" | grep -q 'us-east-1'
}

@test "aws-billing: body has at least 3 numbered steps" {
  count=$(grep -c '^## Step' "$COMMANDS_DIR/aws-billing.md")
  [ "$count" -ge 3 ]
}

# ── ci-findings ──────────────────────────────────────────────────────────────

@test "ci-findings: file exists" {
  [ -f "$COMMANDS_DIR/ci-findings.md" ]
}

@test "ci-findings: has non-empty description in frontmatter" {
  val=$(frontmatter "$COMMANDS_DIR/ci-findings.md" | grep '^description:' | sed 's/^description: *//')
  [ -n "$val" ]
}

@test "ci-findings: has non-empty allowed-tools in frontmatter" {
  val=$(frontmatter "$COMMANDS_DIR/ci-findings.md" | grep '^allowed-tools:' | sed 's/^allowed-tools: *//')
  [ -n "$val" ]
}

@test "ci-findings: allowed-tools contains make ci-local" {
  grep -q 'make ci-local' "$COMMANDS_DIR/ci-findings.md"
}

@test "ci-findings: allowed-tools contains check-workspace-state" {
  grep -q 'check-workspace-state' "$COMMANDS_DIR/ci-findings.md"
}

@test "ci-findings: documents all job classifier statuses" {
  for status in PASS FOUND-FINDINGS UPLOAD-ONLY-FAILED REAL-FAIL CANNOT-RUN; do
    grep -q "$status" "$COMMANDS_DIR/ci-findings.md" \
      || { echo "missing status: $status"; return 1; }
  done
}

@test "ci-findings: scope table covers --all --public --private" {
  for flag in '--all' '--public' '--private'; do
    grep -qF -- "$flag" "$COMMANDS_DIR/ci-findings.md" \
      || { echo "missing flag: $flag"; return 1; }
  done
}

@test "ci-findings: remediation offer is present" {
  grep -q '\-\-remediate' "$COMMANDS_DIR/ci-findings.md"
}

@test "ci-findings: lane flag table covers --sonar-local --sonar-local-only --sonar-cloud" {
  for flag in '--sonar-local' '--sonar-local-only' '--sonar-cloud'; do
    grep -qF -- "$flag" "$COMMANDS_DIR/ci-findings.md" \
      || { echo "missing lane flag: $flag"; return 1; }
  done
}

@test "ci-findings: maps --sonar to --full harness flag" {
  grep -q '\-\-full' "$COMMANDS_DIR/ci-findings.md"
}

@test "ci-findings: maps --sonar-only to --lane-b-only harness flag" {
  grep -q '\-\-lane-b-only' "$COMMANDS_DIR/ci-findings.md"
}

@test "ci-findings: documents SonarQube container first-boot time" {
  grep -q '4\.5 min' "$COMMANDS_DIR/ci-findings.md"
}

@test "ci-findings: documents sequential-not-parallel constraint for fleet+sonar" {
  grep -q 'sequentially' "$COMMANDS_DIR/ci-findings.md"
}

@test "ci-findings: report format distinguishes Lane A vs Lane B" {
  grep -q 'LANE A' "$COMMANDS_DIR/ci-findings.md" && grep -q 'LANE B' "$COMMANDS_DIR/ci-findings.md"
}

# ── cross-skill ───────────────────────────────────────────────────────────────

@test "all commands: no skill file has empty frontmatter block" {
  for f in "$COMMANDS_DIR"/*.md; do
    block=$(frontmatter "$f")
    [ -n "$block" ] || { echo "empty frontmatter: $f"; return 1; }
  done
}
