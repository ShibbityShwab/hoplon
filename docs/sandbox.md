# Sandbox

`HOPLON_SANDBOX=1` wraps opencode in `bubblewrap` (`bwrap`). It is the real
containment boundary for the YOLO permissions and prompt-injection risks
described in [Security](security.md). The permission matcher is a text denylist,
not a boundary.

## What it does

The launcher builds a `bwrap` invocation with these properties:

| Property | Effect |
| --- | --- |
| `--die-with-parent` | the sandbox dies if the launcher dies |
| `--unshare-user --unshare-pid --unshare-ipc --unshare-uts` | own user, pid, ipc, uts namespaces |
| `--ro-bind /usr /usr` | `/usr` read-only |
| `--ro-bind /etc /etc` | `/etc` read-only |
| `--ro-bind-try /bin /lib /lib64 /sbin /opt` | those system paths read-only when present |
| `--proc /proc --dev /dev` | fresh proc and dev |
| `--tmpfs /run` | empty `/run`; host sockets and `/run/user` are gone |
| `--ro-bind-try /run/systemd/resolve` | resolver state, so `/etc/resolv.conf` still resolves |
| `--ro-bind /run/NetworkManager` | NetworkManager resolver state, when present on the host |
| `--tmpfs /tmp` | fresh tmp |
| `--ro-bind "$HOPLON_HOME" "$HOPLON_HOME"` | the repo is read-only |
| `--bind "$HOPLON_HOME/home" "$HOPLON_HOME/home"` | the isolated state home is read-write |
| `--bind "$PWD" "$PWD"` | the target directory is read-write, unless it is inside the repo |
| `--chdir "$PWD"` | start in the target directory |

The network is **not** unshared, so the Venice API stays reachable. That is
deliberate: the agent needs the API to work.

## What works inside

Everything under `/usr` is available: `grep`, `sed`, `awk`, `curl` (TLS
verified), `wget`, `ping`, `dig`, `openssl`, `ssh`, `nmap`, `git`, `python3`,
`node`, `npx`, `uvx`, `jq`, `rg`, and the rest of coreutils. DNS resolves,
HTTPS reaches Venice, and `nmap -sT` (TCP connect) works. The agent can read
`/usr`, `/etc`, `/opt`, the project directory, and the isolated home, and can
write only under `HOPLON_HOME/home` and the target directory.

## What does not work inside

- **Container runtimes.** `/run` is an empty tmpfs, so the Docker socket,
  containerd, podman, dbus, and `/run/user` are not visible. `docker` and
  friends cannot reach a host daemon, and the CLI cannot start one.
- **Repo writes.** The repo is read-only. The agent cannot modify the launcher,
  `scripts/`, `config/`, `bin/`, or `.env` from inside the sandbox.
- **Raw-socket tooling.** `nmap -sS`, ARP sweeps, and packet capture need
  `CAP_NET_RAW` and fail inside. Run those unsandboxed with `HOPLON_SANDBOX=0`.
- **Host user bins.** Tools installed in the host home (`~/.local/bin`,
  `~/.cargo/bin`, `~/go/bin`, `~/.bun/bin`) are not mounted unless you set
  `HOPLON_SANDBOX_BINS=1`.
- **Host credentials.** `~/.ssh` and `~/.config` are not visible, and the
  launcher drops host credential and agent variables before launch (see below).
- **`/etc/shadow`.** Not readable.
- **Writes outside the state home and target.** `/usr` and `/etc` are
  read-only.

## Host environment is scrubbed

Before opencode starts, the launcher unsets host credential, agent, and
container-runtime selectors, in the sandbox and on the host tier alike:

- SSH and GPG agents: `SSH_AUTH_SOCK`, `SSH_AGENT_PID`, `SSH_ASKPASS`,
  `GIT_ASKPASS`, `GPG_AGENT_INFO`.
- Kerberos and GitHub tokens: `KRB5CCNAME`, `KRB5_CONFIG`, `GITHUB_TOKEN`,
  `GH_TOKEN`.
- Cloud credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_SESSION_TOKEN`, and every exported `AZURE_*`, `GOOGLE_*`, or `GCP_*`
  name.
- Container endpoints: `DOCKER_HOST`, `DOCKER_TLS_VERIFY`, `DOCKER_CERT_PATH`,
  `DOCKER_CONTEXT`.
- Runtime dirs: `XDG_RUNTIME_DIR` is reset to `$HOME/.run` and `TMPDIR` to
  `$HOME/tmp`, both inside the isolated home.

The opt-in passthroughs (`HOPLON_SHARE_SSH=1`, `HOPLON_SHARE_GH=1`) still
symlink the host files in. They do not restore the agent variables.

## Broad target directories are refused

The sandbox binds the target directory read-write. Launching from `/`, the host
home, or an ancestor of the host home would expose an entire tree, so the
launcher refuses those targets and exits. Override with
`HOPLON_SANDBOX_ALLOW_BROAD=1` only when you intend to expose that tree; the
override prints a warning and binds the target read-write.

## Exposing host user bins

Set `HOPLON_SANDBOX_BINS=1` to bind these read-only when they exist:

- `~/.local/bin`
- `~/.bun/bin`
- `~/.cargo/bin`
- `~/go/bin`

Everything in `/usr` is already available without this.

## Usage

```bash
HOPLON_SANDBOX=1 ./hoplon
HOPLON_SANDBOX=1 HOPLON_SANDBOX_BINS=1 ./hoplon
HOPLON_SANDBOX=1 HOPLON_SANDBOX_ALLOW_BROAD=1 ./hoplon   # broad target, read-write
```

If `HOPLON_SANDBOX=1` is set but `bwrap` is missing, the launcher prints a
warning and runs unsandboxed. Check `./hoplon doctor` for `bwrap (sandbox)`.

## When to use it

The sandbox is the `host` tier's containment boundary. For a full kernel
boundary, use the `vm` or `nix` tier instead; see [Isolation](isolation.md).
Use the sandbox when handling untrusted content or running risky code. Do not
use it for raw-socket reconnaissance; that needs the host network stack. The
practical split:

| Task | Sandbox |
| --- | --- |
| Processing untrusted files or web content | yes |
| Running third-party code | yes |
| Web app testing over TCP connect | yes |
| Container tooling that needs a host daemon | no |
| Raw-socket scans, ARP, packet capture | no |
| Tools installed in the host user home | only with `HOPLON_SANDBOX_BINS=1` |
