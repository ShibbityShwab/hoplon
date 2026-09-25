# MCP servers

Hoplon wires twelve MCP servers in `config/opencode.jsonc`. Only the Venice
server is enabled by default. Recon and intel servers are present but off until
you add API keys. Weapon servers are present but disabled and are enabled per
specialist agent.

Every server that wraps a CLI tool requires the underlying binary on `PATH`. Run
`./hoplon doctor` to see which runtimes and weapon binaries are installed.

## Server table

| Server | Type | Default | Command | Requirement |
| --- | --- | --- | --- | --- |
| `venice` | local | enabled | `npx -y @veniceai/mcp-server@0.2.0` | `npx`, `VENICE_API_KEY` |
| `shodan` | local | disabled | `npx -y @burtthecoder/mcp-shodan@1.0.32` | `npx`, `SHODAN_API_KEY` |
| `cve` | local | disabled | `uvx --from cve-mcp-server==0.5.0 cve-mcp` | `uvx`, optional NVD / VirusTotal / GreyNoise keys |
| `nmap` | local | disabled | `npx -y mcp-nmap-server@1.0.1` | `npx` |
| `pentest` | local | disabled | `npx -y pentest-mcp@0.9.0` | `npx` |
| `nuclei` | local | disabled | `docker run -i --rm nuclei-mcp:latest` | Docker image |
| `sqlmap` | local | disabled | `docker run -i --rm sqlmap-mcp:latest` | Docker image |
| `ffuf` | local | disabled | `docker run -i --rm ffuf-mcp:latest` | Docker image |
| `burp` | remote | disabled | SSE at `http://127.0.0.1:9876` | Burp BApp running |
| `metasploit` | local | disabled | `uv --directory /opt/MetasploitMCP run MetasploitMCP.py --transport stdio` | `/opt/MetasploitMCP`, `MSF_PASSWORD` |
| `bloodhound` | local | disabled | `python /opt/BloodHound-MCP-AI/BloodHound-MCP.py` | `/opt/BloodHound-MCP-AI`, Neo4j at `bolt://localhost:7687` |
| `ghidra` | local | disabled | `docker run -i --rm -v /samples:/samples:ro ghidra-mcp:latest` | Docker image, samples at `/samples` |

## The Venice server

`venice` is Venice's own MCP server: 31 tools over the full Venice API (chat,
embeddings, image, video, audio, music, characters, augment/web search, models,
crypto RPC, x402). It is published under the `veniceai` org and the `@veniceai`
npm scope and documented by Venice as its MCP server, but the package README
marks it community-maintained with no SLA.

It is enabled by default because it is the native Venice toolset. It uses
`VENICE_API_KEY` and sets these defaults:

| Variable | Value |
| --- | --- |
| `VENICE_DEFAULT_CHAT_MODEL` | `venice-uncensored-1-2` |
| `VENICE_DEFAULT_IMAGE_MODEL` | `flux-2-pro` |
| `VENICE_DEFAULT_TTS_MODEL` | `tts-kokoro` |
| `VENICE_DEFAULT_ASR_MODEL` | `openai/whisper-large-v3` |
| `VENICE_HTTP_TIMEOUT_MS` | `120000` |

The server's two prompts (`uncensored-research`, `image-style-explorer`) log a
harmless argument error at startup; the tools themselves work.

## Enabling a server

1. Add the required key to `.env`. For example, `SHODAN_API_KEY=...`.
2. Set `"enabled": true` on the server in `config/opencode.jsonc`.
3. Restart `./hoplon`.

For the `cve` server, install the package first:

```bash
uvx --from cve-mcp-server==0.5.0 cve-mcp --help
```

For the Docker servers, build and tag the images locally:

```bash
docker build -t nuclei-mcp:latest .
```

For `metasploit` and `bloodhound`, clone the checkouts under `/opt` and set the
matching password in `.env`.

## Per-agent tool gating

Weapon tools are globally off:

```jsonc
"tools": {
  "nmap*": false, "pentest*": false, "nuclei*": false,
  "sqlmap*": false, "ffuf*": false, "burp*": false,
  "metasploit*": false, "bloodhound*": false, "ghidra*": false
}
```

An agent re-enables only what it owns in its `tools` map. For example,
`agents/recon.md` enables `shodan*`, `cve*`, `nmap*`, and `pentest*`, and
`agents/web-attacker.md` enables `burp*`, `nuclei*`, `ffuf*`, `sqlmap*`, and
`pentest*`.

## Pinning

Every `npx` and `uvx` server is version-pinned. The four Docker images are
locally built and currently tagged `:latest`; pin them by tagging each build
with the bundled tool version and a date, then pinning the digest:

```bash
docker inspect --format '{{index .RepoDigests 0}}' <image:tag>
```

The `metasploit` and `bloodhound` servers run local checkouts under `/opt`; pin
those by git commit. `mcp-nmap-server` has not published since January 2025 and
`cve-mcp-server` since May 2025, so treat both as frozen-at-pin.

## Verifying defaults

```bash
awk '/^    "venice": \{/,/^    \}/' config/opencode.jsonc | grep -m1 enabled
grep -A5 '"shodan"' config/opencode.jsonc | grep enabled
awk '/^    "cve": \{/,/^    \}/' config/opencode.jsonc | grep -m1 enabled
```

`venice` should show `true`; `shodan` and `cve` should show `false`.
