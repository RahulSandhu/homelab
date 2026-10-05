# AdGuard Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ad/tracker blocking for the owner's **tailnet devices only** — no router changes, no LAN door, family internet untouched.

**Architecture:** AdGuard Home runs as a container on `docker-host`. Its DNS listens on the **tailnet IP only** (`100.74.164.49:53`), and its admin UI is published on the tailnet via `tailscale serve --https=8443`. The operator adds AdGuard as the **tailnet's global nameserver** in the Tailscale admin console; MagicDNS keeps resolving `*.ts.net`.

**Tech Stack:** Docker Compose, AdGuard Home `v0.107.79`, Tailscale (`serve`), the existing Debian 13 VM.

**Spec:** `docs/specs/2026-09-28-adguard-home-design.md`

## Global Constraints

- **No router changes. No DHCP changes.** The LAN must behave exactly as today.
- **Never `tailscale funnel`** — `serve` only.
- **No LAN door for DNS**: bind `100.74.164.49:53`, never `0.0.0.0:53`.
- **Does not disturb `systemd-resolved`** (`127.0.0.53:53` stays).
- **Image pinned** to `adguard/adguardhome:v0.107.79`. Never `:latest`.
- **`serve` port must be 443 / 8443 / 10000** — 443 belongs to Caddy, so use **8443**.

## Review Focus

- **Family internet is unaffected** — pinned by Task 3's check (router untouched, LAN devices still resolve).
- **No LAN door** — pinned by Task 1 Step 4 (`ss` shows 53 only on `100.74.164.49`).
- **MagicDNS still works** — pinned by Task 4 Step 2 (`*.ts.net` resolves).
- **`systemd-resolved` intact** — pinned by Task 1 Step 4.

---

## Task 1: The stack

**Files:** `stacks/adguard/compose.yaml`, `stacks/adguard/README.md`.

- [ ] **Step 1** — compose: image `adguard/adguardhome:v0.107.79`,
  `restart: unless-stopped`, volumes `./work:/opt/adguardhome/work` +
  `./conf:/opt/adguardhome/conf`, ports `100.74.164.49:53:53/tcp`,
  `100.74.164.49:53:53/udp`, `127.0.0.1:3000:3000`.

- [ ] **Step 2 — deploy**

```sh
scp -r stacks/adguard rahul@192.168.1.60:/tmp/
ssh rahul@192.168.1.60 '
  sudo mkdir -p /opt/adguard/work /opt/adguard/conf
  sudo cp /tmp/adguard/compose.yaml /tmp/adguard/README.md /opt/adguard/
  cd /opt/adguard && sudo docker compose up -d
'
```

- [ ] **Step 3 — container up / listening**

```sh
ssh rahul@192.168.1.60 'docker ps --filter name=adguard --format "{{.Status}}"; docker logs adguard 2>&1 | tail -5'
```
Expected: up; the install wizard listening on `:3000`.

- [ ] **Step 4 — REVIEW FOCUS: no LAN door, resolved intact**

```sh
ssh rahul@192.168.1.60 'sudo ss -lntup | grep -E ":53 |:3000"'
```
Expected: `100.74.164.49:53` (tcp+udp) and `127.0.0.1:3000`; **no** `0.0.0.0:53`; `systemd-resolved` still on `127.0.0.53`.

---

## Task 2: Serve the admin UI on the tailnet

- [ ] **Step 1 — expose on 8443** (does not disturb 443 → Caddy)

```sh
ssh rahul@192.168.1.60 'sudo tailscale serve --bg --https=8443 http://127.0.0.1:3000 && tailscale serve status'
```
Expected: both mappings listed — `443 → localhost:8090`, `8443 → localhost:3000`.

- [ ] **Step 2 — verify**

```sh
curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net:8443
curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net/
```
Expected: `200` for the wizard, and the dashboard still `200` (443 untouched).

---

## Task 3: First run + tailnet wiring *(owner)*

- [ ] **Step 1 (owner)** — open `https://docker-host.tail91459b.ts.net:8443` and
  complete the wizard: set the **admin username + password**, and keep the web
  interface on port **3000** (the port mapping depends on it).
- [ ] **Step 2 (owner)** — Settings → DNS settings → **Upstream DNS servers**:
  replace the default with a DoH provider, e.g.
  `https://dns.quad9.net/dns-query` (and/or `https://dns.cloudflare.com/dns-query`).
- [ ] **Step 3 (owner)** — Tailscale admin console → **DNS** → *Nameservers*:
  add **Global nameserver** `100.74.164.49` and enable **Override local DNS**.
- [ ] **Step 4** — confirm the family is untouched: a device *not* on the tailnet
  still resolves via the ISP (no router change was made).

---

## Task 4: Verify

- [ ] **Step 1 — blocking works** (from the laptop, once the global nameserver is set)

```sh
dig +short doubleclick.net @100.74.164.49      # expect 0.0.0.0 / empty
dig +short example.com @100.74.164.49          # expect a real answer
```
- [ ] **Step 2 — REVIEW FOCUS: MagicDNS still resolves**

```sh
ssh -o BatchMode=yes rahul@docker-host 'true'   # resolves by name from the laptop
tailscale status --json | grep -c TailscaleIPs  # sanity
```
- [ ] **Step 3 — query log** shows the laptop/phone as clients in the AdGuard UI.

---

## Task 5: Dashboard, docs, commit

- [ ] **Step 1** — Homepage tile → `https://docker-host.tail91459b.ts.net:8443`.
- [ ] **Step 2** — `docs/setup.md` section; `docs/access-matrix.md` row + note
  (tailnet-only DNS; LAN untouched); `docs/schemas/homelab.dot` (+ AdGuard);
  `README.md`; `AGENTS.md` (DNS rule: bind DNS to the tailnet IP, never 0.0.0.0).
- [ ] **Step 3** — fill the spec's "As built"; commit.

---

## Self-review

- The owner's touchpoints are exactly Task 3 (wizard, upstreams, global nameserver).
- The review-focus items are each pinned to a concrete step.
- The LAN/host constraints (no router change, no LAN door, resolved intact) each
  have an explicit verification.
