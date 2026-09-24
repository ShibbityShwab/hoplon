---
name: venice-text-routing
description: Route a prompt to the right Venice text model based on privacy tier (anonymized / private / TEE / E2EE), modality (vision / audio / video input), capability (reasoning, code, function calling, web search, large context, structured output), and cost. Use when a local agent (Claude Code, Hermes, NanoClaw, Codex CLI, etc.) needs to decide whether to handle a prompt locally or escalate to Venice, and if escalating, which Venice text model to call. Sits one level above venice-models (model discovery) and before venice-chat (the call surface).
---

# Venice Text-Model Routing

This skill encodes the *decision logic* for "which Venice text model do I call?" — the routing layer that sits above [`venice-chat`](../venice-chat/SKILL.md) (the call surface) and consumes [`venice-models`](../venice-models/SKILL.md) (the discovery API).

Primary use case: a **local agent** receives a prompt, decides whether the local model can handle it, and — if not — picks the cheapest Venice model that satisfies the privacy / modality / capability requirements.

## Snapshot freshness

> Before applying the matrix below, read [`snapshots/text-routing.json`](snapshots/text-routing.json). If the file is missing, **or `snapshot_date` is older than 30 days**, run `python scripts/refresh_routing.py` to regenerate it from `GET /models?type=text` + `GET /models/traits?type=text`. Otherwise trust the cached file — do **not** hit `/models` on every routing decision.

`refresh_routing.py` requires `VENICE_API_KEY` in the environment and rewrites both [`snapshots/text-routing.json`](snapshots/text-routing.json) and [`routing-matrix.md`](routing-matrix.md). Run it once on first install, then ~monthly (CI nightly is also fine).

## When to load this skill

- Picking a Venice text model from a prompt at runtime.
- Building a local-first agent that escalates to Venice for hard prompts.
- Deciding privacy tier (anonymized vs private vs TEE vs E2EE).
- Choosing between a trait shortcut (`default_reasoning`, `most_intelligent`, …) and a hand-filtered candidate.

For the chat call surface itself, see [`venice-chat`](../venice-chat/SKILL.md). For raw discovery of every model field, see [`venice-models`](../venice-models/SKILL.md).

## Privacy tier ladder

Pick the *least restrictive* tier that satisfies the request — restricting tier shrinks the candidate pool and often raises cost.

| Tier | Selector | Guarantee | Use when |
|---|---|---|---|
| **Anonymized** | `model_spec.privacy: "anonymized"` (no `tee-` / `e2ee-` prefix) | Venice strips IPs / metadata; the underlying provider (Anthropic, xAI, OpenAI, …) sees the prompt under their privacy policy | Default for non-sensitive workloads; only path to certain frontier closed-weights models. |
| **Private** | `model_spec.privacy: "private"` (no prefix) | Open-weights model self-hosted by Venice; **zero data retention**; no third party sees the prompt | Default for any user data, business logic, or anything you wouldn't paste into ChatGPT. |
| **TEE** | model id starts with `tee-` | Runs inside Intel TDX / NVIDIA confidential-compute enclave; Venice infrastructure cannot read the prompt; verifiable via `GET /api/v1/tee/attestation` | Regulated data, signed responses required, "Venice itself can't see this." |
| **E2EE** | model id starts with `e2ee-` | TEE + client-side ECDH (secp256k1) / HKDF-SHA256 / AES-256-GCM; prompt encrypted before leaving the device | Strongest. Healthcare, legal, secrets, anything where the wire payload must be opaque. Requires E2EE handshake — see [`venice-chat`](../venice-chat/SKILL.md). |

Sources: [docs.venice.ai/overview/privacy](https://docs.venice.ai/overview/privacy), [docs.venice.ai/guides/features/tee-e2ee-models](https://docs.venice.ai/guides/features/tee-e2ee-models).

E2EE is **not** supported on `/responses` — route encrypted requests to `/chat/completions`.

### Verifying a TEE claim

Two endpoints let you check that inference really ran inside an enclave. Both
are `GET`, **unauthenticated on purpose** (attestation evidence has to be
verifiable by any party without credentials), and rate limited to **10 requests
per minute per IP**. Neither appears in `swagger.yaml`, so `sync_from_swagger.py`
flags `/tee/attestation` as stale. That is expected: the endpoints are live and
`GET /models` points at them from the `supportsTeeAttestation` capability
description.

| Endpoint | Query | Returns |
|---|---|---|
| `GET /api/v1/tee/attestation` | `model` (required), `nonce` (optional hex, up to 64 chars / 32 bytes, used to bind an NVIDIA attestation to your challenge) | Attestation report, hardware type, and the TEE signing public key. |
| `GET /api/v1/tee/signature` | `model` and `request_id` (required), `signing_algo` (optional `ecdsa` \| `ecdsa-p256` \| `rsa`) | The provider's signature over a specific request, plus request/response hashes. |

Both return `400` if the model exists but is not TEE-attested, and `404` if the
model ID is unknown.

Verify the chain of trust in this order: fetch the attestation to get the
signing public key and hardware type, confirm the recovered signer matches the
attestation signing address, then verify the signature over the exact signed
text the signature endpoint returned. Treat the request and response hashes as
provider-reported values unless you can recompute them yourself from a
documented canonical format.

## Capability filters

Map prompt requirement → `model_spec.capabilities` flag (full list in [`venice-models`](../venice-models/SKILL.md#model_speccapabilities--text-models)).

| Requirement | Filter | Notes |
|---|---|---|
| Vision (single image) | `supportsVision: true` | Single-image vision models drop older images on each turn — chain images into the **last** user message. |
| Vision (multiple images) | `supportsVision && supportsMultipleImages` | Honor `maxImages` per request. |
| Audio input | `supportsAudioInput: true` | Audio must be base64; URLs are not accepted. |
| Video input | `supportsVideoInput: true` | Accepts public URLs (incl. YouTube on some providers) or base64. |
| Reasoning / chain-of-thought | `supportsReasoning: true` | If you need to dial effort, additionally require `supportsReasoningEffort` so `reasoning.effort` is honored. |
| Tools / function calling | `supportsFunctionCalling: true` | Required for any agent loop. |
| Code-heavy task | `optimizedForCode: true` | `?type=code` filter on `/models` returns only this subset. |
| Web search (Venice / Brave) | `supportsWebSearch: true` | Toggle with `venice_parameters.enable_web_search`. |
| X / Twitter search | `supportsXSearch: true` | xAI native (Grok models). Adds ~$0.01/search. |
| Structured JSON output | `supportsResponseSchema: true` | Use `response_format: {type: "json_schema", ...}`. |
| Large context (≥ 100K tokens) | `availableContextTokens >= 100000` | Pair with `prompt_cache_key` + `cache_input` pricing. |
| Logprobs | `supportsLogProbs: true` | Niche — eval / sampling debug. |

## Cost tiers

The Venice text catalog clusters by per-1M-token price. Buckets below match the size labels documented at [docs.venice.ai/models/text](https://docs.venice.ai/models/text). Pick the smallest bucket that hosts a model satisfying your capability filters.

| Tier | Rough $/1M in | Rough $/1M out | Use when |
|---|---|---|---|
| **XS** | < $0.20 | < $0.40 | Classification, intent extraction, simple summarization. |
| **S** | $0.20 – $1 | $0.40 – $2 | General chat, basic agents, light vision. |
| **M** | $1 – $4 | $2 – $10 | Reasoning at moderate depth, strong code, multi-image vision. |
| **L** | $4 – $10 | $10 – $30 | Long context (≥ 200K), heavy reasoning, complex tool use. |
| **Frontier** | ≥ $10 | ≥ $30 | Best-available — Claude Opus, GPT-5.x Pro, GLM 5.1 thinking, Grok-4 Heavy. Resolve via trait `most_intelligent`. |

Authoritative per-model pricing lives on `model_spec.pricing` in [`snapshots/text-routing.json`](snapshots/text-routing.json) — never hard-code dollar figures from this prose.

## Routing decision tree

Walk top-down. Stop at the first rule that applies.

```
1. Local-first check
   - Prompt is ≤ ~500 tokens, no special-capability requirement,
     no privacy escalation, no tool calls expected
     → handle on the local model. Do not call Venice.

2. Privacy gate
   - User flagged "private" OR prompt contains regulated data (PHI, secrets, legal):
       require model_spec.privacy === "private"
       OR model id startsWith "tee-" / "e2ee-".
   - User flagged "E2EE" / "must be encrypted in transit":
       require model id startsWith "e2ee-". Skip /responses.
   - User flagged "TEE" / "verifiable inference":
       require model id startsWith "tee-".
   - Otherwise: any tier acceptable (still prefer privacy: "private" when otherwise tied).

3. Modality gate
   - Image input present  → require supportsVision (+ supportsMultipleImages if > 1).
   - Audio input present  → require supportsAudioInput.
   - Video input present  → require supportsVideoInput.

4. Capability gate
   - Tool calls expected               → require supportsFunctionCalling.
   - Code-heavy task                   → prefer optimizedForCode (or call /models?type=code).
   - Chain-of-thought / planning / hard math
                                       → require supportsReasoning;
                                         prefer supportsReasoningEffort to dial reasoning.effort.
   - Structured JSON output required   → require supportsResponseSchema.
   - Web search needed                 → require supportsWebSearch
                                         (or supportsXSearch for X/Twitter content).

5. Context size gate
   - Estimated (prompt + expected output) > availableContextTokens of the candidate
     → bump up to a model with sufficient context. Prefer ones with cache_input pricing.

6. Frontier override
   - User asked for "best", "frontier", "most intelligent", "smartest"
     → resolve trait `most_intelligent` from the snapshot. Skip cost-min step.

7. Cost minimization
   - From surviving candidates, pick the smallest cost tier (XS → S → M → L → frontier).
     Tie-break by lower output $/1M, then lower input $/1M.

8. Sanity filters (apply throughout)
   - Drop model_spec.beta === true unless your key has beta access.
   - Drop model_spec.offline === true.
   - Drop candidates whose model_spec.regionRestrictions exclude the caller.
```

## Trait shortcuts

When the prompt maps cleanly to a named trait, skip the matrix and resolve the trait from the snapshot's `traits` block (sourced from `GET /models/traits?type=text`):

| Trait | Use for |
|---|---|
| `default` | Generic chat / catch-all. |
| `fastest` | Latency-critical, low-stakes. |
| `default_reasoning` | "Think step by step" without specifying a model. |
| `default_code` | Code generation / refactor / review. |
| `default_vision` | Vision input, no other special needs. |
| `function_calling_default` | Agent loops, tool use. |
| `most_intelligent` | "Best available", frontier override. |
| `most_uncensored` | Refusal-free / red-team / creative writing without content filtering. |

Cache the resolved trait → ID map at session start (one HTTP call) and reuse.

## Local-first pattern

For a local agent driving Venice as an "escalation backend":

1. **Score the prompt cheaply** (locally):
   - Token count of prompt + expected output.
   - Modality signals (any image / audio / video parts).
   - Keyword signals: "code", "reason", "step by step", "private", "secret", "encrypt", "best", "frontier".
   - User-provided overrides (e.g. `--model frontier`, `--privacy e2ee`).

2. **Decide local vs Venice**:
   - If estimated tokens ≤ local model's comfort window AND no capability or privacy escalation → stay local.
   - Otherwise → continue to step 3.

3. **Run the decision tree above** to pick a Venice model.

4. **Call** via [`venice-chat`](../venice-chat/SKILL.md):

   ```bash
   curl https://api.venice.ai/api/v1/chat/completions \
     -H "Authorization: Bearer $VENICE_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "<chosen id>",
       "messages": [...],
       "venice_parameters": {"include_venice_system_prompt": false}
     }'
   ```

5. **Cap blast radius**: log the chosen model + estimated cost before sending; refuse to escalate beyond the user's `--max-cost` ceiling.

## Examples

**Example 1 — local-first wins**

Prompt: "Summarize this email in one sentence: …" (~200 tokens)

- Step 1 → local handles it. **Do not call Venice.**

**Example 2 — privacy + reasoning**

Prompt: "Here's our customer churn dataset (PII). Reason about which factors drive churn."

- Step 2 → privacy gate requires `privacy: "private"` or `tee-` / `e2ee-` prefix.
- Step 4 → reasoning required → `supportsReasoning: true`.
- Step 7 → among private/TEE candidates with reasoning, pick the cheapest.
- → typically a `tee-*` reasoning model, or `traits.default_reasoning` filtered to `privacy: "private"`.

**Example 3 — multi-image vision**

Prompt: 3 product photos + "Compare these for build quality."

- Step 3 → `supportsVision && supportsMultipleImages && maxImages >= 3`.
- Step 7 → cheapest survivor → typically `traits.default_vision`.

**Example 4 — frontier intelligence on a long doc**

Prompt: "Give me your absolute best take on this 50-page legal brief."

- Step 5 → context size gate triggers (> 100K tokens).
- Step 6 → frontier override fires (`most_intelligent`).
- → resolve `traits.most_intelligent` (a Claude Opus / GPT-5.x Pro / GLM 5.1 family ID, depending on the snapshot).

**Example 5 — code agent with tools**

Prompt: "Refactor this repo. You have shell + edit tools."

- Step 4 → `supportsFunctionCalling && optimizedForCode`.
- Step 7 → cheapest survivor → `traits.default_code` if it also supports tools, else `traits.function_calling_default` filtered by `optimizedForCode`.

## Future extensions

A `scripts/route.py` CLI may be added later for runtimes that prefer structured output (`route.py --prompt '...' --max-cost 0.001 --need-vision` → `{"model_id": "...", "estimated_cost": ..., "tier": "..."}`). The prose decision tree above remains the source of truth.

Sibling routing skills (`venice-image-routing`, `venice-audio-routing`, `venice-video-routing`) can mirror this layout when needed.

## Gotchas

- **Don't hard-code model IDs.** Venice rolls models monthly — resolve via traits or filters against the snapshot.
- **Stale snapshot lies silently.** The 30-day rule is the floor; refresh sooner if you hit a 404 on a model ID.
- **Privacy ≠ uncensored.** `most_uncensored` and `privacy: "private"` are independent axes.
- **`enable_e2ee` defaults to `true`** on E2EE-capable models when the right headers are present — see [`venice-chat`](../venice-chat/SKILL.md). The routing decision selects the model; the chat skill drives the handshake.
- **Beta / offline models in the snapshot.** Filter out `model_spec.beta === true` (unless your key has beta access) and `model_spec.offline === true` before scoring.
- **Region restrictions.** `model_spec.regionRestrictions[]` returns `403` outside the listed countries — drop those candidates if your caller is outside.
- **Trait keys differ by `type`.** Always pass `?type=text`. Don't reuse image traits.

## See also

- [`venice-models`](../venice-models/SKILL.md) — `/models`, `/models/traits`, `/models/compatibility_mapping` (the discovery API this skill consumes).
- [`venice-chat`](../venice-chat/SKILL.md) — `/chat/completions` (the call surface this skill picks a model for).
- [`venice-auth`](../venice-auth/SKILL.md) — Bearer vs x402 wallet auth.
- [`venice-billing`](../venice-billing/SKILL.md) — confirming actual spend matched the routing estimate.
- [`venice-errors`](../venice-errors/SKILL.md) — 402 / 422 / 429 handling on routed requests.
- Per-model snapshot: [`snapshots/text-routing.json`](snapshots/text-routing.json).
- Per-model human-readable matrix: [`routing-matrix.md`](routing-matrix.md).
