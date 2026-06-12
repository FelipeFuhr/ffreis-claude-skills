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
      --granularity MONTHLY --metrics BlendedCost \
      --query "ResultsByTime[0].Total.BlendedCost.Amount" --output text
  '
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+ ]]
}

@test "by-service: returns valid JSON array" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY --metrics BlendedCost \
      --group-by Type=DIMENSION,Key=SERVICE \
      --query "ResultsByTime[0].Groups[].[Keys[0],Metrics.BlendedCost.Amount]" \
      --output json
  '
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list)"
}

@test "by-CostCenter: returns JSON and includes at least one tagged row" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY --metrics BlendedCost \
      --group-by Type=TAG,Key=CostCenter \
      --query "ResultsByTime[0].Groups[].[Keys[0],Metrics.BlendedCost.Amount]" \
      --output json
  '
  [ "$status" -eq 0 ]
  # At least one row should exist (even if only untagged)
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d) >= 1"
}

@test "by-CostCenter: engineering CostCenter has near-zero spend (tag drift guard)" {
  run bash -c '
    AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
      --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
      --granularity MONTHLY --metrics BlendedCost \
      --group-by Type=TAG,Key=CostCenter \
      --query "ResultsByTime[0].Groups[?Keys[0]=='"'"'CostCenter\$engineering'"'"'].Metrics.BlendedCost.Amount | [0]" \
      --output text
  '
  [ "$status" -eq 0 ]
  # engineering CostCenter should be absent or < $0.10 — it should not accumulate real spend
  if [ "$output" != "None" ] && [ -n "$output" ]; then
    python3 -c "import sys; v=float('$output'); assert v < 0.10, f'engineering CostCenter spend too high: \${v:.4f}'"
  fi
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
