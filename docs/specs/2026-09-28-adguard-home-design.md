# Homelab design — AdGuard Home (tailnet-only DNS)

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** the 2026-09-28 specs

## Context

The owner wants ad/tracker blocking. The home router is a **Livebox Fibra
(Arcadyan)** whose DNS page states, verbatim:

> *"Los servidores DNS se configuran por el operador y por tu seguridad no se
> pueden modificar en el router."*

The DNS servers handed to LAN clients **cannot be changed** (the fields are
greyed out), and IPv6 DNS is operator-locked too. So a **LAN-wide** filter would
require taking over DHCP entirely — which the owner **explicitly rejected**: it
would put the family's internet behind the homelab and make it the network's DHCP
server.

**Decision: scope ad-blocking to the owner's own tailnet devices.** No router
changes at all; the family's internet is untouched.

## Goals

- Ad/tracker blocking for the owner's devices (**laptop + phone**), **at home and
  away**.
- **Zero router/network changes** — no DHCP takeover, no DNS override.
- Tailnet-only; **no LAN door**; consistent with the repo rules (no `funnel`,
  pinned image, snapshot before change).

## Non-goals

- **Whole-home (LAN-wide) filtering** — impossible here without DHCP takeover
  (rejected).
- Replacing **MagicDNS**. Tailnet names must keep resolving.

## Decision: AdGuard Home (not Pi-hole)

| | **AdGuard Home** | Pi-hole |
| --- | --- | --- |
| Encrypted DNS | **built in** — DoH/DoT upstream *and* server | needs a bolt-on (`cloudflared`) |
| Shape | one Go binary | v6 folded the web server into FTL (closer now) |
| UI / per-client | modern UI, per-client rules, blocked-services presets | classic, groups-based |
| Rule engine | adblock-style **and** hosts lists | hosts-list centric |
| Ecosystem | smaller | **much larger** community |

Chosen for **built-in encrypted upstreams** (queries from the phone cross the
internet) and single-binary simplicity. Pi-hole remains the better pick if
community/guides matter more — noted, not needed here.

## Decision: scope and exposure

- **DNS** is published **only on the VM's tailnet IP**:
  `100.74.164.49:53` (tcp + udp). That means **no LAN door** — nothing on the home
  network can even reach it. It does not clash with `systemd-resolved`, which
  keeps `127.0.0.53:53`.
- **Admin UI**: AdGuard's UI does not support subpaths, so it gets **its own
  port** rather than a Caddy path:

  ```sh
  tailscale serve --bg --https=8443 http://127.0.0.1:3000
  # → https://docker-host.tail91459b.ts.net:8443
  ```

  (`tailscale serve` only permits ports 443 / 8443 / 10000; 443 stays Caddy's.)
- **Tailnet-wide wiring** (owner, in the admin console): set the tailnet's
  **global nameserver** to `100.74.164.49` with *Override local DNS*. Tailscale
  points devices at MagicDNS, which forwards non-tailnet names to AdGuard — so
  **blocking works everywhere and `*.ts.net` still resolves**.
- **The LAN is untouched**: no DHCP change, no router change, family devices keep
  using the ISP's DNS exactly as today.

## Architecture

```
laptop / phone ──(tailnet, from anywhere)──> AdGuard Home  100.74.164.49:53
        │                                          │
        │                                          └──(DoH/DoT upstream)
        └── MagicDNS still resolves *.ts.net

family devices ──> Livebox ──> ISP DNS      (unchanged)
```

## Components

| Component | Image (pinned) | Notes |
| --- | --- | --- |
| AdGuard Home | `adguard/adguardhome:v0.107.79` | `stacks/adguard/`; `100.74.164.49:53` (tcp+udp) + `127.0.0.1:3000`; state in `./work` + `./conf` |

## Risks and notes

- **AdGuard becomes the DNS for the owner's devices.** If the homelab is down,
  *their* resolution breaks (the family's is unaffected). Accepted: the box is
  always on.
- **DoH / Private DNS can bypass it.** Android's *Private DNS* or a browser's
  forced DoH skips AdGuard. Disable those on the devices for full coverage.
- **The compose file hardcodes the tailnet IP** as the published address — stable,
  but an implicit dependency worth knowing when reviewing.
- **Upstreams**: set to a DoH provider in the UI (the container default would be
  Docker's internal resolver → the ISP).
- Not a backup: the config is small and re-creatable; VM 100 snapshots cover it.

## Phases

| Phase | What | Owner |
| --- | --- | --- |
| 0 | Approve this design | owner |
| 1 | Write `stacks/adguard/`, deploy, `tailscale serve --https=8443` | agent |
| 2 | Wizard: admin user + password; **global nameserver** in the Tailscale console | **owner** |
| 3 | Verify: blocking works, `*.ts.net` still resolves | agent + owner |
| 4 | Dashboard tile, docs, diagram, spec "As built", commit | agent |

## As built

- Deployed as `adguard/adguardhome:v0.107.79`; the filter list loaded **176,212 rules**.
- DNS listens on **`100.74.164.49:53` only** — verified with `ss`: no `0.0.0.0:53`
  anywhere, and `systemd-resolved` keeps its `127.0.0.53` stub untouched.
- Admin UI published with **`tailscale serve --https=8443`** →
  `https://docker-host.tail91459b.ts.net:8443`. (`serve` permits only 443/8443/10000
  and 443 is Caddy's; AdGuard's UI has no subpath support, hence its own port.)
- **Blocking verified** from the laptop by querying the tailnet IP directly:

  | query | public resolver (1.1.1.1) | AdGuard |
  | --- | --- | --- |
  | `example.com` | real IP | real IP ✅ resolves |
  | `doubleclick.net` | real IP | **`0.0.0.0`** ✅ blocked |

- **Gotcha (costly):** Homepage's `/` HTML is a **static shell that always contains
  its demo placeholders**. The live dashboard is rendered from `/api/services`.
  Verify Homepage config through the API — **never** by grepping the HTML.
- **Operator steps** (Tailscale admin console): add global nameserver
  `100.74.164.49` and enable *Override local DNS*. Until that is done, only devices
  explicitly pointed at AdGuard are filtered — the LAN is untouched either way.
