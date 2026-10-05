# Stirling PDF — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tailnet-only, stateless PDF toolbox (merge/split/compress/OCR/convert/sign/redact) with a dashboard tile.

**Architecture:** One container on `docker-host` joining the external `proxy` network, publishing `127.0.0.1:8081` (localhost only). `tailscale serve --https=10000` exposes it at the URL **root**, because the UI hardcodes `<base href="/" />` and cannot live under a Caddy subpath.

**Tech Stack:** Docker Compose, `stirlingtools/stirling-pdf:3.0.0`, Tailscale `serve`.

**Spec:** `docs/specs/2026-09-28-stirling-pdf-design.md`

## Global Constraints

- **Never `tailscale funnel`.** `serve` only — this stays tailnet-only.
- **No LAN door**: the published port is bound to `127.0.0.1`, never `0.0.0.0`.
- **Image pinned** to `3.0.0`. Never `:latest`.
- **Root URL only** — a subpath will break the SPA (`<base href="/" />`).
- `serve` ports are limited to 443/8443/10000; 443 and 8443 are taken, so use **10000**.

## Review Focus

- **No LAN door** — pinned by Task 1 Step 3 (`ss` shows 8081 on `127.0.0.1` only).
- **Assets load at the URL root** — pinned by Task 2 Step 2 (an asset fetch must
  return its real content-type, **not** HTML from the dashboard).
- **Other services undisturbed** — pinned by Task 2 Step 3.
- **Dashboard verified via the API** — pinned by Task 4 Step 2.

---

## Task 1: The stack

**Files:** `stacks/stirling-pdf/compose.yaml`, `stacks/stirling-pdf/README.md`.

- [ ] **Step 1** — compose: image `stirlingtools/stirling-pdf:3.0.0`,
  `restart: unless-stopped`, `TZ`, volume `./data:/configs`, ports
  `127.0.0.1:8081:8080`, network `proxy` (external).

- [ ] **Step 2 — deploy**

```sh
scp -r stacks/stirling-pdf rahul@docker-host:/tmp/
ssh rahul@docker-host '
  sudo mkdir -p /opt/stirling-pdf/data
  sudo cp /tmp/stirling-pdf/compose.yaml /tmp/stirling-pdf/README.md /opt/stirling-pdf/
  sudo chown -R 1000:1000 /opt/stirling-pdf
  cd /opt/stirling-pdf && sudo docker compose up -d
'
```

- [ ] **Step 3 — wait for the Java app, then check (REVIEW FOCUS: no LAN door)**

```sh
sleep 35
ssh rahul@docker-host 'docker ps --filter name=stirling --format "{{.Status}}"; sudo ss -lntp | grep 8081'
```
Expected: `healthy`; the listener bound to **`127.0.0.1:8081`** only.

---

## Task 2: Publish on the tailnet (root URL)

- [ ] **Step 1**

```sh
ssh rahul@docker-host 'sudo tailscale serve --bg --https=10000 http://127.0.0.1:8081 && tailscale serve status'
```
Expected: three mappings listed — 443 → Caddy, 8443 → AdGuard, **10000 → 127.0.0.1:8081**.

- [ ] **Step 2 — verify the UI *and an asset at the root* (REVIEW FOCUS)**

```sh
curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net:10000/
curl -sk -o /dev/null -w "%{http_code} %{content_type}\n" https://docker-host.tail91459b.ts.net:10000/modern-logo/favicon.ico
```
Expected: `200`; and the asset returns **a real content-type** (e.g.
`image/x-icon`) — if it returned HTML, we'd be seeing the dashboard and the
subpath/root decision would be wrong.

- [ ] **Step 3 — nothing else disturbed (REVIEW FOCUS)**

```sh
curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net/
curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net:8443/login.html
```
Expected: `200` and `200`.

---

## Task 3: Dashboard tile

- [ ] **Step 1** — append to `stacks/homepage/config/services.yaml`:
  `Stirling PDF` → `https://docker-host.tail91459b.ts.net:10000/`, icon
  `stirling-pdf`; deploy and recreate Homepage.

---

## Task 4: Verify the tile **the right way**

- [ ] **Step 1 — NEVER verify Homepage by its HTML** (the shell always contains the
  demo placeholders). Use the API:

```sh
curl -sk -H "Host: docker-host.tail91459b.ts.net" https://docker-host.tail91459b.ts.net/api/services | grep -o '"name":"[^"]*"'
```
- [ ] **Step 2 (REVIEW FOCUS)** — expected: the tile list including **Stirling PDF**.

---

## Task 5: Docs, diagram, commit

- [ ] **Step 1** — `docs/setup.md`: environment row + a Stirling section (stateless;
  root-URL requirement; port 10000).
- [ ] **Step 2** — `docs/access-matrix.md`: a Services row.
- [ ] **Step 3** — `docs/schemas/homelab.dot`: add Stirling PDF (its own port, not
  behind Caddy); `make schemas`.
- [ ] **Step 4** — `README.md`: add `stacks/stirling-pdf/`.
- [ ] **Step 5** — `AGENTS.md`: note that the `serve` ports are exhausted and that
  subpath-hostile apps need their own name (sidecar) or a dedicated port.
- [ ] **Step 6** — fill the spec's "As built"; commit.

---

## Self-review

- The one genuinely risky decision (subpath vs root) is pinned by Task 2 Step 2,
  which would catch a wrong choice (HTML instead of an asset).
- The Homepage verification trap is called out explicitly in Task 4.
- No owner touchpoints: Stirling PDF needs no wizard, no auth key, no settings.
