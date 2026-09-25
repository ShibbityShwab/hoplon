# Third-party notices

Hoplon's own code is licensed under the GNU Affero General Public License,
version 3 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).

Hoplon bundles, depends on, or invokes the third-party components listed below.
Each keeps its own license. This file records provenance: the exact upstream
URL, the pinned version, and the license. MIT components carry their full text
inline in this file, since the MIT license is short and its copyright line must
travel with the component. Where a full license text ships in this repository it
lives in [LICENSES/](LICENSES/); otherwise the component entry links the
upstream license file, and the summary table marks the text as `upstream`.

A note on the two categories that are easy to get wrong:

- **Fetched, not redistributed.** Several components are downloaded at runtime
  (by `npx`, `uvx`, OpenCode's plugin loader, `scripts/install.sh`, or
  `scripts/toolchain.sh`) and are not committed to this repository. They are
  listed here because Hoplon depends on them, not because their source ships in
  the tree.
- **Source-available, not open source.** `oh-my-openagent` uses the Sustainable
  Use License, which is not OSI-approved and restricts commercial use. It is
  called out in full below.

## Summary

| Component | Version (pinned) | License (SPDX) | Redistributed? | Text |
| --- | --- | --- | --- | --- |
| opencode | 1.18.25 | MIT | No, fetched by installer | inline below |
| veniceai/skills | vendored, no revision pinned | MIT | Yes, in `skills/` | inline below |
| @veniceai/mcp-server | 0.2.0 | MIT | No, fetched by `npx` | inline below |
| @cortexkit/opencode-magic-context | 0.43.1 | MIT | No, fetched by OpenCode | inline below |
| @burtthecoder/mcp-shodan | 1.0.32 | MIT | No, fetched by `npx` | inline below |
| mcp-nmap-server | 1.0.1 | MIT | No, fetched by `npx` | inline below |
| cve-mcp-server | 0.5.0 | MIT | No, fetched by `uvx` | inline below |
| pentest-mcp | 0.9.0 | GPL-3.0-or-later | No, fetched by `npx` | LICENSES/GPL-3.0-or-later.txt |
| oh-my-openagent | 5.0.0-beta.62 | SUL-1.0 | No, fetched at runtime | LICENSES/SUL-1.0.txt |
| Go toolchain | 1.24.0 | BSD-3-Clause | No, fetched by `scripts/toolchain.sh` | upstream |
| Ghidra | 12.1.4 | Apache-2.0 | No, fetched by `scripts/toolchain.sh` | upstream |
| Trivy | 0.74.0 | Apache-2.0 | No, fetched by `scripts/toolchain.sh` | upstream |
| kubectl | 1.31.0 | Apache-2.0 | No, fetched by `scripts/toolchain.sh` | upstream |
| jadx | 1.5.6 | Apache-2.0 | No, fetched by `scripts/toolchain.sh` | upstream |
| upx | 5.2.1 | GPL-2.0-or-later | No, fetched by `scripts/toolchain.sh` | upstream |
| sliver | 1.7.7 | GPL-3.0-only | No, fetched by `scripts/toolchain.sh` | upstream |
| feroxbuster | 2.13.1 | MIT | No, fetched by `scripts/toolchain.sh` | inline below |

---

## MIT components

The MIT license text is identical for every component below except for the
copyright line. The full text is reproduced once, then each component lists its
own copyright line and upstream URL.

### MIT license text

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### opencode

- Package: `opencode`, version `1.18.25` (the version this repo is tested on)
- Repository: https://github.com/anomalyco/opencode
- License: MIT
- Copyright: Copyright (c) 2025 opencode
- License file: https://github.com/anomalyco/opencode/blob/dev/LICENSE
- Redistributed: No. `scripts/install.sh` downloads the pinned release archive
  into `bin/`; the binary is gitignored and not committed. Override the version
  with `HOPLON_OPENCODE_VERSION` and the repo with `HOPLON_OPENCODE_REPO`.

### veniceai/skills

- Repository: https://github.com/veniceai/skills
- License: MIT
- Copyright: Copyright (c) 2026 Venice.ai
- License file: https://github.com/veniceai/skills/blob/main/LICENSE
- Redistributed: Yes. The 20 `venice-*` skill directories under `skills/` are
  vendored verbatim from this repository. The red-team skills under `skills/`
  are Hoplon's own work and are AGPL-3.0-or-later, not part of this component.
- Upstream revision: none pinned. The vendored directories are not tied to a
  recorded upstream commit or tag. Re-vendor from the repository when updating,
  and record the revision here at that point.

### @veniceai/mcp-server

- Package: `@veniceai/mcp-server`, version `0.2.0` (npm)
- Repository: https://github.com/veniceai/venice-mcp-server
- License: MIT
- Copyright: Copyright (c) 2026 Venice AI
- License file: https://github.com/veniceai/venice-mcp-server/blob/main/LICENSE
- Redistributed: No. Fetched by `npx -y @veniceai/mcp-server@0.2.0` at runtime.
  Wired into `config/opencode.jsonc` as the `venice` MCP server. Published under
  the `veniceai` GitHub org and the `@veniceai` npm scope and documented by
  Venice as its Model Context Protocol server; the package README self-describes
  as community-maintained and provided as-is, with no warranty or SLA from
  Venice AI.

### @cortexkit/opencode-magic-context

- Package: `@cortexkit/opencode-magic-context`, version `0.43.1` (npm)
- Repository: https://github.com/cortexkit/magic-context
- License: MIT
- Copyright: Copyright (c) 2025 Ufuk Altinok
- License file: https://github.com/cortexkit/magic-context/blob/master/LICENSE
- Redistributed: No. Loaded by OpenCode as a plugin, declared in
  `config/opencode.jsonc`. It owns compaction, which is why OMO's
  `preemptive-compaction` hook stays disabled in `config/omo.jsonc`.

### @burtthecoder/mcp-shodan

- Package: `@burtthecoder/mcp-shodan`, version `1.0.32` (npm)
- Repository: https://github.com/w0h1v/mcp-shodan
- License: MIT
- Copyright: Copyright (c) 2024 Burt
- License file: https://github.com/w0h1v/mcp-shodan/blob/main/LICENSE
- Redistributed: No. Fetched by `npx -y @burtthecoder/mcp-shodan@1.0.32` at
  runtime. Wired into `config/opencode.jsonc` as the `shodan` MCP server, which
  is disabled by default because it needs a paid `SHODAN_API_KEY`.

### mcp-nmap-server

- Package: `mcp-nmap-server`, version `1.0.1` (npm)
- Repository: https://github.com/PhialsBasement/nmap-mcp-server
- License: MIT
- Copyright: Copyright (c) 2025 PhialsBasement
- License file: https://github.com/PhialsBasement/nmap-mcp-server/blob/main/LICENSE
- Redistributed: No. Fetched by `npx -y mcp-nmap-server@1.0.1` at runtime. Wired
  into `config/opencode.jsonc` as the `nmap` MCP server, disabled by default.
  The package has not published since January 2025, so treat it as frozen at
  this pin.

### cve-mcp-server

- Package: `cve-mcp-server`, version `0.5.0` (PyPI)
- Repository: https://github.com/mukul975/cve-mcp-server
- License: MIT
- Copyright: Copyright 2025 cve-mcp-server (the upstream README also credits
  Copyright (c) 2025-2026 Mahipal Jangra (mukul975))
- License file: https://github.com/mukul975/cve-mcp-server/blob/main/LICENSE
- Redistributed: No. Fetched by `uvx --from cve-mcp-server==0.5.0 cve-mcp` at
  runtime. Wired into `config/opencode.jsonc` as the `cve` MCP server, disabled
  by default. The package has not published since May 2025, so treat it as
  frozen at this pin.

  Note: the repository's root `LICENSE` file is the Apache License 2.0, but the
  published `cve-mcp-server==0.5.0` distribution ships an MIT license file and
  its README states MIT. The version Hoplon pins (0.5.0) is MIT, which is what
  is recorded here. If you move to a different version, re-check the license.

---

## Other licenses

Full texts for these components are in [LICENSES/](LICENSES/).

### pentest-mcp

- Package: `pentest-mcp`, version `0.9.0` (npm)
- Repository: https://github.com/dmontgomery40/pentest-mcp
- License: GPL-3.0-or-later (SPDX: `GPL-3.0-or-later`)
- License file: https://github.com/dmontgomery40/pentest-mcp/blob/main/LICENSE
- Full text: [LICENSES/GPL-3.0-or-later.txt](LICENSES/GPL-3.0-or-later.txt)
- Redistributed: No. Fetched by `npx -y pentest-mcp@0.9.0` at runtime. Wired
  into `config/opencode.jsonc` as the `pentest` MCP server, disabled by default
  and enabled only inside the specialist that owns it.

  Note: the npm package metadata declares `GPL-3.0-or-later`, while the
  repository's root `LICENSE` file contains the MIT text. The published package
  metadata is the authoritative declaration for the version Hoplon pins, so
  GPL-3.0-or-later is recorded here. If you move to a different version,
  re-check the license.

### oh-my-openagent

- Package: `oh-my-openagent`, version `5.0.0-beta.62` (npm)
- Repository: https://github.com/code-yeongyu/oh-my-openagent
- License: SUL-1.0 (Sustainable Use License, version 1.0)
- License file: https://github.com/code-yeongyu/oh-my-openagent/blob/dev/LICENSE.md
- Full text: [LICENSES/SUL-1.0.txt](LICENSES/SUL-1.0.txt)
- Redistributed: No. Loaded by OpenCode as a plugin, declared in
  `config/opencode.jsonc`. `scripts/install.sh` may pre-seed the plugin cache
  from a host cache for offline use, but the plugin is not committed to this
  repository.

  **OMO is source-available, not OSI open source.** The Sustainable Use License
  is not an OSI-approved license. Its terms restrict commercial use: you may use
  or modify the software only for your own internal business purposes or for
  non-commercial or personal use, and you may distribute it or provide it to
  others only free of charge for non-commercial purposes. Hoplon fetches OMO at
  runtime and does not redistribute it. Anyone who runs Hoplon with OMO enabled
  is bound by those terms. If you need to use OMO commercially, obtain a
  separate license from its author.

---

## Red-team toolchain components

`scripts/toolchain.sh` fetches these during a `--full` install in the QEMU
guest or the Docker image. Each is downloaded from the URL below at the pinned
version and is not committed to this repository. The `HOPLON_*_VERSION`
environment variable overrides each pin.

### Go toolchain

- Component: the Go compiler and standard library (`go`, `gofmt`)
- Upstream: https://go.dev/dl/
- Repository: https://github.com/golang/go
- Version (pinned): `1.24.0` (`HOPLON_GO_VERSION`)
- License: BSD-3-Clause
- License file: https://github.com/golang/go/blob/master/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` when the distro Go is
  older than the minimum acceptable minor (default 21).

### Ghidra

- Component: NSA Ghidra software reverse engineering suite
- Upstream: https://github.com/NationalSecurityAgency/ghidra
- Version (pinned): `12.1.4` (`HOPLON_GHIDRA_VERSION`)
- License: Apache-2.0
- License file: https://github.com/NationalSecurityAgency/ghidra/blob/master/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` into `/opt/ghidra`.

### Trivy

- Component: Aqua Trivy vulnerability and misconfiguration scanner
- Upstream: https://github.com/aquasecurity/trivy
- Version (pinned): `0.74.0` (`HOPLON_TRIVY_VERSION`)
- License: Apache-2.0
- License file: https://github.com/aquasecurity/trivy/blob/main/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` into `/usr/local/bin`.

### kubectl

- Component: Kubernetes command-line client (`kubectl`)
- Upstream: https://github.com/kubernetes/kubernetes
- Release source: https://dl.k8s.io/release/stable.txt
- Version (pinned): `1.31.0` (`HOPLON_KUBECTL_VERSION`)
- License: Apache-2.0
- License file: https://github.com/kubernetes/kubernetes/blob/master/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` into `/usr/local/bin`.

### jadx

- Component: jadx Dex to Java decompiler
- Upstream: https://github.com/skylot/jadx
- Version (pinned): `1.5.6` (`HOPLON_JADX_VERSION`)
- License: Apache-2.0
- License file: https://github.com/skylot/jadx/blob/master/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` into `/opt/jadx`.

### upx

- Component: UPX executable packer
- Upstream: https://github.com/upx/upx
- Version (pinned): `5.2.1` (`HOPLON_UPX_VERSION`)
- License: `GPL-2.0-or-later`. The upstream license also grants a special
  exception for compressed executables, which is not a standard SPDX exception
  identifier, so the SPDX field records only the base license.
- License file: https://github.com/upx/upx/blob/devel/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` into `/usr/local/bin`.

### sliver

- Component: BishopFox Sliver command-and-control framework
- Upstream: https://github.com/BishopFox/sliver
- Version (pinned): `1.7.7` (`HOPLON_SLIVER_VERSION`)
- License: GPL-3.0-only
- License file: https://github.com/BishopFox/sliver/blob/master/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` into `/usr/local/bin`.

### feroxbuster

- Component: feroxbuster content discovery scanner
- Upstream: https://github.com/epi052/feroxbuster
- Version (pinned): `2.13.1` (`HOPLON_FEROXBUSTER_VERSION`)
- License: MIT
- Copyright: Copyright (c) 2020-2026 epi
- License file: https://github.com/epi052/feroxbuster/blob/main/LICENSE
- Redistributed: No. Fetched by `scripts/toolchain.sh` into `/usr/local/bin`.

---

## Components fetched on first use

For a fully offline copy, vendor the following. None of them are committed to
this repository.

- The `opencode` binary, fetched by `scripts/install.sh` (roughly 180 MB).
- The OMO plugin, fetched by OpenCode or pre-seeded by `scripts/install.sh`.
- The `npx` and `uvx` MCP servers, all version-pinned as listed above.
- The red-team toolchain binaries, fetched by `scripts/toolchain.sh --full`
  (Go, Ghidra, Trivy, kubectl, jadx, upx, sliver, feroxbuster, and the rest).
- LSP servers, downloaded on first use.
- OMO's ast-grep runtime, downloaded on first use.
