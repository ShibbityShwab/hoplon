---
name: redteam-roe
description: "Mandatory rules-of-engagement gate for all offensive work. Use FIRST before recon, scanning, web testing, exploitation, or any active action, and whenever authorization, scope, time window, or emergency contact is unclear. Triggers: roe, rules of engagement, authorization, scope, get written authorization, engagement, out of scope, emergency contact."
---

# Rules of Engagement (ROE) Gate

This skill gates every other offense skill. No active action runs until this gate passes.

## Hard stop

If there is no written authorization covering the target, STOP. Do not scan, enumerate, fuzz, exploit, or touch the asset, not even a single request. Ask the operator for the authorization artifact. If it is absent, offer only passive OSINT against public sources and clearly label it as awareness, not testing.

Written authorization means a signed document (statement of work, engagement letter, or rules-of-engagement appendix) that names the legal entity granting permission and lists the assets in scope. A verbal "go ahead" from an employee who may not own the asset is not authorization.

## Pre-flight authorization checklist

Confirm every line before the first active packet. Record the answers in the engagement log.

1. Authorization: signed document exists, dated, names the granting entity and the authorized tester(s).
2. Scope (in): explicit list of domains, IP ranges/CIDR, hostnames, applications, APIs, cloud accounts, and physical sites approved for testing.
3. Scope (out): explicit exclusions. Include third-party hosting, payment processors, shared infrastructure, production data stores, and any subsidiary not named in the authorization.
4. Time window: start and end dates/times with timezone, plus permissible testing hours and any blackout windows (business peaks, financial close, release freezes).
5. Emergency contact: named person, role, phone, and secondary contact, reachable during the window. Include the escalation path if a host becomes unstable.
6. Data handling: classification of data that may be encountered, whether exfiltration is permitted, storage and encryption rules, retention/deletion deadline, and who receives findings.
7. Rules of engagement specifics: permitted techniques, prohibited techniques (denial of service, social engineering, physical intrusion, destructive payloads), and whether testing is announced (white box) or stealth (black box).
8. Insurance and legal: liability coverage, indemnification, and the governing jurisdiction if not in the SOW.
9. Notification: who is told before testing starts, and the agreed signal for "stop all testing now".
10. Reporting: deliverable format, due date, and secure channel for transmitting findings.

## Hard stop conditions during the engagement

Abort and notify the emergency contact when any of these occur:

- A target resolves to an asset outside the approved scope.
- Authorization cannot be produced or has expired.
- Testing destabilizes a host or service, or causes data loss/corruption.
- The emergency stop signal is given.
- You are asked to continue past the approved time window.

## Staying in scope

- Resolve every hostname and confirm the resolved IP and owning organization fall inside the approved ranges before probing. DNS can shift; re-check at each phase.
- Phase-gate scope: recon, scanning, exploitation, and post-exploitation each need their assets listed and approved. Approval for recon does not extend to exploitation.
- Shared infrastructure (CDNs, managed databases, SaaS tenants) is out of scope unless the authorization explicitly names the provider and account.
- Two targets that share an IP do not share scope. Test the named host, not the neighbor on the same address.
- Track a live scope ledger (asset, in/out, approval reference, last tested). Update it before acting, not after.

## Evidence and logging discipline

- Keep a timestamped, timezone-stamped engagement log. Every action gets a start time, tool, command or MCP call, target, and result summary.
- Preserve raw output (terminal transcripts, HTTP request/response pairs, tool exports, screenshots). Store under an engagement directory with a clear naming scheme.
- Hash or checksum critical evidence at capture time so it can be shown unaltered.
- Never edit raw evidence. Write analysis and interpretation in separate files.
- Log negative results too. "No findings on X" is a valid, reportable outcome.
- Redact secrets discovered during testing from anything that leaves the engagement directory by default.

## Destructive-action approval

Some actions can damage or expose the client even when in scope. Treat each as requiring a fresh, explicit go-ahead that names the action and the target:

- Denial of service, stress, or load testing of any kind.
- Destructive SQL (DROP, DELETE, UPDATE on live data), file deletion, service shutdown, or config changes.
- Password spraying or lockout-prone authentication attacks against production accounts.
- Payloads that persist, exfiltrate real data, or modify business logic.
- Anything that could trip a production alarm or auto-remediation system.

Workflow for approval: describe the action, the target, the expected blast radius, and the rollback plan; get written confirmation from the named emergency contact or authorizing entity; record the approval in the engagement log before executing.

## Operating posture

Assume the client's monitoring will see you. Be loud where it helps detection testing and quiet where stealth is the objective, per the agreed rules. When in doubt about scope or impact, stop and ask. A paused engagement is recoverable; an out-of-scope action is not.
