---
name: venice-x402
description: Manage Venice x402 wallet credits. Covers POST /x402/top-up (payment discovery + signed USDC settlement), GET /x402/balance/{walletAddress}, GET /x402/transactions/{walletAddress}, USDC on Base (chain 8453) and Solana mainnet, the PAYMENT-SIGNATURE / SIGN-IN-WITH-X header names, minimum $5 top-up, transaction types TOP_UP/CHARGE/REFUND, and the x402 v2 PAYMENT-REQUIRED response shape returned by all inference endpoints.
---

# Venice x402 (wallet credits)

x402 is Venice's **wallet-based payment** flow. Pay per request with USDC on Base or Solana mainnet, no account required. Three admin endpoints plus the protocol-level `402` response returned by every inference endpoint.

| Endpoint | Auth | Purpose |
|---|---|---|
| `POST /x402/top-up` | None (discovery) / `PAYMENT-SIGNATURE` (settlement) | Discover payment requirements, then settle a signed USDC transfer. |
| `GET /x402/balance/{walletAddress}` | SIWX (`SIGN-IN-WITH-X`) | Current USD balance for a wallet. |
| `GET /x402/transactions/{walletAddress}` | SIWX | Paginated ledger: `TOP_UP`, `CHARGE`, `REFUND`. |

For the SIWX header format itself, see [`venice-auth`](../venice-auth/SKILL.md).

## Header names

Venice accepts three payment header names and two sign-in header names. Send the
canonical one in new code; the others exist so older integrations keep working.

| Purpose | Canonical | Also accepted |
|---|---|---|
| Signed payment (settlement) | `PAYMENT-SIGNATURE` | `X-402-Payment` (Venice original), `X-PAYMENT` (x402 v1 / `x402-fetch`, `x402-axios`) |
| Wallet sign-in proof | `SIGN-IN-WITH-X` | `X-Sign-In-With-X` (Venice original) |
| Payment requirements (response) | `PAYMENT-REQUIRED` | — |
| Settlement result (response) | `PAYMENT-RESPONSE` | — |

## Pay with a wallet: end-to-end

### 1. Call an inference endpoint with no balance → `402`

Any inference endpoint (e.g. `POST /chat/completions`) returns a `402` with structured `topUpInstructions` and `siwxChallenge` when the wallet balance is too low. The `PAYMENT-REQUIRED` response header carries the **x402 v2 `paymentRequired` object** (base64-encoded JSON containing `x402Version`, `error`, `resource`, `accepts[]`, and optional `extensions`) — it is **not** the same payload as the 402 body, which is a richer balance/top-up document.

```json
{
  "error": "Payment required",
  "code": "PAYMENT_REQUIRED",
  "message": "Insufficient x402 balance",
  "suggestedTopUpUsd": 10,
  "minimumTopUpUsd": 5,
  "supportedTokens": ["USDC"],
  "supportedChains": ["base", "solana"],
  "topUpInstructions": {
    "step1": "POST /api/v1/x402/top-up with no payment header to get payment requirements",
    "step2": "Choose a payment option from accepts and sign a USDC transfer authorization using the x402 SDK (createPaymentHeader)",
    "step3": "POST /api/v1/x402/top-up with the signed X-402-Payment header",
    "receiverWallet": "<RECEIVER_WALLET_ADDRESS>",
    "tokenAddress": "<USDC_TOKEN_ADDRESS>",
    "tokenDecimals": 6,
    "network": "eip155:8453",
    "minimumAmountUsd": 5
  },
  "siwxChallenge": {
    "info": { "domain": "api.venice.ai", "statement": "Sign in to Venice AI", ... },
    "supportedChains": [
      { "chainId": "eip155:8453", "type": "eip191" },
      { "chainId": "eip155:8453", "type": "eip1271" },
      { "chainId": "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", "type": "ed25519" }
    ]
  }
}
```

`topUpInstructions` describes the **Base** rail only (it predates the Solana
rail and still names the EVM receiver, token, and network). It also still names
the legacy `X-402-Payment` header in `step3`. To pay on Solana, read the
`accepts[]` array from `POST /x402/top-up` instead. `siwxChallenge.supportedChains`
is the authoritative list of chains and signature types you can sign in with.

### 2. Discover payment requirements — `POST /x402/top-up` (no header)

```bash
curl -X POST https://api.venice.ai/api/v1/x402/top-up
```

Response `402`. `accepts[]` carries **one entry per payment rail** (Base and
Solana today):

```json
{
  "x402Version": 2,
  "accepts": [
    {
      "scheme": "exact",
      "network": "eip155:8453",
      "asset": "<USDC_TOKEN_ADDRESS>",
      "amount": "5000000",          // base units; USDC = 6 decimals → 5 USDC
      "payTo": "<RECEIVER_WALLET_ADDRESS>",
      "maxTimeoutSeconds": 300,
      "extra": { "name": "USD Coin", "version": "2" }
    },
    {
      "scheme": "exact",
      "network": "solana",
      "asset": "<USDC_MINT_ADDRESS>",
      "amount": "5000000",
      "payTo": "<SOLANA_RECEIVER_ADDRESS>",
      "maxTimeoutSeconds": 300,
      "extra": { "name": "USD Coin", "version": "2", "feePayer": "<VENICE_FEE_PAYER>" }
    }
  ]
}
```

Pick the entry whose `network` matches your wallet and echo it back unchanged.
Venice accepts either the short alias or the CAIP-2 form on the way in (`base`
or `eip155:8453`; `solana` or `solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp`), so the
safest thing is to send back exactly what you were given.

On Solana, `extra.feePayer` is the Venice-operated account that pays the
transaction fee. Set it as the fee payer on the transfer you sign so the payer
does not need SOL.

### 3. Sign a USDC transfer → `POST /x402/top-up` with `PAYMENT-SIGNATURE`

The **x402 SDK** does the EIP-712 USDC `transferWithAuthorization` signing for you:

```bash
npm install x402
```

```ts
import { createPaymentHeader } from 'x402'
import { Wallet } from 'ethers'

const wallet = new Wallet(process.env.WALLET_KEY!)
// 1. Discover
const discover = await fetch(`${base}/x402/top-up`, { method: 'POST' })
const { accepts } = await discover.json()
const req = accepts.find(a => a.network === 'eip155:8453' || a.network === 'base')

// 2. Sign payment for $10 (write your own amount in base units)
const amount = '10000000' // $10
const header = await createPaymentHeader({ ...req, amount }, wallet)

// 3. Settle
const settle = await fetch(`${base}/x402/top-up`, {
  method: 'POST',
  headers: { 'PAYMENT-SIGNATURE': header },
})
const { data } = await settle.json()
console.log(data.newBalance, data.amountCredited, data.paymentId)
```

The settlement result is also returned base64-encoded in the `PAYMENT-RESPONSE`
response header.

`200` response:

```json
{
  "success": true,
  "data": {
    "walletAddress": "0x...",
    "amountCredited": 10,
    "newBalance": 22.5,
    "paymentId": "payment_01HZ..."
  }
}
```

### 4. Call inference again — credits are now debited from the wallet

The `venice-x402-client` SDK wraps steps 1–4: it catches `402`, auto-tops-up to a configured amount, and retries.

## `GET /x402/balance/{walletAddress}`

```bash
curl "https://api.venice.ai/api/v1/x402/balance/0xYOUR_WALLET" \
  -H "SIGN-IN-WITH-X: <base64 siwx>"
```

```json
{
  "success": true,
  "data": {
    "walletAddress": "0x...",
    "balanceUsd": 12.5,
    "canConsume": true,
    "minimumTopUpUsd": 5,
    "suggestedTopUpUsd": 10,
    "diemBalanceUsd": 5.25    // optional — present if the wallet is linked to a Venice account with DIEM
  }
}
```

The SIWX signer **must match** the path wallet — `403` otherwise.

## `GET /x402/transactions/{walletAddress}`

```bash
curl "https://api.venice.ai/api/v1/x402/transactions/0xYOUR_WALLET?limit=50&offset=0" \
  -H "SIGN-IN-WITH-X: <base64 siwx>"
```

```json
{
  "success": true,
  "data": {
    "walletAddress": "0x...",
    "currentBalance": 12.35,
    "transactions": [
      {
        "id": "ledger_01H...",
        "amount": -0.15,
        "balanceAfter": 12.35,
        "type": "CHARGE",
        "createdAt": "2026-04-03T12:34:56.000Z",
        "requestId": "chatcmpl-...",
        "modelId": "zai-org-glm-5-1"
      },
      {
        "id": "ledger_01H...",
        "amount": 10,
        "balanceAfter": 12.5,
        "type": "TOP_UP",
        "createdAt": "2026-04-03T12:00:00.000Z",
        "requestId": null,
        "modelId": null
      }
    ],
    "pagination": { "limit": 50, "offset": 0, "hasMore": false }
  }
}
```

### Transaction types

| `type` | Sign of `amount` | Meaning |
|---|---|---|
| `TOP_UP` | positive | `/x402/top-up` settlement. |
| `CHARGE` | negative | Inference debit. `requestId` / `modelId` link back to the call. |
| `REFUND` | positive | Failed request refund or manual adjustment. |

## Query parameters

### `/x402/transactions/{walletAddress}`

| Param | Notes |
|---|---|
| `limit` | 1–100. Default 50. |
| `offset` | Number of entries to skip. Default 0. |

Use `offset + limit` and `pagination.hasMore` for paging.

## Constants

- **Chains** — Base mainnet, chain ID `8453` (`eip155:8453`), and Solana mainnet (`solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp`).
- **Token** — USDC (6 decimals) on both rails. Native USDC on Base; not USDbC.
- **Signature types** — `eip191` and `eip1271` (smart contract wallets) on Base, `ed25519` on Solana.
- **Minimum top-up** — `$5` by default. A small number of allow-listed wallets (e.g. internal test wallets) may have a lower per-wallet override — always use the `minimumTopUpUsd` returned in `topUpInstructions` / `/x402/balance` rather than hardcoding `5`.
- **x402 SDK** — `npm install x402` for raw payment header signing, or `venice-x402-client` for the managed Venice flow.
- **Receiver wallets, token contracts, and the Solana fee payer** are returned in `accepts[]` / `topUpInstructions`; don't hardcode them.

## Errors

| Code | Meaning |
|---|---|
| `400` | Below minimum top-up, invalid wallet format, or other validation. |
| `401` | `SIGN-IN-WITH-X` header is **present** but invalid (bad signature, expired, nonce reuse, unsupported chain) — returned as `X402_SIGN_IN_*` error codes. |
| `402` | Expected **discovery** response on `/x402/top-up` (no payment header), on `/x402/balance` and `/x402/transactions` when the SIWX header is **absent**, and on any inference endpoint when the wallet balance is insufficient. Settlement errors use `INVALID_PAYMENT` / `INVALID_PAYMENT_FORMAT` / `INSUFFICIENT_FUNDS` / `EXPIRED_PAYMENT` codes. Rail mismatches use `INVALID_PAYMENT_RECIPIENT`, `UNSUPPORTED_TOKEN`, and `UNSUPPORTED_SCHEME` (only `scheme: "exact"` is accepted). |
| `403` | SIWX wallet ≠ path wallet. |
| `429` | Too many top-ups/balance checks. |
| `500` | Settlement failure; retry with a fresh nonce. |

## Gotchas

- Use the **x402 SDK** (`npm install x402`) for signing. Hand-rolling the EIP-712 `transferWithAuthorization` is risky — nonce reuse ⇒ `INVALID_PAYMENT`.
- The SIWX signer wallet must match the `walletAddress` path param on `balance` / `transactions`. Separate wallets can't inspect each other.
- `/x402/top-up` is unauthenticated on the **discovery** call — auth is implicit via the signed `PAYMENT-SIGNATURE` header on settlement.
- Don't read the rail off `topUpInstructions`. It still describes Base only. `accepts[]` is the multi-rail list.
- `balanceUsd` on `/x402/balance` is the **USDC** credit balance only. `diemBalanceUsd`, when present, is a **separate** linked-account number — sum them yourself if you need a combined figure.
- `PAYMENT-REQUIRED` (uppercase, hyphens) is the **header** with base64-encoded x402 `paymentRequired` object; don't confuse it with the body field `code: "PAYMENT_REQUIRED"` (which only appears on insufficient-balance bodies, not on auth-style 402s).
- On `/x402/balance` and `/x402/transactions`, **missing** the SIWX header returns `402` (not 401). Only a present-but-invalid header returns `401` with a `X402_SIGN_IN_*` code.
- The x402 v2 `accepts[].amount` is in **base units** (e.g. `"5000000"` = 5 USDC). Don't multiply by decimals again.
- `DIEM`, `BUNDLED_CREDITS`, and Bearer-account `USD` are independent from wallet credits. For account balance, use [`venice-billing`](../venice-billing/SKILL.md).
