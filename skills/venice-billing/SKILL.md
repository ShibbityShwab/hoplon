---
name: venice-billing
description: Venice billing and usage analytics - GET /billing/balance, GET /billing/usage-history (keyset-paginated per-request ledger, JSON or CSV), GET /billing/usage (deprecated predecessor), and GET /billing/usage-analytics (aggregated by date/model/key). Covers the DIEM/USD/BUNDLED_CREDITS consumption priority and building dashboards. (Beta)
---

# Venice Billing

Four read-only endpoints for account-level billing and analytics. All are under a **Beta** tag — schema/behavior may change.

| Endpoint | Purpose |
|---|---|
| `GET /billing/balance` | Current `canConsume` flag, remaining DIEM & USD, epoch allocation. |
| `GET /billing/usage-history` | Per-request ledger with keyset pagination. JSON or CSV. **Use this one.** |
| `GET /billing/usage` | **Deprecated** offset-paginated ledger. See the warning below. |
| `GET /billing/usage-analytics` | Aggregated breakdowns: by date, model, API key. |

All require Bearer auth (not x402 — for wallet balances, use [`venice-x402`](../venice-x402/SKILL.md)). `GET /billing/balance`, `GET /billing/usage-history`, and `GET /billing/usage` require an **ADMIN** key — an `INFERENCE` key gets `401`. `GET /billing/usage-analytics` works on any authenticated key (scoped to the account behind the key).

> **`GET /billing/usage` is deprecated and mostly closed.** It is rate limited to
> **1 request per minute per user**, and accounts created on or after
> **2026-07-07** are rejected outright with `410 Gone`. Every response carries
> `Deprecation: @1783555200` and
> `Link: </api/v1/billing/usage-history>; rel="successor-version"`. Write new
> integrations against `GET /billing/usage-history`, which returns the same data
> with keyset pagination.

## Currency / priority

Venice debits from, in order:

1. **`DIEM`** — staked credits (reset per epoch).
2. **`BUNDLED_CREDITS`** — included in some Pro plans.
3. **`USD`** — prepaid fiat balance.
4. (`VCU`) — **deprecated** legacy DIEM.

`consumptionCurrency` on `/billing/balance` reports the **current** currency being consumed.

## `GET /billing/balance`

```bash
curl https://api.venice.ai/api/v1/billing/balance \
  -H "Authorization: Bearer $VENICE_API_KEY"
```

```json
{
  "canConsume": true,
  "consumptionCurrency": "DIEM",
  "balances": { "diem": 90.5, "usd": 25 },
  "diemEpochAllocation": 100
}
```

- `canConsume: false` means both DIEM and USD buckets are empty on this endpoint — `canConsume` here is `hasPositiveDiemBalance || usdBalance > 0` and does **not** factor in bundled credits (which are consulted during the actual request in `getConsumableBalanceForRequest`).
- `consumptionCurrency` is `"DIEM"`, `"USD"`, or `null` (when neither applies).
- `balances.diem` is `null` if not staking.
- `diemEpochAllocation` is the ceiling for the current epoch — `balances.diem / diemEpochAllocation` = remaining fraction.

## `GET /billing/usage-history`

Per-request ledger with keyset (cursor) pagination. This is the supported way to
walk billing history.

```bash
curl "https://api.venice.ai/api/v1/billing/usage-history?startTimestamp=2026-06-01T00:00:00Z&endTimestamp=2026-07-01T00:00:00Z&pageSize=1000&currency=USD" \
  -H "Authorization: Bearer $VENICE_ADMIN_KEY" \
  -H "Accept: application/json"
```

### Query parameters

A request is **either** a filtered first page **or** a bare continuation. Sending
`cursor` alongside any filter is a `400`, and so is any unknown parameter — the
validator is strict rather than lenient.

| Param | Notes |
|---|---|
| `startTimestamp` | Inclusive lower bound, ISO 8601 UTC with a `Z` suffix. First page only. |
| `endTimestamp` | Exclusive upper bound, ISO 8601 UTC. Must be later than `startTimestamp`. Consecutive windows that share a boundary walk the history with no gaps and no overlaps. |
| `currency` | `USD` / `DIEM` / `BUNDLED_CREDITS`. |
| `pageSize` | 10–1000. Default **1000**. |
| `cursor` | Opaque continuation token from a previous `nextCursor`. Carries the filters of the walk it continues, so send it **alone**. |

### Response (JSON)

```json
{
  "data": [
    {
      "timestamp": "2026-06-15T19:05:10.504Z",
      "sku": "zai-org-glm-5-1-llm-output-mtoken",
      "units": 0.000227,
      "pricePerUnitUsd": 2.8,
      "amount": -0.06356,
      "currency": "DIEM",
      "notes": "API Inference",
      "inferenceDetails": {
        "requestId": "chatcmpl-4007fd29f42b7d3c4107f4345e8d174a",
        "promptTokens": 339,
        "completionTokens": 227,
        "inferenceExecutionTime": 2964
      }
    }
  ],
  "nextCursor": "AZq3fK9tXhIVDm2j4vN8cQwYt1sB6uEoLxRgPzKaJdHfM5nC7yW0K3w"
}
```

Entries come back in **ascending** timestamp order. `nextCursor` is `null` on the
last page. Set `Accept: text/csv` for CSV, in which case `Content-Disposition`
stamps the export time into the filename (each page of a walk downloads under a
unique, sort-ordered name) and `nextCursor` moves to the `x-next-cursor`
response header.

Entry fields match `/billing/usage` (see below), with `inferenceDetails`
sub-fields nullable when a count or timing was not recorded.

### Walking the full history

```ts
let url = `${base}/billing/usage-history?startTimestamp=${start}&endTimestamp=${end}`
for (;;) {
  const page = await fetch(url, { headers }).then(r => r.json())
  handle(page.data)
  if (page.nextCursor === null) break
  url = `${base}/billing/usage-history?cursor=${encodeURIComponent(page.nextCursor)}`
}
```

## `GET /billing/usage` (deprecated)

Offset-paginated per-request ledger. Kept alive for grandfathered accounts only;
see the deprecation warning at the top of this skill before using it.

```bash
curl "https://api.venice.ai/api/v1/billing/usage?limit=200&page=1&sortOrder=desc&currency=USD&startDate=2026-04-01T00:00:00Z&endDate=2026-04-21T23:59:59Z" \
  -H "Authorization: Bearer $VENICE_API_KEY" \
  -H "Accept: application/json"
```

### Query parameters

| Param | Notes |
|---|---|
| `currency` | `USD` / `VCU` / `DIEM` / `BUNDLED_CREDITS`. |
| `startDate` / `endDate` | ISO 8601 datetime. |
| `limit` | 1–500. Default 200. |
| `page` | Default 1. |
| `sortOrder` | `asc` / `desc` on `createdAt`. Default `desc`. |

### Accept header

- `application/json` (default) — paginated JSON.
- `text/csv` — downloads `billing-usage.csv` (sets `Content-Disposition`).

### Response (JSON)

```json
{
  "warningMessage": "DIEM (formerly VCU) has been renamed...",
  "data": [
    {
      "timestamp": "2026-04-20T12:34:56Z",
      "sku": "zai-org-glm-5-1-llm-output-mtoken",
      "units": 0.000227,
      "pricePerUnitUsd": 2.8,
      "amount": -0.06356,
      "currency": "DIEM",
      "notes": "API Inference",
      "inferenceDetails": {
        "requestId": "chatcmpl-...",
        "promptTokens": 339,
        "completionTokens": 227,
        "inferenceExecutionTime": 2964
      }
    }
  ],
  "pagination": { "limit": 200, "page": 1, "total": 1000, "totalPages": 5 }
}
```

Response headers: `x-pagination-{limit,page,total,total-pages}`.

### Fields

- `sku` — billing line item (model + unit type + format).
- `units` — for LLMs, millions of tokens (e.g. `0.000227` = 227 tokens).
- `pricePerUnitUsd` — rate; for DIEM, DIEM ≈ USD so this doubles as reference.
- `amount` — negative for debit.
- `inferenceDetails` — present for inference SKUs; `requestId` is the `id` returned on the original `/chat/completions` response.

## `GET /billing/usage-analytics`

Aggregated summary for dashboards. **Cached 10 minutes.**

```bash
curl "https://api.venice.ai/api/v1/billing/usage-analytics?lookback=7d" \
  -H "Authorization: Bearer $VENICE_API_KEY"
```

### Query parameters (choose one approach)

- `lookback=Nd` — `7d`, `30d`, up to `90d`. Default `7d`.
- **OR** `startDate=YYYY-MM-DD` + `endDate=YYYY-MM-DD` — both required if either is given.

### Response (selected keys)

```json
{
  "lookback": "7d",
  "byDate": [{ "date": "2026-04-20", "USD": 0.5, "DIEM": 10.25 }, ...],
  "byModel": [
    {
      "modelName": "GLM 5.1",
      "unitType": "tokens",
      "modelType": "LLM",
      "totalUsd": 0.4,
      "totalDiem": 12.5,
      "totalUnits": 50000,
      "breakdown": [
        { "type": "Output", "usd": 0.3, "diem": 10, "units": 35000 },
        { "type": "Input",  "usd": 0.1, "diem": 2.5, "units": 15000 }
      ]
    }
  ],
  "byModelDaily": [
    { "date": 1705276800000, "GLM 5.1": 5.5, "Claude Opus 4.7": 3.2 }
  ],
  "byModelDailyUsd": [...],
  "topModels": ["GLM 5.1", "Claude Opus 4.7"],
  "byKey": [
    { "apiKeyId": "key_abc123", "description": "Production Key",
      "totalUsd": 0.8, "totalDiem": 15, "totalUnits": 75000 },
    { "apiKeyId": null, "description": "Web App",
      "totalUsd": 0, "totalDiem": 4, "totalUnits": 25000 }
  ],
  "byKeyDaily": [...],
  "byKeyDailyUsd": [...],
  "topKeyNames": [...]
}
```

- `byDate` / `byModelDaily` / `byKeyDaily` are pre-shaped for time-series charts.
- `topModels` / `topKeyNames` give top-8 names for legend rendering.
- `apiKeyId: null` in `byKey` means the usage originated from Venice's web app.

## Recipes

### Abort before calling inference if balance is empty

```ts
const { canConsume } = await fetch(`${base}/billing/balance`, { headers }).then(r => r.json())
if (!canConsume) throw new Error('Venice balance exhausted — top up before continuing')
```

### Monthly CSV export

```bash
curl "https://api.venice.ai/api/v1/billing/usage-history?startTimestamp=2026-04-01T00:00:00Z&endTimestamp=2026-05-01T00:00:00Z&pageSize=1000" \
  -H "Authorization: Bearer $VENICE_ADMIN_KEY" \
  -H "Accept: text/csv" \
  -o billing-april.csv
```

Read `x-next-cursor` off the response and re-request with `?cursor=<token>` (and
no other parameters) until the header is absent.

### Top-models chart

```ts
const a = await fetch(`${base}/billing/usage-analytics?lookback=30d`, { headers }).then(r => r.json())
// chart(a.byModelDaily, { series: a.topModels, xField: 'date' })
```

## Errors

| Code | Meaning |
|---|---|
| `400` | Bad params (`startDate` without `endDate`, calendar range > 90 days). On `/billing/usage-history`: a `cursor` sent with any filter, an unknown parameter, or `endTimestamp` not later than `startTimestamp`. `lookback=100d` is silently **clamped** to 90 days rather than rejected. |
| `401` | Auth failed, or `INFERENCE` key used on `/billing/balance`, `/billing/usage-history`, or `/billing/usage` (ADMIN required). |
| `410` | `/billing/usage` only — the account was created on or after 2026-07-07 and must use `/billing/usage-history`. |
| `429` | `/billing/usage` only — the deprecated 1 request/minute cap. |
| `500` | Internal error. |
| `504` | Analytics query timed out — shorten `lookback` or date range. |

## Gotchas

- This is **Beta** — field names may shift. Validate against `swagger.yaml` periodically.
- Don't build anything new on `/billing/usage`. One request per minute is not a pagination budget, and new accounts can't call it at all.
- `/billing/usage-history` takes `startTimestamp` / `endTimestamp` / `pageSize`; `/billing/usage` takes `startDate` / `endDate` / `limit` / `page`. The parameter names do not carry over when you migrate.
- `/billing/usage-history` accepts `USD`, `DIEM`, and `BUNDLED_CREDITS` for `currency`. Legacy `VCU` is only on `/billing/usage`.
- `currency` values on `/billing/usage` include legacy `VCU` — use `DIEM` instead in new code.
- `inferenceDetails` is `null` for non-inference SKUs (e.g. subscription charges).
- The analytics endpoint is **cached 10 min** — sudden spikes lag in the dashboard by that window.
- `byModelDaily.date` is a **Unix milliseconds integer**; `byDate.date` is a **`YYYY-MM-DD` string**. Don't mix them.
- Usage entries from the Venice web app have `apiKeyId: null` — don't drop them when reconciling.
- For x402 (wallet) balance, don't use this endpoint — use `GET /x402/balance/{walletAddress}`.
