---
name: venice-auth
description: Authenticate to the Venice API with a Bearer API key or with an x402 / SIWX wallet (EVM on Base or Ed25519 on Solana). Covers the SIGN-IN-WITH-X header format, the SIWE and Solana message fields, TTL and nonce rules, the venice-x402-client SDK, and how to choose between the two modes.
---

# Venice Authentication

Every Venice endpoint accepts **one of two** auth schemes, declared in the OpenAPI spec as `BearerAuth` and `siwx`. Both are first-class — pick whichever fits the deployment.

## Use when

- You're making your first call to `api.venice.ai`.
- You're building a server-side integration (usually Bearer) or an agent / no-account wallet flow (x402).
- You hit `401 Authentication failed` and need to check header format.
- You're implementing SIWE signing manually instead of using the SDK.

## Option A — Bearer API key

```http
Authorization: Bearer <VENICE_API_KEY>
```

- Create keys at <https://venice.ai/settings/api> or via [`venice-api-keys`](../venice-api-keys/SKILL.md).
- Keys carry `consumptionLimits` (USD and/or DIEM caps) and `apiKeyType` (`ADMIN` or `INFERENCE`).
- Billing draws from DIEM (staked), USD balance, and bundled credits in order.
- Key types determine which endpoints are reachable — only `ADMIN` keys can manage other keys.

```bash
curl https://api.venice.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $VENICE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "zai-org-glm-5-1",
    "messages": [{"role":"user","content":"hello"}]
  }'
```

Use the Bearer scheme when you have a Venice account, want usage analytics (`/billing/usage-analytics`), want to issue scoped child keys, or need DIEM / bundled credit priority.

## Option B — x402 wallet (SIWX)

Authenticate with an Ethereum wallet on Base or a Solana wallet on Solana mainnet. No account needed. Pay per request in USDC. Balance lives under your wallet address and is consumed automatically.

### Header

```http
SIGN-IN-WITH-X: <base64(json)>
```

`SIGN-IN-WITH-X` is the canonical x402 v2 header name. Venice's original
`X-Sign-In-With-X` is still accepted for backwards compatibility, so existing
integrations keep working, but new code should send the canonical name.

Where the decoded JSON is:

| Field | Notes |
|---|---|
| `address` | EVM (checksummed hex) or Solana (base58) wallet address. |
| `message` | The signed SIWX message. EVM uses EIP-4361 SIWE; Solana uses the Solana SIWX format. Optional if you send the structured fields instead (see below). |
| `signature` | EVM signatures are hex. Solana signatures may be base58 or base64. |
| `timestamp` | Unix ms. Venice-legacy field. Canonical SIWX relies on the signed `Issued At` instead, and Venice only cross-checks `timestamp` when you send it. |
| `chainId` | `8453`, `"8453"`, or `"eip155:8453"` for Base. `"solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"` for Solana. |
| `type` | Optional signature type. `"ed25519"` for Solana. Omitted means EVM / EIP-191. |

```json
{
  "address":   "0x... (checksummed)",
  "message":   "<SIWE message string from SiweMessage.prepareMessage()>",
  "signature": "0x... (hex)",
  "timestamp": 1712659200000,
  "chainId":   8453
}
```

You may also omit `message` and send the structured SIWX fields (`domain`,
`address`, `uri`, `version`, `nonce`, `issuedAt`, `expirationTime`, `notBefore`,
`statement`, `resources`, `chainId`, `type`). Venice rebuilds the exact message
bytes server-side and verifies the signature over them. The rebuilt `Chain ID`
line uses the **bare reference** (`8453`, `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp`),
not the CAIP-2 form, so sign the bare value.

### SIWE message fields (EIP-4361, EVM)

| Field | Value |
|---|---|
| `domain` | One of the allow-listed Venice domains: `venice.ai`, `api.venice.ai`, `outerface.venice.ai`, `preview.venice.ai`, `staging.venice.ai` (plus `localhost` in dev). The server's own generated challenge uses `api.venice.ai`. |
| `uri` | Matching `https://<domain>` URL. |
| `version` | `"1"` |
| `address` | the wallet's checksummed address |
| `statement` | `"Sign in to Venice AI"` (what the server's generated challenge uses — any string is accepted, this one keeps consent UX consistent). |
| `nonce` | random 16-char hex, single-use per wallet |
| `issuedAt` / `expirationTime` | ISO-8601. Server enforces a hard **5-minute** window from `issuedAt` (`expirationTime` is informational only). |
| `chainId` | `8453` — accepted as number (`8453`), numeric string (`"8453"`), or CAIP-2 (`"eip155:8453"`). |

The header is short-lived — generate a fresh one at most every ~4 minutes (server accepts up to 5 min from `issuedAt`). When you send the legacy `timestamp` field it must be within **30 seconds** of the signed `issuedAt`; omit it and only `issuedAt` is checked. `issuedAt` must not be more than 30 seconds ahead of server time (`X402_SIGN_IN_FUTURE_TIMESTAMP`). Nonces are single-use per wallet — reuse within ~5.5 minutes is rejected with `X402_SIGN_IN_NONCE_REUSED`.

Domain is validated against the allow-list above — **not** against the incoming request's `Host` header. Passing any allow-listed domain (e.g. `api.venice.ai`) is fine regardless of which Venice host you hit.

### Solana message fields

Solana wallets sign the Solana SIWX message with Ed25519. The message opens with
`<domain> wants you to sign in with your Solana account:`, then the base58
address, then the same `URI`, `Version`, `Chain ID`, `Nonce`, `Issued At`, and
optional `Expiration Time` lines as the EVM form:

```
api.venice.ai wants you to sign in with your Solana account:
7xKX...base58...

Sign in to Venice AI

URI: https://api.venice.ai
Version: 1
Chain ID: 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp
Nonce: 3f2a91c4d80b7e15
Issued At: 2026-07-28T19:00:00.000Z
Expiration Time: 2026-07-28T19:05:00.000Z
```

In the base64 payload set `type: "ed25519"` and
`chainId: "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"`. The `Chain ID` line inside
the signed message carries the bare reference without the `solana:` prefix. The
same 5-minute window, 30-second skew, and single-use nonce rules apply.

### Manual signing (TypeScript)

```ts
import { Wallet } from 'ethers'
import { SiweMessage } from 'siwe'

const wallet = new Wallet(process.env.WALLET_KEY!)

function makeSiwxHeader() {
  const msg = new SiweMessage({
    domain: 'api.venice.ai',
    address: wallet.address,
    statement: 'Sign in to Venice AI',
    uri: 'https://api.venice.ai',
    version: '1',
    chainId: 8453,
    nonce: crypto.randomUUID().replace(/-/g, '').slice(0, 16),
    issuedAt: new Date().toISOString(),
    expirationTime: new Date(Date.now() + 4 * 60_000).toISOString(),
  })
  const message = msg.prepareMessage()
  const signature = wallet.signMessageSync(message)
  return btoa(JSON.stringify({
    address: wallet.address,
    message,
    signature,
    timestamp: Date.now(),
    chainId: 8453,
  }))
}

const res = await fetch('https://api.venice.ai/api/v1/chat/completions', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'SIGN-IN-WITH-X': makeSiwxHeader(),
  },
  body: JSON.stringify({
    model: 'zai-org-glm-5-1',
    messages: [{ role: 'user', content: 'hello' }],
  }),
})
```

### SDK shortcut

```bash
npm install venice-x402-client
```

```ts
import { VeniceClient } from 'venice-x402-client'

const venice = new VeniceClient(process.env.WALLET_KEY!)

await venice.topUp(10)            // $10 USDC on Base (first time only)
const res = await venice.chat({
  model: 'zai-org-glm-5-1',
  messages: [{ role: 'user', content: 'Hello!' }],
})
console.log(res.choices[0].message.content)
```

`VeniceClient` and `createAuthFetch` handle SIWE signing, header rotation, and `402` top-up prompts automatically.

### First-time top-up (wallet → credits)

```
POST /x402/top-up                # WITHOUT payment header → returns Base + Solana payment requirements
→ pick one entry from accepts[] and sign it with the x402 SDK (createPaymentHeader)
POST /x402/top-up                # WITH PAYMENT-SIGNATURE header → credits land on your wallet address
```

`PAYMENT-SIGNATURE` is the canonical x402 v2 payment header. The legacy
`X-402-Payment` and `X-PAYMENT` names are also accepted.

See [`venice-x402`](../venice-x402/SKILL.md) for the full flow.

## Choosing between the two

| Need | Pick |
|---|---|
| Server-side dashboard with usage analytics | Bearer |
| Scoped child keys, consumption limits per app | Bearer |
| DIEM-staked users / bundled credits | Bearer |
| Serverless function that pays per call | x402 |
| Agents with an on-chain budget, no account | x402 |
| End-user wallets authing directly (browser extension, mobile wallet) | x402 |
| Team sharing — one seed, many consumers | Bearer (+ child keys) |

Both schemes can co-exist: a Pro user may generate a **Web3 API key** via `POST /api_keys/generate_web3_key` that ties an on-chain wallet to an off-chain key with an EIP-191 signature. See [`venice-api-keys`](../venice-api-keys/SKILL.md).

## Common auth errors

| Status | Likely cause |
|---|---|
| `401 Authentication failed` | bad/expired key, SIWE older than 5 min from `issuedAt`, `payload.timestamp` off by >30s, `domain` not in the Venice allow-list, unsupported chain id, nonce replayed. The server returns a specific code like `X402_SIGN_IN_EXPIRED`, `X402_SIGN_IN_TIMESTAMP_MISMATCH`, `X402_SIGN_IN_DOMAIN_MISMATCH`, `X402_SIGN_IN_NONCE_REUSED`, or `X402_SIGN_IN_INVALID_CHAIN_ID` (code always set; `message` may fall back to generic text for some codes). |
| `402 x402` (no header) | `SIGN-IN-WITH-X` is **missing** on an SIWX-gated route (`/x402/balance`, `/x402/transactions`). Add the header. |
| `401 This model is only available to Pro users` | using x402 or an INFERENCE key on a gated model — switch to a Pro Bearer key |
| `402 PAYMENT_REQUIRED` (x402) | wallet balance too low; read `topUpInstructions` and top up via `/x402/top-up` |
| `402 INSUFFICIENT_BALANCE` (Bearer) | DIEM + USD + bundled credits are all empty; top up at venice.ai |

## Security hygiene

- Bearer keys behave like passwords — store in a secret manager, rotate on compromise, scope via `consumptionLimits`.
- SIWX requires a private key signer on the client side. For browsers, use a wallet provider (MetaMask or WalletConnect on EVM, Phantom or a wallet-standard adapter on Solana) — do **not** ship raw private keys.
- Signed headers are valid **5 minutes** from `issuedAt`; rotate every ~4 minutes. Never reuse a signed `SIGN-IN-WITH-X` header across hours or across machines. Nonces are tracked per wallet for ~5.5 min; replaying one is rejected with `X402_SIGN_IN_NONCE_REUSED`.
- Rate limits are per-key (Bearer) or per-wallet (x402). See [`venice-api-keys`](../venice-api-keys/SKILL.md) and [`venice-errors`](../venice-errors/SKILL.md).
