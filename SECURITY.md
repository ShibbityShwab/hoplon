# Security Policy

Hoplon is a portable, uncensored, red-team-focused OpenCode distribution. It
invokes offensive security tooling by design, so the security model has two
sides: the security of this distribution itself, and the authorization
boundary around how it is used. This document covers both.

## Supported versions

Only the latest release line receives security fixes.

| Version | Supported |
| ------- | --------- |
| 1.0.x   | Yes       |
| < 1.0   | No        |

The bundled opencode binary is pinned by `scripts/install.sh` (default
`1.18.25`). If a vulnerability is in opencode itself, report it upstream to the
opencode project as well; Hoplon will bump the pin once a fixed release exists.

## Reporting a vulnerability

Report suspected vulnerabilities in Hoplon privately. Do not open a public
issue for a security problem.

Preferred channel: use GitHub's private vulnerability reporting. Open the
**Security** tab of this repository and click **Report a vulnerability**. That
starts a private security advisory visible only to you and the maintainers.

Fallback: if private advisories are unavailable, open a public issue that asks
for a private contact channel and contains no technical detail about the
vulnerability. A maintainer will move the conversation to a private thread.

Please include:

- A description of the issue and its impact.
- Steps to reproduce, with the exact commands and environment.
- The affected version, commit, or file.
- Any proof of concept, kept minimal and non-destructive.
- Whether you have disclosed it elsewhere.

## Response timeline

- Acknowledgement within 3 business days.
- An initial assessment, including severity and whether it is accepted, within
  10 business days.
- A fix or a mitigation plan for accepted issues as soon as practical, with
  progress updates in the private advisory.
- Coordinated disclosure once a fix is available. We will credit you in the
  advisory unless you ask us not to.

This is a volunteer project, so the timeline is a target, not a contract.

## Scope

In scope for this policy:

- The launcher (`hoplon`) and its isolation model: `HOME` and XDG isolation,
  environment scrubbing, the OMO config takeover and restore, and the
  `HOPLON_ISOLATION` delegation to the QEMU guest.
- The isolation backend: `scripts/vm.sh` and `scripts/toolchain.sh`.
- `scripts/install.sh`: download, checksum verification, and install-by-rename.
- The configuration in `config/`: permissions, provider wiring, MCP servers,
  and the rules-of-engagement gate.
- The agents in `agents/` and the skills in `skills/`.
- Any path where a secret (`VENICE_API_KEY` or an MCP key) could leak outside
  the isolated home or into a log, a commit, or model context.

Out of scope:

- Vulnerabilities in upstream opencode, OMO, the Venice MCP server, or the
  vendored Venice skills. Report those to their maintainers. Hoplon will track
  and bump pins.
- The behavior of third-party weapon tooling (`nmap`, `sqlite`, `metasploit`,
  and the rest) that Hoplon can invoke.
- Findings that require an already-compromised host or an operator who has
  disabled the VM tier and the ROE gate.

### Offensive tooling and authorization

Hoplon invokes offensive tooling by design. That is the point of the
distribution, and it is not a vulnerability. The tooling is gated by a
mandatory rules-of-engagement skill and by the operator's own authorization.

Laws and rules of engagement govern use. Use Hoplon only against systems you
own or have explicit written authorization to test. Unauthorized access,
scanning, or exploitation is illegal in most jurisdictions and can carry
criminal and civil liability. The operator is solely responsible for staying
inside scope and for complying with all applicable laws.

Reports that amount to "the tool can attack things" are out of scope. Reports
that the ROE gate can be bypassed, that the VM boundary can be escaped, or that
isolation leaks host state are in scope and welcome.

## No warranty

Hoplon is provided as is, without warranty of any kind, express or implied,
including but not limited to the warranties of merchantability, fitness for a
particular purpose, and noninfringement. The authors and maintainers accept no
liability for misuse or for any damage arising from use of this distribution.
See the license for the full terms.

## Hardening notes

The [Security page](docs/security.md) documents the current mitigations and
their limits. In short: run engagements on a disposable box, use
`HOPLON_ISOLATION=vm` when handling untrusted content (the QEMU guest is the
kernel boundary), treat `VENICE_API_KEY` as exposed to the model because bash is
allowed, and keep the key scoped.
