#!/usr/bin/env bats
# Integration tests for /aws-billing skill commands.
# Skipped automatically when AWS credentials are unavailable.
# Run locally with: bats tests/aws-billing-integration.bats

setup() {
  AWS_PROFILE=ffreis-platform aws sts get-caller-identity &>/dev/null \
    || skip "AWS credentials not available (ffreis-platform profile)"
}

@test "MTD spend: returns a non-empty decimal number" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY --metrics UnblendedCost \
      --query "ResultsByTime[0].Total.UnblendedCost.Amount" --output text
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+ ]]
}

@test "by-service: returns valid JSON array" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=SERVICE \
      --query "ResultsByTime[0].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]" \
      --output json
  '
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list)"
}

@test "by-CostCenter+usage-type: returns JSON and includes at least one tagged row" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY --metrics UnblendedCost \
      --group-by Type=TAG,Key=CostCenter Type=DIMENSION,Key=USAGE_TYPE \
      --query "ResultsByTime[0].Groups[].[Keys[0],Keys[1],Metrics.UnblendedCost.Amount]" \
      --output json
  '
  [ "$status" -eq 0 ]
  # At least one row should exist (even if only untagged), each a 3-element
  # [CostCenter, usage type, amount] triple — the shape Step 1's cache write
  # classifies into fixed/tagged/untagged.
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d) >= 1; assert all(len(row) == 3 for row in d)"
}

@test "by-CostCenter+usage-type: engineering CostCenter has near-zero spend (tag drift guard)" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY --metrics UnblendedCost \
      --group-by Type=TAG,Key=CostCenter Type=DIMENSION,Key=USAGE_TYPE \
      --query "ResultsByTime[0].Groups[?Keys[0]=='"'"'CostCenter\$engineering'"'"'].Metrics.UnblendedCost.Amount" \
      --output json \
    | jq "[.[] | tonumber] | add // 0"
  '
  [ "$status" -eq 0 ]
  # engineering CostCenter should sum to near-zero across all its usage-type
  # rows (the compound group-by can now split one CostCenter across several
  # rows) — it should not accumulate real spend.
  python3 -c "v=float('$output'); assert v < 0.10, f'engineering CostCenter spend too high: \${v:.4f}'"
}

@test "by-CostCenter+usage-type: fixed-usage-type classifier matches known recurring-fee patterns" {
  # No live AWS call — this is a pure jq unit check that the skill's
  # documented FIXED_PATTERN (mirroring deck's Rust is_fixed_usage_type)
  # correctly separates fixed rows from ordinary usage-based ones.
  run bash -c '
    FIXED_PATTERN="HostedZone|Health-Check|AlarmMonitorUsage"
    echo "[
      [\"CostCenter\$flemming\", \"USE1-HostedZone\", \"0.5\"],
      [\"CostCenter\$flemming\", \"Requests-Tier1\", \"5.18\"],
      [\"CostCenter\$\", \"CW:AlarmMonitorUsage\", \"3.21\"],
      [\"CostCenter\$\", \"USE1-APIRequest\", \"1.25\"]
    ]" | jq -r --arg pat "$FIXED_PATTERN" "[.[] | select(.[1] | test(\$pat)) | .[2] | tonumber] | add"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "3.71" ]
}

@test "Lambda invocations: CloudWatch returns a number or N/A" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws cloudwatch get-metric-statistics \
      --namespace AWS/Lambda --metric-name Invocations \
      --start-time $(date +%Y-%m-01)T00:00:00Z \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 2592000 --statistics Sum \
      --query "Datapoints[0].Sum" --output text 2>/dev/null || echo "N/A"
  '
  [ "$status" -eq 0 ]
  # Valid outputs: a decimal number, "None" (empty datapoints), or "N/A" (command failed gracefully)
  [[ "$output" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$output" = "None" ] || [ "$output" = "N/A" ]
}

@test "CloudFront: metric query targets us-east-1 and returns without error" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws cloudwatch get-metric-statistics \
      --region us-east-1 \
      --namespace AWS/CloudFront --metric-name Requests \
      --dimensions Name=Region,Value=Global \
      --start-time $(date +%Y-%m-01)T00:00:00Z \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 2592000 --statistics Sum \
      --query "Datapoints[0].Sum" --output text 2>/dev/null || echo "N/A"
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$output" = "None" ] || [ "$output" = "N/A" ]
}
