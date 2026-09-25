# Models

Hoplon routes every request to Venice AI. Seven models are declared and
allowlisted in `config/opencode.jsonc`. This page lists them with their exact
limits and the routing for each agent and category.

## Provider

| Setting | Value |
| --- | --- |
| Provider | Venice AI (OpenCode built-in venice provider) |
| Base URL | `https://api.venice.ai/api/v1` |
| API key | `{env:VENICE_API_KEY}` |
| Timeout | 600000 ms |
| Header timeout | 60000 ms |
| Chunk timeout | 60000 ms |
| Model reference format | `venice/<model-id>` |

Do not add an `"npm"` override to `provider.venice`. The built-in provider
lowers options into Venice's `venice_parameters` (snake_case). A generic adapter
bypasses that and sends a camelCase object the API ignores.

## Declared models

This is the complete set. `provider.venice.whitelist` restricts the catalog to
exactly these seven.

| Model ID | Name | Context | Output | Tools | Reasoning | Vision |
| --- | --- | --- | --- | --- | --- | --- |
| `qwen-3-6-plus` | Qwen 3.6 Plus Uncensored | 1,000,000 | 65,536 | yes | yes | yes |
| `qwen-3-8-27b` | Qwen 3.8 27B (Uncensored, Vision) | 262,144 | 65,536 | yes | yes | yes |
| `aion-labs-aion-3-5` | Aion 3.5 (Uncensored) | 262,144 | 32,768 | yes | yes | no |
| `olafangensan-glm-4.7-flash-heretic` | GLM 4.7 Flash Heretic (Uncensored) | 200,000 | 24,000 | yes | yes | no |
| `venice-uncensored-1-2` | Venice Uncensored 1.2 | 128,000 | 8,192 | yes | no | yes |
| `venice-uncensored-role-play` | Venice Uncensored Role Play | 128,000 | 4,096 | yes | no | yes |
| `gemma-4-uncensored` | Gemma 4 Uncensored | 256,000 | 8,192 | yes | no | yes |

The non-uncensored community models (`glm-5-3-flash`, `deepseek-v4-pro`) are
omitted on purpose: Venice does not tag them uncensored, so upstream hosts can
still filter them. Only the uncensored set is declared.

## Agent routing

The OpenCode-native roster in `config/opencode.jsonc`:

| Agent | Model | Mode | Steps | Temp | Max tokens |
| --- | --- | --- | --- | --- | --- |
| `build` | `venice/qwen-3-6-plus` | primary | 25 | 0.1 | 32768 |
| `plan` | `venice/qwen-3-6-plus` | subagent | 15 | 0.2 | 16384 |
| `explore` | `venice/olafangensan-glm-4.7-flash-heretic` | subagent | 15 | 0.1 | 8192 |
| `oracle` | `venice/qwen-3-6-plus` | subagent | 20 | 0.2 | 32768 |
| `reviewer` | `venice/qwen-3-6-plus` | subagent | 15 | 0.2 | 16384 |
| `frontend` | `venice/qwen-3-6-plus` | subagent | 20 | 1.0 | 16384 |
| `asset-qa` | `venice/qwen-3-8-27b` | subagent | 15 | 0.0 | 16384 |
| `multimodal-looker` | `venice/qwen-3-8-27b` | subagent | 15 | 0.1 | 16384 |

The OMO layer in `config/omo.jsonc` tunes most of the same agents plus its own roster
(`sisyphus`, `prometheus`, `metis`, `momus`, `hephaestus`, `atlas`,
`sisyphus-junior`, `librarian`). OMO routing:

| Agent | Model | Reasoning |
| --- | --- | --- |
| `sisyphus`, `prometheus`, `hephaestus`, `oracle`, `atlas`, `build`, `plan`, `reviewer`, `frontend` | `venice/qwen-3-6-plus` | high |
| `metis`, `momus`, `multimodal-looker` | `venice/qwen-3-8-27b` | xhigh / low |
| `sisyphus-junior`, `explore`, `librarian` | `venice/olafangensan-glm-4.7-flash-heretic` | low / off |

## Category routing

| Category | Model | Reasoning |
| --- | --- | --- |
| `visual-engineering` | `venice/qwen-3-6-plus` | high |
| `artistry` | `venice/venice-uncensored-role-play` | off |
| `ultrabrain` | `venice/qwen-3-6-plus` | high |
| `deep` | `venice/qwen-3-6-plus` | high |
| `quick` | `venice/olafangensan-glm-4.7-flash-heretic` | off |
| `unspecified-low` | `venice/olafangensan-glm-4.7-flash-heretic` | low |
| `unspecified-high` | `venice/qwen-3-6-plus` | high |
| `writing` | `venice/venice-uncensored-1-2` | off |

## Reasoning effort

Reasoning effort is only applied where a model advertises an effort control:
`qwen-3-8-27b` and `olafangensan-glm-4.7-flash-heretic`. Settings on models
without one (for example `qwen-3-6-plus`) are dropped by the harness rather than
sent, so they are inert.

Sampling follows Venice's published per-model constraints where they exist. For
`qwen-3-6-plus` that is temperature 0.7 and top_p 0.8.

## Feature suffixes

Venice's feature suffixes (`:enable_web_search=on`,
`:include_venice_system_prompt=false`) do not resolve through the built-in
venice provider: a suffixed model id fails with "Provider not found". Enabling
them would mean switching back to the OpenAI-compatible adapter, which is what
breaks `venice_parameters`, so they are deliberately not used.

## Concurrency

`config/omo.jsonc` sets background task concurrency:

| Scope | Limit |
| --- | --- |
| Provider `venice` | 5 |
| `venice/qwen-3-6-plus` | 8 |
| `venice/qwen-3-8-27b` | 6 |
| `venice/olafangensan-glm-4.7-flash-heretic` | 10 |

## Verifying the roster

```bash
python3 -c "import re;s=open('config/opencode.jsonc').read();m=re.search(r'\"whitelist\":\s*\[(.*?)\]',s,re.S);print(len(re.findall(r'\"([^\"]+)\"',m.group(1))))"
# expected: 7
```

To list what the runtime resolves:

```bash
./hoplon models venice
```
