# Contributing to Hoplon

Thanks for considering a contribution. Hoplon is a portable, uncensored,
red-team-focused OpenCode distribution, and it is licensed
AGPL-3.0-or-later. This document covers the fork, branch, and pull request
flow, the commit convention, the development setup, the lint commands, the
sign-off requirement, and the safety expectations that come with a project
that ships offensive tooling.

## Before you start

- Read [AGENTS.md](AGENTS.md) for the operator model and the rules of
  engagement.
- Read [SECURITY.md](SECURITY.md) if your change touches the launcher, the
  sandbox, permissions, or anything that handles credentials.
- Check the issue tracker for an existing issue. Open one before large work so
  the design can be agreed on first.

## Scope and rules of engagement

Hoplon invokes offensive security tooling by design. That shapes what a
contribution may contain.

- Do not add tooling, payloads, or automation whose only purpose is to attack
  systems without authorization. Features must serve authorized engagements.
- Do not weaken the rules-of-engagement gate. The `redteam-roe` skill gates
  every offense skill, and that gate stays mandatory.
- Do not commit real target data, credentials, API keys, or engagement
  artifacts. Use synthetic fixtures.
- Keep the isolation model intact. The launcher isolates `HOME` and the XDG
  directories on purpose. Changes that leak host state, or that read or write
  the host's OpenCode or OMO state, will be rejected.
- If you are unsure whether a change crosses a line, open an issue and ask
  before writing code.

## Development setup

Requirements: `bash`, `curl`, and either `tar` (Linux) or `unzip` (macOS). The
installer supports Linux and macOS on `x64` and `arm64`.

```bash
git clone <your-fork> hoplon
cd hoplon
scripts/install.sh
cp .env.example .env      # then set VENICE_API_KEY
./hoplon doctor           # report binary, key, sandbox, MCP and weapon tooling
```

`scripts/install.sh` fetches a pinned opencode binary into `bin/`. The default
version is `1.18.25`, overridable with `HOPLON_OPENCODE_VERSION`. The release
repo defaults to `anomalyco/opencode`, overridable with `HOPLON_OPENCODE_REPO`.
Pin `HOPLON_OPENCODE_SHA256` in `.env` to make a tampered or partial download
fail closed.

Run the test suite with:

```bash
tests/run.sh
```

If the tests directory is not present in your checkout, the suite has not been
vendored yet; run the manual checks in the lint section below and say so in
your pull request.

## Lint and validation

Run every check that applies to the files you touched. All of them must pass
before a pull request is ready.

```bash
shellcheck hoplon scripts/install.sh
shfmt -d hoplon scripts/install.sh
actionlint
markdownlint '**/*.md'
```

JSONC validation: the config files carry comments, so strip them before
handing the result to `jq`.

```bash
for f in config/opencode.jsonc config/omo.jsonc; do
  sed 's://.*::' "$f" | jq empty
done
jq empty config/tui.json themes/hoplon.json themes/hoplon-ghost.json
```

Also confirm the tree carries no em dashes or en dashes, since the project
treats them as a hard style violation:

```bash
grep -rnP '[\x{2013}\x{2014}]' \
  --include='*.md' --include='*.sh' --include='*.jsonc' .
```

## Fork, branch, and pull request flow

1. Fork the repository and clone your fork.
2. Create a topic branch off the default branch. Use a short, descriptive name:
   `fix/launcher-restore`, `docs/contributing`, `feat/doctor-json`.
3. Make focused commits. Keep each commit to one logical change.
4. Rebase on the default branch before opening the pull request, and resolve
   conflicts locally.
5. Open the pull request against the default branch. Fill in what changed, why,
   and how you verified it. Link the issue it closes.
6. Respond to review. Push follow-up commits rather than force-pushing over
   reviewed history unless a reviewer asks for a rebase.

Keep diffs minimal. Do not refactor unrelated code in the same pull request.
Preserve the existing patterns and style.

## Commit convention

Hoplon uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

```text
<type>(<optional scope>): <description>

<optional body>

<optional footer>
```

Common types:

- `feat`: a new feature
- `fix`: a bug fix
- `docs`: documentation only
- `refactor`: a change that neither fixes a bug nor adds a feature
- `test`: adding or correcting tests
- `chore`: build, tooling, or maintenance
- `ci`: continuous integration changes

Examples:

```text
feat(launcher): add HOPLON_SANDBOX_BINS passthrough
fix(install): install by rename so a killed download cannot truncate
docs(readme): document the Magic Context plugin
```

Write the description in the imperative mood, lower case, no trailing period.
Keep the subject under 72 characters. Use the body to explain what and why, not
how.

## Developer Certificate of Origin

Every commit must be signed off under the
[Developer Certificate of Origin](https://developercertificate.org/). Add the
trailer with `git commit -s`:

```text
Signed-off-by: Your Name <you@example.com>
```

The sign-off certifies that you wrote the contribution or otherwise have the
right to submit it under the project license. Pull requests with unsigned
commits will be asked to amend.

## Licensing: inbound equals outbound

Hoplon is licensed AGPL-3.0-or-later. By submitting a contribution you agree
that it is licensed under the same terms, inbound equals outbound. Do not
submit code you cannot license this way. If you vendor third-party code, record
its provenance and license in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
and confirm the license is compatible with AGPL-3.0-or-later.

## Review and merge

A maintainer reviews every pull request. Expect questions about scope, safety,
and verification. A pull request merges when the checks pass, the review is
approved, and the change is inside scope. Maintainers may close a pull request
that weakens the safety model or falls outside the project's purpose.
