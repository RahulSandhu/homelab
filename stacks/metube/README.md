# MeTube

A web UI for **`yt-dlp`**: paste a link (YouTube and hundreds of other sites) and
it downloads to the server — video, audio, subtitles, whole playlists and channels,
plus **subscriptions** that queue new uploads as they appear.

Served at **`https://docker-host.tail91459b.ts.net/metube/`** — behind Caddy,
**tailnet-only**. It is never public: a public MeTube would let strangers make your
server fetch arbitrary URLs.

## The workflow (and the cleanup)

1. Paste links → they download **on the server** (so they keep going while your
   laptop is off, and subscriptions run unattended).
2. When a job finishes, click **download** in the UI. With your browser set to
   *"Always ask where to save"*, you get a save dialog — pick anywhere on your machine.
3. MeTube then tidies up after itself: **24 h** after a job completes, its row
   **leaves *Completed*** and — because `DELETE_FILE_ON_TRASHCAN=true` — its
   **file is deleted from the disk** too. Clearing a job by hand does the same
   thing immediately.

> **`CLEAR_COMPLETED_AFTER` is measured in *seconds*, not minutes** (`86400` = 24 h
> here), and it covers **finished *and* failed** jobs. This is the entire cleanup —
> there is no separate script or timer. The trade-off: anything you haven't
> collected within the window is deleted along with its row, so keep the window
> longer than your usual collect time (or grab files before it lapses).

## Cookies — age checks and login-only sites

Some downloads need **your** cookies (YouTube age-restricted videos, members-only
posts, …). MeTube reads a file called **`cookies.txt` in its state dir** —
`/srv/metube/downloads/.metube/cookies.txt` — for every download, so there's no need
to use the UI's upload button.

**Treat that file as a secret.** It is a live browser-session jar (YouTube/Google,
X, Reddit, Instagram, TikTok, Twitch, Kick…), so it is:

- **filtered to media sites only** — *not* a full Firefox export: your router,
  pcloud, this VM, and Gmail/Drive/Passwords cookies are **not** on the server;
- owned `1000:1000`, mode `600`, and outside the repo (never committed);
- reachable only over the tailnet, like everything else here.

**Refresh** it every few months, or when a download starts asking you to sign in
(cookies expire, and YouTube rotates its session cookies). From the laptop:

```sh
stacks/metube/refresh-cookies.sh
```

It exports the Firefox profile (the same one `~/desktop/projects/yt-downloader`
uses), keeps only the media domains, pushes the jar to the VM and restarts MeTube.

- Verify: `sudo docker exec -u 1000 metube head -1 /downloads/.metube/cookies.txt`
- Need cookies for a site the filter drops? Add its domain to `KEEP_DOMAINS` at the
  top of `refresh-cookies.sh` and re-run.

## Storage

`/srv/metube` — a dedicated **25 GB** disk (`/srv/metube/downloads` is the only
thing MeTube writes to). Deliberately small, because it's a staging area you empty.

## Operate

```sh
docker compose ps
docker compose logs -f
docker compose restart

# grab a file without the UI, if ever needed:
docker exec -it metube sh -c 'cd /downloads && yt-dlp <url>'
```

## Hardening (set in `compose.yaml`)

| Setting | Value | Why |
| --- | --- | --- |
| `ALLOW_PRIVATE_ADDRESSES` | `false` | SSRF guard: it will not fetch internal/private addresses |
| `ALLOW_YTDL_OPTIONS_OVERRIDES` | `false` | that flag allows running commands inside the container |
| `DELETE_FILE_ON_TRASHCAN` | `true` | clear/expire a job → delete its file |
| `CLEAR_COMPLETED_AFTER` | `86400` | auto-expire Completed rows after 24 h (**seconds**), deleting the file with them |
| `MAX_CONCURRENT_DOWNLOADS` | `3` | keeps it from hammering the box |
| `URL_PREFIX` | `/metube` | lets Caddy route it as a subpath |

## ⚠️ Maintenance — unlike the rest of the stack

`yt-dlp` has to keep up with the sites, and MeTube publishes a **new image for every
`yt-dlp` release**. So this is the one service that wants a **deliberate version
bump every few weeks**:

```sh
# bump the tag in compose.yaml, then
cd /opt/metube && sudo docker compose pull && sudo docker compose up -d
```

If you'd rather not think about it, `YTDL_NIGHTLY_UPDATE_TIME=03:00` makes it
upgrade `yt-dlp` inside the container and restart daily — at the cost of the tool no
longer being pinned.

**Legal note:** `yt-dlp` targets sites whose terms of service generally prohibit
downloading. That's the operator's call; this README just says so out loud.
