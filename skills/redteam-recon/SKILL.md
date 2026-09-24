---
name: redteam-recon
description: "Reconnaissance and attack-surface mapping methodology, passive first then active. Use for OSINT, subdomain and asset discovery, DNS enumeration, port and service scanning, fingerprinting, TLS analysis, and cloud exposure. Triggers: recon, reconnaissance, asset discovery, subdomain enumeration, port scan, service fingerprint, attack surface, OSINT, shodan, nmap."
---

# Reconnaissance

Recon runs only after the redteam-roe gate passes and the target assets are confirmed in scope. Passive first; active only on approved ranges.

## Phase discipline

1. Passive OSINT: gather everything without touching the target's own infrastructure.
2. Active enumeration: direct queries to in-scope assets (DNS, ports, services).
3. Correlation: normalize into one asset inventory and map the attack surface.

Keep passive and active separated so a passive-only engagement never emits a packet to the target.

## Passive OSINT

- Search engines, certificate transparency logs, paste sites, code hosts, job postings, and breach data for leaked names, emails, subdomains, and keys.
- Read the client's own public footprint: DNS records, WHOIS, ASN and netblocks, MX/SPF/DMARC, and public cloud buckets or storage accounts.
- `shodan`: use internet-wide scan data to see what the target already exposes without probing it. Search by organization, netblock, hostname, and TLS certificate. Pull banners, ports, products, and historical data. Shodan is passive from the target's perspective and is the preferred first look at exposed services.
- `cve`: correlate discovered products and versions against known CVEs. Feed banners and version strings in, get candidate vulnerabilities with CVSS and references out. This drives what the later phases prioritize.
- Record every artifact with source and timestamp. Do not treat a search-engine hit as confirmed exposure until an active check confirms it (when active is permitted).

## Active enumeration

- Subdomain and asset discovery: certificate transparency, DNS brute force against wordlists, zone transfer attempts where permitted, and permutation of known names. Validate discovered names resolve before scanning them.
- DNS: A/AAAA, CNAME chains, MX, TXT (SPF, DKIM, verification tokens), NS, SOA. CNAME chains often reveal third-party SaaS tenancy that must be scope-checked.
- `nmap`: port and service discovery on the approved ranges. Start with a fast host-discovery pass, then a targeted service/version scan on live hosts, then targeted NSE scripts. Choose timing and evasion settings per the agreed stealth level. Example workflow: host discovery, then `-sV -sC` on discovered ports, then version-specific NSE.
- `pentest`: use the pentest toolkit for service-level enumeration tasks that complement nmap, covering protocol banners, default credentials checks, and light service probing where authorized.
- Fingerprinting: identify exact products, versions, frameworks, and OS from banners, HTTP headers, favicon hashes, TLS fingerprints (JA3/JARM), and error pages.
- TLS: certificate subjects and SANs, issuer, validity, weak protocol/cipher support, and misconfigurations. SANs are a subdomain source.
- Cloud exposure: public object storage, misconfigured buckets, exposed metadata endpoints, forgotten dev/staging hosts, and CI/CD artifacts. Check for both public-read and public-write only where write testing is explicitly authorized.

## OPSEC notes

- Passive tools leave no trace on the target. Active scans do. Assume the client's IDS/SIEM logs every active packet; that is often a deliberate detection test.
- Prefer distributed or trusted third-party data (Shodan, CT logs) over direct probing when stealth matters.
- Rate-limit active scans to the agreed threshold. Blast the network only when loud is intended.
- Source IP hygiene: use the agreed testing egress. Do not scan from personal or unattributed infrastructure unless the ROE says so.
- Subdomain discovery can tip off defenders via DNS canaries. Coordinate before brute force on sensitive targets.

## Output format

Produce two artifacts in the engagement directory.

### Asset inventory

One row per asset:

| Asset | Type | In scope (ref) | Resolved IP/ASN | Ports/services | Product/version | TLS notes | Cloud | Source | Confidence |
|-------|------|----------------|-----------------|----------------|-----------------|-----------|-------|--------|------------|

Type is one of domain, host, IP, range, API, mobile app, cloud account, or person.

### Findings

One entry per issue, ordered by likely impact:

- Title: short and specific.
- Asset(s): exact host/URL/IP.
- Evidence: raw output excerpt, banner, or screenshot reference.
- CVE / weakness: where applicable, with CVSS.
- Why it matters: the exposure path it enables.
- Next step: the phase that should pursue it (web, exploit) and any scope check required.

Close the recon phase with a coverage statement: what was enumerated, what was excluded, and what could not be reached.
