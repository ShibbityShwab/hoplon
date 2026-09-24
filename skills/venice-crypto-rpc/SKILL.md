---
name: venice-crypto-rpc
description: Use Venice as a pay-per-call JSON-RPC proxy to 27 EVM, Starknet, and Solana networks. Covers GET /crypto/rpc/networks, POST /crypto/rpc/{network}, chain families and per-family method allowlists, the 1×/2×/4× method-tier pricing model, per-minute + 24-hour credit rate limits, idempotency keys for safe retries, single vs batch requests, and the unsupported stateful/WebSocket methods (eth_subscribe, eth_newFilter, *Subscribe, etc.).
---

# Venice Crypto RPC (JSON-RPC proxy)

Venice exposes a **multi-chain JSON-RPC proxy** billed per call. Same request shape as Alchemy / Infura — just change the base URL and pay per credit.

| Endpoint | Auth | Notes |
|---|---|---|
| `GET /crypto/rpc/networks` | Bearer or SIWX | Returns `{ "networks": [...] }` (sorted). |
| `POST /crypto/rpc/{network}` | Bearer or SIWX (x402) | Forward a JSON-RPC 2.0 request (single or batch). |

## Supported networks

Call `GET /crypto/rpc/networks` for the current list. It currently returns 27 slugs (always verify — the catalog grows):

```
arbitrum-mainnet    arbitrum-sepolia
avalanche-mainnet   avalanche-fuji
base-mainnet        base-sepolia
blast-mainnet       blast-sepolia
bsc-mainnet         bsc-testnet
ethereum-mainnet    ethereum-sepolia    ethereum-holesky
linea-mainnet       linea-sepolia
optimism-mainnet    optimism-sepolia
polygon-mainnet     polygon-amoy
robinhood-mainnet   robinhood-testnet
solana-mainnet      solana-devnet
starknet-mainnet    starknet-sepolia
zksync-mainnet      zksync-sepolia
```

Use the slug as `:network` in the proxy path.

The `network` enum published in `swagger.yaml` currently lists only 25 of these:
it omits `blast-mainnet` and `blast-sepolia`, which the proxy does route. Trust
`GET /crypto/rpc/networks` over the spec enum, and don't build a client-side
validator from the enum or it will reject working networks.

### Chain families

Each network speaks exactly one method family, and the allowlist is enforced per
family. Sending an EVM method to a Solana network (or the reverse) is a `400`,
not a pass-through.

| Family | Networks | Methods |
|---|---|---|
| `evm` | Everything except Starknet and Solana, including Robinhood Chain (an Arbitrum Orbit L2). | `eth_*`, `net_*`, `web3_*`, `trace_*`, `debug_*`, `txpool_*`, and chain extensions `zks_*`, `linea_*`, `bor_*`, `arbtrace_*`. |
| `starknet` | `starknet-mainnet`, `starknet-sepolia` | `starknet_*`. |
| `solana` | `solana-mainnet`, `solana-devnet` | `getAccountInfo`, `getBalance`, `getLatestBlockhash`, `sendTransaction`, and the rest of the Solana JSON-RPC allowlist. |

## Send a JSON-RPC request

### Single call

```bash
curl -X POST https://api.venice.ai/api/v1/crypto/rpc/ethereum-mainnet \
  -H "Authorization: Bearer $VENICE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

```json
{ "jsonrpc": "2.0", "id": 1, "result": "0x1" }
```

### Batch (up to 100 calls)

```bash
curl -X POST https://api.venice.ai/api/v1/crypto/rpc/base-mainnet \
  -H "Authorization: Bearer $VENICE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '[
    {"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1},
    {"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":2}
  ]'
```

A single unsupported method in a batch ⇒ the **entire batch** fails with `400`.

### Drop-in with `viem` / `ethers`

```ts
import { createPublicClient, http } from 'viem'
import { mainnet } from 'viem/chains'

const client = createPublicClient({
  chain: mainnet,
  transport: http('https://api.venice.ai/api/v1/crypto/rpc/ethereum-mainnet', {
    fetchOptions: { headers: { Authorization: `Bearer ${process.env.VENICE_API_KEY}` } },
  }),
})
```

## Pricing

Credits per call = `baseCredits[chain] × methodTier`.

| Base credits | Chains |
|---|---|
| `20` | Ethereum, Base, Optimism, Arbitrum, Polygon, Linea, Avalanche, BSC, Blast, Robinhood, Starknet. |
| `30` | zkSync Era, Solana. |

| Tier | Multiplier | Methods |
|---|---|---|
| **Standard** | `1×` | `eth_call`, `eth_getBalance`, `eth_blockNumber`, `eth_sendRawTransaction`, `eth_getLogs`, `net_version`, `web3_clientVersion`, ERC-4337 bundler (`eth_sendUserOperation`, …), chain-family extensions (`zks_*`, `linea_*`, `bor_*`, `starknet_*`), and Solana methods (`getAccountInfo`, `getBalance`, `getLatestBlockhash`, `sendTransaction`, …). |
| **Advanced** | `2×` | `trace_*`, `debug_*`, `txpool_inspect`, `txpool_status`, `arbtrace_*`. |
| **Large** | `4×` | `trace_replayBlockTransactions`, `trace_replayTransaction`, `txpool_content`, `arbtrace_replay*`, and Solana `getLargestAccounts` / `getSupply`. |

At `~$7e-7` per credit:

- Standard EVM call (20 × 1) ≈ **$0.000014**
- Advanced trace on Ethereum (20 × 2) ≈ **$0.000028**
- Large trace replay (20 × 4) ≈ **$0.000056**
- zkSync standard call (30 × 1) ≈ **$0.000021**
- Solana standard call (30 × 1) ≈ **$0.000021**
- Solana `getLargestAccounts` (30 × 4) ≈ **$0.000084**

RPC-level errors (HTTP 200 with `error` object inside — e.g. method unsupported on that chain, bad params) are billed at a flat **5 credits** regardless of tier.

Response headers on `200`:

| Header | Meaning |
|---|---|
| `X-Venice-RPC-Credits` | Total credits charged (sum over batch). |
| `X-Venice-RPC-Cost-USD` | Dollar cost to 8 decimal places. |
| `X-Balance-Remaining` | Remaining x402 USD — set on routes whose middleware refreshes balance headers. The `/crypto/rpc/*` handler currently emits credits/cost/request headers; treat `X-Balance-Remaining` here as best-effort (may be absent on RPC). Use `GET /x402/balance/{walletAddress}` for an authoritative read. |
| `X-Request-ID` | 32-char correlation ID — include in support tickets. |
| `Idempotent-Replayed` | `"true"` when served from the idempotency cache. |

## Unsupported methods

These always return `400`:

- **Stateful filter methods** — `eth_newFilter`, `eth_newBlockFilter`, `eth_getFilterChanges`, `eth_getFilterLogs`, `eth_uninstallFilter`. Filter state is pinned to a single backend and a load-balanced HTTP proxy can't maintain it. Use `eth_getLogs` instead.
- **WebSocket-only methods** — EVM `eth_subscribe` / `eth_unsubscribe` and Solana `*Subscribe` / `*Unsubscribe`. This proxy is HTTP only. Run your own WS endpoint for subscriptions.
- **Cross-family methods** — calling `starknet_*` or Solana `getBalance` on an EVM chain, or `eth_call` on Solana, ⇒ `400`.
- **Unmapped methods** — anything not in the Standard/Advanced/Large lists.

## Idempotency

Set the `Idempotency-Key` header to any `[A-Za-z0-9_-]{1,255}` string for safe retries:

```bash
curl -X POST https://api.venice.ai/api/v1/crypto/rpc/ethereum-mainnet \
  -H "Authorization: Bearer $VENICE_API_KEY" \
  -H "Idempotency-Key: send-tx-2026-04-21-nonce-42" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["0x..."] ,"id":1}'
```

- Cached for **24 hours** keyed on `(user, idempotency-key)`.
- Replay returns the cached response with `Idempotent-Replayed: true` and is **not billed again**.
- Same key + **different body** ⇒ `400` (prevents silent corruption).

Use this for any state-mutating method (`eth_sendRawTransaction`, `eth_sendUserOperation`) to survive flaky networks without double-broadcasting.

## Rate limits

Two caps per caller, both enforced independently:

| Tier | Per-minute requests | Credits / rolling 24h |
|---|---|---|
| Paid | 100 | 10,000,000 |
| Staff | 1,000 | 100,000,000 |

`429` response `customMessage` identifies which cap tripped. Per-minute cap also sets `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers.

Concurrent-call collisions on the per-user mutex also return `429`. Retry with jitter.

## Errors

| Status | Typical cause |
|---|---|
| `400` | Unsupported network slug, empty body, batch > 100, unsupported/WebSocket/filter method, cross-family call, idempotency-key reuse with a different body. |
| `401` | Missing or invalid Bearer / SIWX. The `/networks` listing is public but the proxy endpoint requires auth. |
| `402` | Insufficient balance. x402 wallet users get a `PAYMENT-REQUIRED` header with structured top-up instructions (see [`venice-x402`](../venice-x402/SKILL.md)). |
| `429` | Per-minute, 24-hour credit, or concurrency cap tripped. |
| `500` | Upstream fetch failed / timeout. Safe to retry with the same `Idempotency-Key`. |

## Patterns

- **Multi-chain dashboards** — Single API key unlocks all networks. No per-chain keys to rotate.
- **High-throughput indexing** — Batch up to 100 calls per request; each sub-call is still billed individually, but the network round-trip is amortized.
- **Wallet-based (x402) RPC** — Pay per RPC call with USDC on Base or Solana. Use the `SIGN-IN-WITH-X` header; a `402` indicates low credit and carries structured top-up instructions.
- **Cost tracking** — Log `X-Venice-RPC-Credits` and `X-Venice-RPC-Cost-USD` per request; aggregate by `method` to see where credits go.
- **Safe transaction submission** — Always include an `Idempotency-Key` on `eth_sendRawTransaction`. The proxy then guarantees exactly-once semantics within 24 hours.
