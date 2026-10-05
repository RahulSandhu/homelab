# Homelab design — Stirling PDF

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** the 2026-09-28 specs

## Context

A self-hosted **PDF toolbox** (merge, split, compress, rotate, OCR, convert,
sign, redact, protect) so PDFs don't have to be uploaded to random websites.
The service is **stateless**: files are processed in temp and deleted. It holds
no library and no database — the only thing that persists is its own settings.

## Goals

- PDF operations from any tailnet device, without third-party websites.
- **Nothing persisted** (no document store to protect or back up).
- Tailnet-only; consistent with the repo rules (no LAN door, pinned image).

## Non-goals

- Being a document *archive* (that would be a DMS such as Paperless-ngx —
  deliberately not chosen: it needs a database, Redis, storage, and a backup
  story of its own).

## Decision: the standard `3.0.0` variant

| Tag | Notes |
| --- | --- |
| **`3.0.0`** ⭐ | full toolbox **including OCR** — what we run |
| `3.0.0-fat` | adds LibreOffice/Calibre → Office → PDF conversions |
| `3.0.0-ultra-lite` | stripped down, no OCR |

Chosen for OCR at a moderate image size. `-fat` is a one-word change if Office
conversions are ever wanted.

## Decision: its own tailnet port (not a Caddy subpath)

Stirling's UI is a SPA that hardcodes **`<base href="/" />`**, so every asset
resolves against the URL **root**. Under a Caddy path (`/pdf`) those requests hit
the dashboard instead of the app — the same class of failure as
PairDrop/Vaultwarden/AdGuard (apps that cannot live under a subpath).

`tailscale serve` only permits ports **443 / 8443 / 10000**; 443 is Caddy and 8443
is AdGuard, so Stirling takes **10000**:

```
https://docker-host.tail91459b.ts.net:10000/
```

## Architecture

```
tailnet device ──HTTPS──> tailscale serve :10000
                              │
                              ▼
                     127.0.0.1:8081  (localhost only — no LAN door)
                              │
                              ▼
                     stirling-pdf container :8080  (stateless; /configs only)
```

Nothing is written to disk except `settings.yml`.

## Components

| Component | Image (pinned) | Notes |
| --- | --- | --- |
| Stirling PDF | `stirlingtools/stirling-pdf:3.0.0` | joins the external `proxy` network; publishes `127.0.0.1:8081`; `./data` → `/configs` |

## Risks and notes

- **Stateless by design** — no documents are retained, so there is nothing to
  back up and no data to leak from this service.
- **Serve ports are now exhausted** (443 Caddy, 8443 AdGuard, 10000 Stirling).
  A future subpath-hostile service needs its **own tailnet name** via a Tailscale
  sidecar — or to share a port deliberately.
- OCR is CPU-bound; fine on 2 vCPU for occasional use.

## Phases

| Phase | What | Owner |
| --- | --- | --- |
| 1 | `stacks/stirling-pdf/`, deploy, publish on `:10000` | agent |
| 2 | Verify the UI **and an asset at the URL root** | agent |
| 3 | Dashboard tile (verified via `/api/services`, not the HTML) | agent |
| 4 | Docs, diagram, commit | agent |

## As built

- Deployed `stirlingtools/stirling-pdf:3.0.0`; container **healthy**; app logging
  `Stirling-PDF Started` on `:8080`.
- Published `127.0.0.1:8081` → `tailscale serve --https=10000` →
  **`https://docker-host.tail91459b.ts.net:10000/`**.
- Verified: UI **200**, and an asset at the root (`/modern-logo/favicon.ico`)
  **200 `image/x-icon`** — confirming the root-path mount is correct (had we used
  a subpath, the `<base href="/">` would have broken every asset).
- Dashboard tile added and confirmed through **`/api/services`** (the HTML shell
  contains Homepage's demo placeholders and must not be used to verify config).