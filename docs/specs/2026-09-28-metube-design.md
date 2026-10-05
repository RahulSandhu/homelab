# Homelab design — MeTube

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** the 2026-09-28 specs

## Context

A **web UI for `yt-dlp`**: paste a link (YouTube and hundreds of other sites) and
the server downloads it — video, audio, subtitles, whole playlists/channels, plus
**subscriptions** that queue new uploads automatically.

Unlike Stirling PDF (a stateless tool that hands your file straight back), MeTube's
whole point is that the **download lives on the server**: long jobs and
subscriptions keep running when the laptop is off. Collecting the file is then a
normal browser download, and removing the job cleans up the server copy.

## Goals

- Video/audio downloads without leaving the laptop on.
- Files land on a **bounded, separate** disk and can be cleaned up in one action.
- **Tailnet-only.**

## Decision: behind Caddy, at a subpath

MeTube ships **`URL_PREFIX`**, so it can live under a path — the first app in a while
that doesn't need its own port or tailnet node. Route:

```caddyfile
handle /metube* { reverse_proxy metube:8081 }   # no prefix stripping
```

Its HTML uses **relative** asset paths, so the trailing slash matters (the PairDrop
lesson) — verified that `/metube` 302s to `/metube/` and that assets resolve under it.

## Decision: never public

A downloader fetches URLs on your behalf; public, it would be an abuse magnet
(**SSRF** into the LAN, bandwidth, disk). It also has no authentication. So:
tailnet-only, with MeTube's own SSRF guard left **on** and per-download
`yt-dlp` overrides left **off** (that flag can execute commands in the container).

## Decision: a 25 GB staging disk + delete-on-collect

`/srv/metube` (dedicated thin disk). Because the intended flow is
*download → collect → clear*, `DELETE_FILE_ON_TRASHCAN=true` deletes the file when
the job is removed from **Completed** — so the disk stays near-empty.

> `CLEAR_COMPLETED_AFTER` is deliberately **`0` (never)**: an auto-clear would
> combine with the delete-on-trashcan setting and destroy files before they had
> been collected. Deletion only ever follows the operator's action.

> **Update (2026-10-04) — reversed.** The extra `metube-cleanup` script + systemd
> timer was **removed** (it deleted files by `atime`, but left the *Completed* rows,
> which the operator found confusing). Cleanup is now MeTube's own
> `CLEAR_COMPLETED_AFTER=86400` (**seconds** = 24 h) with `DELETE_FILE_ON_TRASHCAN=true`,
> so a Completed job and its file auto-expire together. The trade-off — a file not
> collected inside the window is deleted with its row — is accepted; the window is
> the tuning knob.

## Components

| Component | Image (pinned) | Notes |
| --- | --- | --- |
| MeTube | `ghcr.io/alexta69/metube:2026.09.28` | joins the external `proxy` network; downloads on `/srv/metube`; no host port |

## Risks

| Risk | Mitigation |
| --- | --- |
| **`yt-dlp` going stale** (sites change constantly) | MeTube publishes a new image per `yt-dlp` release → **deliberate bumps every few weeks** (the one service that isn't set-and-forget) |
| Disk filling with downloads | 25 GB staging disk + delete-on-collect |
| SSRF into the LAN | `ALLOW_PRIVATE_ADDRESSES=false` (default kept) |
| Container command execution | `ALLOW_YTDL_OPTIONS_OVERRIDES=false` |
| ToS / legality of downloading | Operator's call; recorded in the stack README |

## Phases

| Phase | What | Owner |
| --- | --- | --- |
| 1 | 25 GB disk → `/srv/metube`; write the stack | agent |
| 2 | Deploy + Caddy route; verify the subpath (page **and** assets) | agent |
| 3 | Dashboard tile (verified via `/api/services`) | agent |
| 4 | Docs, diagram, spec/plan, commit | agent |

## As built

- 25 GB thin disk → `/dev/sde` → ext4 label `metube` → **`/srv/metube`** (fstab by
  UUID). The guest's device names **reordered after a VM reboot** (the OS became
  `/dev/sdb`) — harmless precisely because every mount is by **UUID**.
- Container `metube` (healthy) on the `proxy` network, `PUID/PGID=1000`,
  `URL_PREFIX=/metube`, `DELETE_FILE_ON_TRASHCAN=true`, `CLEAR_COMPLETED_AFTER=0`,
  `MAX_CONCURRENT_DOWNLOADS=3`, SSRF guard on, overrides off.
- Caddy route added; verified **`/metube/` → 200**, assets served with correct
  content types (`text/javascript`, `text/css`) **under the prefix**, and
  `/metube` → 302 → `/metube/`.
- Dashboard tile added and confirmed through `/api/services`.
- **Automatic cleanup (superseded 2026-10-04):** originally a `metube-cleanup`
  script + 15-minute systemd timer deleted a download **once it had been collected**
  (`atime > mtime` on a `strictatime` mount; verified live). It was **removed** —
  it deleted files but left the *Completed* rows, which proved confusing — in favour
  of MeTube's built-in `CLEAR_COMPLETED_AFTER=86400` + `DELETE_FILE_ON_TRASHCAN=true`.
  See the update note above and `stacks/metube/README.md`.
- **Side effect of the work:** the VM's RAM was raised 4 → **6 GB** (it was down to
  ~1.3 GiB free with the whole stack running) and `qemu-guest-agent` was installed,
  so future reboots are graceful rather than a hard reset (which is what this one was).