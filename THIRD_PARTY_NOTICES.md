# Third-party notices

Hoplon bundles or depends on the following third-party components. Each retains
its own license; this file records provenance.

## Venice AI MCP server

- Package: `@veniceai/mcp-server`, version `0.2.0` (npm)
- Repository: https://github.com/veniceai/venice-mcp-server
- License: MIT
- Published under the `veniceai` GitHub org and the `@veniceai` npm scope, and
  documented by Venice as its Model Context Protocol server. The package README
  self-describes as community-maintained and provided as-is, with no warranty or
  SLA from Venice AI. Wired into `config/opencode.jsonc`.

## Venice AI skills

- Repository: https://github.com/veniceai/skills
- License: MIT, Copyright (c) 2026 Venice.ai
- Vendored verbatim into `skills/` as the `venice-*` directories.

## OpenCode

- Repository: https://github.com/anomalyco/opencode
- License: see the upstream repository
- The `opencode` binary is fetched by `scripts/install.sh` (not committed).

## Oh My OpenAgent

- Package: `oh-my-openagent`, version `5.0.0-beta.62` (npm)
- Repository: https://github.com/code-yeongyu/oh-my-openagent
- License: see the upstream repository
- Loaded as an OpenCode plugin; the plugin cache is fetched or pre-seeded at
  install time.
