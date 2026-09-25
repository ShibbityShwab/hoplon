# Sandbox

`HOPLON_SANDBOX=1` wraps opencode in `bubblewrap` (`bwrap`). It is the real
mitigation for the YOLO permissions and prompt-injection risks described in
[Security](security.md).

## What it does

The launcher builds a `bwrap` invocation with these properties:

| Property | Effect |
| --- | --- |
| `--die-with-parent` | the sandbox dies if the launcher dies |
| `--unshare-user --unshare-pid --unshare-ipc --unshare-uts` | own user, pid, ipc, uts namespaces |
| `--ro-bind /usr /usr` | `/usr` read-only |
| `--ro-bind-try /bin /lib /lib64 /sbin /etc /opt /run` | system paths read-only when present |
| `--proc /proc --dev /dev --tmpfs /tmp` | fresh proc, dev, tmp |
| `--bind "$HOPLON_HOME" "$HOPLON_HOME"` | the repo is writable |
| `--bind "$PWD" "$PWD"` | the target directory is writable, unless it is inside the repo |
| `--chdir "$PWD"` | start in the target directory |

The network is **not** unshared, so the Venice API stays reachable. That is
deliberate: the agent needs the API to work.

## What works inside

Everything under `/usr` is available: `grep`, `sed`, `awk`, `curl` (TLS
verified), `wget`, `ping`, `dig`, `openssl`, `ssh`, `nmap`, `git`, `python3`,
`node`, `npx`, `uvx`, `jq`, `docker`, `rg`, and the rest of coreutils. DNS
resolves, HTTPS reaches Venice, and `nmap -sT` (TCP connect) works.

## What does not work inside

- **Raw-socket tooling.** `nmap -sS`, ARP sweeps, and packet capture need
  `CAP_NET_RAW` and fail inside. Run those unsandboxed with `HOPLON_SANDBOX=0`.
- **Host user bins.** Tools installed in the host home (`~/.local/bin`,
  `~/.cargo/bin`, `~/go/bin`, `~/.bun/bin`) are not mounted unless you set
  `HOPLON_SANDBOX_BINS=1`.
- **Host credentials.** `~/.ssh` and `~/.config` are not visible.
- **`/etc/shadow`.** Not readable.
- **Writes outside the repo and target.** `/usr` is read-only.

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
```

If `HOPLON_SANDBOX=1` is set but `bwrap` is missing, the launcher prints a
warning and runs unsandboxed. Check `./hoplon doctor` for `bwrap (sandbox)`.

## When to use it

Use the sandbox when handling untrusted content or running risky code. Do not
use it for raw-socket reconnaissance; that needs the host network stack. The
practical split:

| Task | Sandbox |
| --- | --- |
| Processing untrusted files or web content | yes |
| Running third-party code | yes |
| Web app testing over TCP connect | yes |
| Raw-socket scans, ARP, packet capture | no |
| Tools installed in the host user home | only with `HOPLON_SANDBOX_BINS=1` |
