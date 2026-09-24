---
name: redteam-report
description: "Turn raw findings into a client-ready penetration test report with executive summary, structured findings, CVSS vectors, and remediation. Use after testing to write up results or when calibrating severity by real exploitability. Triggers: report, write up findings, penetration test report, executive summary, cvss, severity, remediation, client deliverable."
---

# Reporting

The report is the deliverable. A finding that is not clearly written, reproduced, and prioritized does not count. Write for two audiences: executives who need risk, and engineers who need to fix it.

## Report structure

1. Cover and metadata: client, engagement name, date range, tester(s), version, classification.
2. Executive summary: one page, non-technical. What was tested, the overall risk posture, the few things that matter most, and a short prioritized action list.
3. Scope and methodology: in-scope assets, out-of-scope exclusions, techniques used, tooling, and any limitations (time, access, unreachable hosts).
4. Risk overview: a table of findings by severity with counts, plus a short narrative on themes.
5. Findings: one section per finding, ordered by severity then impact.
6. Positive observations and coverage: what was tested and held up, and what could not be tested.
7. Appendices: asset inventory, evidence index, tool output references, CVSS scoring notes.

## Finding structure

Every finding uses the same shape:

- Title: short, specific, and impact-first. "Unauthenticated SQL injection in login endpoint allows full database read", not "SQLi on login".
- Severity: Critical / High / Medium / Low / Informational, with the CVSS base score.
- CVSS vector: the full base vector string, for example `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H`. Show the score and vector; do not hand-wave.
- Affected assets: exact hostnames, URLs, IPs, parameters, and versions.
- Description: the technical root cause in plain terms, and the class (CWE, OWASP WSTG ID).
- Reproduction steps: numbered, exact, and minimal. Someone with the right access should be able to reproduce it from the steps plus the evidence, without guessing.
- Evidence: request/response pairs, command output, screenshots. Reference the evidence file by name. Keep raw evidence unedited.
- Impact: what an attacker gains. Distinguish technical impact (code execution, data read) from business impact (data breach, regulatory exposure, downtime).
- Remediation: concrete, testable fixes, primary and defense-in-depth. Point to the exact config, code, or control to change.
- References: CWE, CVE, vendor advisory, and any standards.

## Executive summary guidance

- One page maximum. No jargon, no CVEs, no exploit detail.
- Lead with the answer: how well did defenses hold, and what is the single most important thing to fix.
- Translate findings into business language: what data or service is at risk, and what could realistically happen.
- Use a short prioritized list (fix first, fix next, backlog) tied to finding titles.
- Be honest about uncertainty and about what was not tested.
- Do not inflate. Do not bury a critical issue under a wall of informational noise.

## Severity calibration by real exploitability

Score by what you actually proved, not by what a scanner guessed. Calibrate with these questions:

- Reachability: can the issue be reached unauthenticated, or does it need a privileged session? Network position matters.
- Preconditions: what must be true for exploitation (default config, specific version, user interaction, a chained issue)?
- Demonstrated impact: did you prove data read/write, code execution, or a minor information leak? A theoretical worst case is not the same as a proven one.
- Exploit maturity: is there a public exploit, is it weaponized in the wild, or did you have to develop it?
- Blast radius: one object, one user, the whole tenant, or the underlying infrastructure?

Rules that keep scores defensible:

- A finding with a public, unauthenticated, remote exploit that yields code execution is Critical.
- An information leak with no onward path is Low or Informational, regardless of how interesting the data looks.
- A scanner hit that will not reproduce is at most Informational; either reproduce it and score it, or drop it.
- Chain severity, not individual component severity: if two Mediums chain into confirmed RCE, the finding is the chain and it scores as RCE.
- Adjust for compensating controls only if you verified they work.
- State the reasoning for any score that is close to a boundary.

## Writing discipline

- Factual and concise. Every claim maps to evidence.
- Past tense for what was done, present for what is true of the system.
- No filler, no marketing language, no dramatic adjectives. Severity comes from the score, not the prose.
- Consistency: same structure, same severity scale, same terminology throughout.
- Proofread for the client's legal and technical reviewers. Remove em-dashes and en-dashes; use periods, commas, colons, parentheses, or plain hyphens.
- Redact real secrets and PII from the report body; reference them securely where the finding requires it.

## Delivery

Export to the agreed format (PDF plus Markdown, or per the SOW), name files per the engagement convention, and transmit over the secure channel specified in the ROE. Include the evidence archive reference and a note on any client-side cleanup performed.
