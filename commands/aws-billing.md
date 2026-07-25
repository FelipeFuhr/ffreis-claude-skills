---
description: AWS billing dashboard — account-wide spend, per-product CostCenter breakdown, forecast, and usage metrics (Bedrock, Lambda, CloudFront, API Gateway).
allowed-tools: Bash(AWS_PROFILE=ffreis-platform aws ce *), Bash(AWS_PROFILE=ffreis-platform aws cloudwatch *), Bash(AWS_PROFILE=ffreis-platform aws dynamodb *)
---

Fetch and report AWS billing and usage data for the current month.

## Step 1 — check the shared cost cache first

Every `aws ce` call costs $0.01 (see the workspace AGENTS.md "AWS Cost Explorer
caching — convention" section) — the fleet shares one hourly-refreshed
DynamoDB row so repeated `/aws-billing` runs (and the `deck` dashboard's cost
button) don't each pay for their own query.

```bash
AWS_PROFILE=ffreis-platform aws dynamodb get-item \
  --table-name ffreis-aws-cost-cache \
  --key '{"pk":{"S":"costcenter-snapshot"}}' \
  --output json
```

- **Cache hit** (an `Item` is present and its `generated_at`, `YYYY-MM-DDTHH:MM:SSZ`,
  is less than 1 hour old): use its `mtd`, `forecast`, and `untagged` fields
  and the `cost_center_breakdown` field (a JSON string — parse it, an array of
  `{"name":..., "usd":...}`, already sorted largest-first, untagged excluded)
  directly for the **Spend** and **By product** sections below. Skip queries
  A, C, and E entirely — go straight to Step 2 for B and D (not cached, since
  they aren't shared with any other consumer) and Step 3.
- **Cache miss** (row missing, unreadable, or `generated_at` ≥ 1 hour old): run
  A, C, E as a live fetch in Step 2, then write the result back so the *next*
  reader — another `/aws-billing` run, or the `deck` dashboard button — gets a
  hit:

  ```bash
  AWS_PROFILE=ffreis-platform aws dynamodb put-item \
    --table-name ffreis-aws-cost-cache \
    --item '{
      "pk": {"S": "costcenter-snapshot"},
      "generated_at": {"S": "<now, date -u +%Y-%m-%dT%H:%M:%SZ>"},
      "mtd": {"N": "<A result>"},
      "forecast": {"N": "<A + C results, MTD + remaining forecast — the cache stores the TOTAL, not just the remaining delta>"},
      "untagged": {"N": "<E'"'"'s untagged group amount>"},
      "cost_center_breakdown": {"S": "<E'"'"'s named groups as a JSON string, e.g. [{\"name\":\"flemming\",\"usd\":5.68}]>"}
    }'
  ```

  Build `cost_center_breakdown`/`untagged` from E's raw output with `jq`,
  splitting each `Keys[0]` on its first `$` exactly like `deck`'s Rust parser
  does (an empty value after `$` is the untagged bucket, tracked separately —
  never one of the named groups):
  ```bash
  # $E_RAW is E's --output json array of [tagValue, amount] pairs.
  BREAKDOWN=$(echo "$E_RAW" | jq -c '[.[] | {name: (.[0] | split("$")[1]), usd: (.[1] | tonumber * 100 | round / 100)} | select(.name != "")] | sort_by(-.usd)')
  UNTAGGED=$(echo "$E_RAW" | jq -r '([.[] | select((.[0] | split("$")[1]) == "") | .[1] | tonumber] | add // 0) * 100 | round / 100')
  ```
  A failed `put-item` (e.g. table unreachable) is not an error — just skip it
  and report normally; the next reader will simply pay for its own live fetch.

## Step 2 — cost queries (only the ones the cache didn't cover)

**A. Account-wide MTD** *(skip on a cache hit)*:
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost \
  --query 'ResultsByTime[0].Total.UnblendedCost.Amount' --output text
```

**B. Last month total** *(always run — not part of the shared cache)*:
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date -d "$(date +%Y-%m-01) -1 month" +%Y-%m-01),End=$(date +%Y-%m-01) \
  --granularity MONTHLY --metrics UnblendedCost \
  --query 'ResultsByTime[0].Total.UnblendedCost.Amount' --output text
```

**C. MTD forecast** *(skip on a cache hit; skip gracefully if today is month-end)*:
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-forecast \
  --time-period Start=$(date +%Y-%m-%d),End=$(date -d "$(date +%Y-%m-01) +1 month" +%Y-%m-%d) \
  --metric UNBLENDED_COST --granularity MONTHLY \
  --query 'Total.Amount' --output text 2>/dev/null || echo "N/A"
```

**D. MTD by service (top 12)** *(always run — not part of the shared cache)*:
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'sort_by(ResultsByTime[0].Groups, &Metrics.UnblendedCost.Amount)[-12:].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output json
```

**E. MTD by CostCenter tag (per-product)** *(skip on a cache hit)*:
```bash
AWS_PROFILE=ffreis-platform aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=TAG,Key=CostCenter \
  --query 'sort_by(ResultsByTime[0].Groups, &Metrics.UnblendedCost.Amount)[].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output json
```

## Step 3 — run usage metric queries in parallel

Time window: start of current month to now. Use period=2592000 (30 days) to get a single data point. These are free-tier CloudWatch metric calls, not Cost Explorer — nothing here is cached or needs to be.

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

## Step 4 — format the report

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
- Cost Explorer charges > $1 → may indicate the shared cache isn't being hit (check whether Step 1 actually found a fresh row) or a consumer elsewhere is bypassing it
- Any product CostCenter with untagged resources draining into "(untagged)" → tag drift
- Forecast significantly above last month → note the delta and the top driver service
- Bedrock invocations > 0 while ai-ask CostCenter spend is near zero → cross-check (invocations may be on a different account/region)
