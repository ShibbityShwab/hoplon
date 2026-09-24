---
name: redteam-web
description: "Web application testing methodology mapped to OWASP WSTG categories, driven by the burp, nuclei, ffuf, sqlmap, and pentest MCP servers. Use for HTTP/service testing, authentication and session analysis, injection, SSRF, broken access control, and deserialization. Triggers: web app test, wstg, owasp, burp, nuclei, ffuf, sqlmap, injection, ssrf, idor, access control, xss, deserialization."
---

# Web Application Testing

Requires the redteam-roe gate. Confirm each host and endpoint is in scope before sending payloads. Automated scanners send a lot of traffic; match intensity to the agreed stealth level.

## Workflow

1. Map the application: crawl, sitemap, parameter inventory, technology fingerprint.
2. Content and path discovery: `ffuf`.
3. Automated vulnerability sweep: `nuclei`.
4. Manual and semi-automated analysis through `burp` (proxy, repeater, intruder).
5. Targeted injection and logic testing: `sqlmap`, `pentest`.
6. Evidence capture throughout.

## Tool mapping

- `burp`: primary manual workbench. Proxy browser and tool traffic, inspect and replay requests in Repeater, fuzz with Intruder, and use the scanner where licensed. Use it to confirm findings and to craft precise proof-of-concept requests.
- `ffuf`: content, directory, parameter, and virtual-host discovery, plus fuzzing for hidden endpoints, files, and parameters. Always filter noise (status, size, word count) and keep wordlists engaged with the target's stack.
- `nuclei`: templated, fast sweep for known CVEs, misconfigurations, exposed panels, default credentials, and takeovers. Run low-severity/safe templates first, then targeted tags. Treat every hit as a lead to reproduce manually, not a confirmed finding.
- `sqlmap`: SQL injection detection and exploitation. Start with detection and DBMS fingerprinting. Never use OS shell, file read/write, or data dump options without explicit destructive-action approval per ROE.
- `pentest`: general-purpose service and web probing for enumeration and light validation tasks that complement the above.

## OWASP WSTG coverage

Work the categories explicitly and note which were tested.

- Information gathering: WSTG-INFO. Fingerprinting, metadata leakage, application entry points, error handling.
- Configuration and deployment: WSTG-CONF. Server config, backup/leftover files, HTTP methods, security headers, cross-domain policy.
- Identity management: WSTG-IDNT. Registration, account provisioning, account enumeration.
- Authentication: WSTG-ATHN. Credential transport, default accounts, lockout, MFA bypass, password policy.
- Authorization: WSTG-ATHZ. Directory traversal, bypassing authorization schemes, IDOR, privilege escalation, missing function-level access control.
- Session management: WSTG-SESS. Cookie attributes, session fixation, CSRF, logout/session timeout, JWT weaknesses (alg confusion, none, weak keys, kid injection).
- Input validation: WSTG-INPV. XSS (reflected, stored, DOM), SQL/NoSQL/ORM injection, command injection, SSTI, XXE, LDAP/XPath injection, HTTP parameter pollution, request smuggling, deserialization (Java/PHP/.NET/Python), mass assignment.
- Error handling: WSTG-ERRH. Stack traces, verbose errors, information in responses.
- Cryptography: WSTG-CRYP. Weak TLS, padding oracle, weak hashing, cleartext storage.
- Business logic: WSTG-BUSL. Workflow bypass, replay, price/quantity tampering, race conditions.
- Client-side: WSTG-CLNT. DOM XSS, postMessage, client storage, open redirect, clickjacking.
- API: WSTG-APIT. REST/GraphQL testing: introspection, authorization per field, batching, rate limits.

### High-value focus areas

- Access control: IDOR and horizontal/vertical privilege issues are the highest-yield class. Enumerate object identifiers and roles, then test across accounts.
- Injection: validate every sink with a minimal, safe payload first; escalate only within ROE.
- SSRF: test server-side URL fetchers with in-scope callback infrastructure. Cloud metadata endpoints (169.254.169.254, IMDSv2) only where the provider is in scope.
- Deserialization: identify serialized blobs in cookies, parameters, and headers; test with benign type-confusion payloads before any code execution attempt.

## Evidence capture rules

- Store the exact request and response for every confirmed finding (Burp export, raw HTTP), including headers, cookies, and the parameter that triggered it.
- Capture a minimal, reproducible proof: the fewest requests that demonstrate impact. Prefer a harmless marker (a reflected nonce, a time delay, a boolean difference) over real damage.
- Screenshot the rendered proof (for example, XSS alert or admin panel access) with a timestamp visible.
- Record the tool, version, and command/template used.
- For automated hits, attach the template or fuzzing output and the manual reproduction that confirmed it. Never report a scanner hit as confirmed without reproduction.
- Redact real PII, tokens, and secrets from evidence copies that leave the engagement directory.

## Output

Per finding: title, affected endpoint(s), class (WSTG ID), reproduction steps with requests, evidence reference, impact, and remediation direction. Hand off to redteam-report for the client-facing write-up and to redteam-exploit when a finding needs a working proof of impact.
