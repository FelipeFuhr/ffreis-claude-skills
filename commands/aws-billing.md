---
description: AWS billing dashboard — account-wide spend, per-product CostCenter breakdown, forecast, and usage metrics (Bedrock, Lambda, CloudFront, API Gateway).
allowed-tools: Bash(AWS_PROFILE=ffreis-platform aws ce *), Bash(AWS_PROFILE=ffreis-platform aws cloudwatch *)
---

Fetch and report AWS billing and usage data for the current month.

## Step 1 — run all cost queries in parallel

Run these simultaneously (they are independent):

**A. Account-wide MTD:**
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text
```

**B. Last month total:**
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date -d "$(date +%Y-%m-01) -1 month" +%Y-%m-01),End=$(date +%Y-%m-01) \
  --granularity MONTHLY --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' --output text
```

**C. MTD forecast (skip gracefully if today is month-end):**
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-forecast \
  --time-period Start=$(date +%Y-%m-%d),End=$(date -d "$(date +%Y-%m-01) +1 month" +%Y-%m-%d) \
  --metric BLENDED_COST --granularity MONTHLY \
  --query 'Total.Amount' --output text 2>/dev/null || echo "N/A"
```

**D. MTD by service (top 12):**
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'sort_by(ResultsByTime[0].Groups, &Metrics.BlendedCost.Amount)[-12:].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output json
```

**E. MTD by CostCenter tag (per-product):**
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics BlendedCost \
  --group-by Type=TAG,Key=CostCenter \
  --query 'sort_by(ResultsByTime[0].Groups, &Metrics.BlendedCost.Amount)[].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output json
```

## Step 2 — run usage metric queries in parallel

Time window: start of current month to now. Use period=2592000 (30 days) to get a single data point.

**F. Bedrock invocations (model inference calls):**
```bash
AWS_PROFILE=ffreis-platform aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name Invocations \
  --start-time $(date +%Y-%m-01)T00:00:00Z \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 2592000 --statistics Sum \
  --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "N/A"
```

**G. Lambda invocations (fleet total):**
```bash
AWS_PROFILE=ffreis-platform aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --start-time $(date +%Y-%m-01)T00:00:00Z \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 2592000 --statistics Sum \
  --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "N/A"
```

**H. CloudFront requests (fleet total):**
CloudFront metrics are only published to `us-east-1`.
```bash
AWS_PROFILE=ffreis-platform aws cloudwatch get-metric-statistics \
  --region us-east-1 \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=Region,Value=Global \
  --start-time $(date +%Y-%m-01)T00:00:00Z \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 2592000 --statistics Sum \
  --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "N/A"
```

**I. API Gateway requests (fleet total):**
```bash
AWS_PROFILE=ffreis-platform aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --start-time $(date +%Y-%m-01)T00:00:00Z \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 2592000 --statistics Sum \
  --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "N/A"
```

## Step 3 — format the report

AWS CLI outputs `None` (not `N/A`) when a CloudWatch query returns zero datapoints — treat `None` as 0 in the report.

Present the results as:

---

**AWS Dashboard — [Month Year] ([N] days in)**

**Spend**
| | Amount |
|---|---|
| Month-to-date | $X.XX |
| Forecast (EOM) | $X.XX |
| Last month | $X.XX |

**By product (CostCenter tag)**
| Product | MTD |
|---|---|
| petlook | $X.XX |
| flemming | $X.XX |
| ffreis-website | $X.XX |
| platform | $X.XX |
| dashboard | $X.XX |
| ai-ask | $X.XX |
| (untagged) | $X.XX |

**Top services**
Omit rows under $0.01. Sort descending.

**Usage**
| Metric | MTD |
|---|---|
| Bedrock invocations | N |
| Lambda invocations | N |
| CloudFront requests | N |
| API Gateway requests | N |

---

**Flags to call out:**
- Cost Explorer charges > $1 → may indicate dashboard widget cache cadence is too short ($0.01/req)
- Any product CostCenter with untagged resources draining into "(untagged)" → tag drift
- Forecast significantly above last month → note the delta and the top driver service
- Bedrock invocations > 0 while ai-ask CostCenter spend is near zero → cross-check (invocations may be on a different account/region)
