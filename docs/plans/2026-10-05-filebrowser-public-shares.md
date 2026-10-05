# Public Filebrowser share links — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give an off-tailnet recipient a read-only link to a folder in `/srv/backup`, served by the existing Filebrowser through a route-filtering gate on its own funneled tailnet node — without exposing the Filebrowser login or the rest of the backup.

**Architecture:** A new stack (`stacks/filebrowser-share/`) runs a Tailscale sidecar (`fileshare` node) plus a Caddy gate that shares the sidecar's netns. The gate allows only share-related paths through to the existing `filebrowser:80` (reached over the external `proxy` network) and `404`s everything else. Funnel on the new node only publishes the gate. No data is copied; the shared folder is the live `/srv/backup` path.

**Tech Stack:** Docker Compose, Tailscale (`tailscale/tailscale:v1.102.4`), Caddy (`caddy:2.11.4-alpine`), FileBrowser Quantum (`gtstef/filebrowser:1.5.6-stable`).

**Spec:** `docs/specs/2026-10-05-filebrowser-public-shares-design.md`

## Global Constraints

- **Nothing is public except the two deliberate funneled nodes** (`zipline`, and now `fileshare`). **Never funnel `docker-host`** — copy this rule verbatim into any doc you touch.
- **Images stay pinned.** Do not introduce `:latest`. Reuse the exact tags above.
- **No real secrets committed.** `TS_AUTHKEY` lives only in a git-ignored `.env`; only `.env.example` is tracked.
- **Escape `$` as `$$`** in any Compose `.env` value Docker would interpolate (not expected here, but applies).
- **Filebrowser stays read-only**: `ro` bind mount *and* permissions (`modify`/`create`/`delete` false).
- **Verify public reachability from a device with Tailscale OFF** — a tailnet device proves nothing.
- **Commit only the files this plan touches.** The repo currently has unrelated uncommitted work (MeTube, AdGuard, print-scan); never `git add -A`.
- Conventional-commit prefixes (`feat:`, `fix:`, `docs:`, `chore:`).

## Review Focus

Failure modes the spec implies but no test fully covers — watch each explicitly during review:

1. **Caddy matcher prefix confusion / path traversal** — `/files/static` must not be broadenable to `/files/static.../api`, and `..` segments must not reach `/files/api/*`. The gate uses an explicit allowlist; confirm `path` matcher semantics on the pinned Caddy.
2. **Tailnet leakage through the new node** — the `fileshare` sidecar must reach *only* `filebrowser` on `proxy`, never other services, and its funnel must expose *only* the gate (`:8080`).
3. **Share-token enumeration** — a share link is a bearer secret; the gate must not expose share listing or any auth/admin route.
4. **Live-mirror mutation mid-download** — `rclone sync` can delete a file the recipient is reading; behavior should be a clean failure, not a hang.
5. **Funnel/ACL misconfiguration** — forgetting the `nodeAttrs` grant leaves funnel non-functional; adding `docker-host` would publish everything.

## File Structure

- `stacks/filebrowser-share/compose.yaml` — **create** — sidecar + gate services.
- `stacks/filebrowser-share/Caddyfile` — **create** — the allowlist gate.
- `stacks/filebrowser-share/.env.example` — **create** — `TS_AUTHKEY` placeholder.
- `stacks/filebrowser-share/README.md` — **create** — deploy/operate/rollback.
- `stacks/filebrowser/config/config.yaml` — **modify** — enable `share`.
- `.gitignore` — **modify** — ignore `stacks/filebrowser-share/ts-state/`.
- `AGENTS.md` — **modify** — amend the public rule (git-ignored, local-only).
- `docs/setup.md` — **modify** — promote the DRAFT section to final.
- `docs/access-matrix.md` — **modify** — promote the DRAFT section to final.
- `docs/schemas/homelab.dot` — **modify** — add the `fileshare` node.
- `README.md`, `stacks/filebrowser/README.md` — **modify** — note sharing.
- `docs/specs/2026-10-05-filebrowser-public-shares-design.md` — **modify** — mark implemented + "As built".

---

### Task 1: Enable Filebrowser sharing and discover the share route set

**Files:**
- Modify: `stacks/filebrowser/config/config.yaml`
- Modify (on VM): `/opt/filebrowser/config/config.yaml` (copied from the repo)

**Interfaces:**
- Consumes: the running `filebrowser` instance on `docker-host`.
- Produces: the exact **route allowlist** (list of path prefixes) that a share page requests, consumed by Task 2's `Caddyfile`; and a confirmed way to grant `share`.

> **This task requires the owner** for one step (creating a test share in the UI, or supplying the admin password so the API can do it).

- [ ] **Step 1: Enable the `share` permission**

In `stacks/filebrowser/config/config.yaml`, set `share: true` under `userDefaults.permissions` (keep `admin`, `modify`, `create`, `delete`, `api` false and `download` true). If Quantum 1.5.6 does not apply `userDefaults` to the *existing* admin user, grant `share` to `admin` via the admin UI (Settings → Users) instead, and record which mechanism worked.

- [ ] **Step 2: Apply on the VM and restart**

```sh
scp stacks/filebrowser/config/config.yaml rahul@docker-host:/tmp/config.yaml
ssh rahul@docker-host 'sudo cp /tmp/config.yaml /opt/filebrowser/config/config.yaml && cd /opt/filebrowser && sudo docker compose restart'
```

Expected: `docker-host` serves `/files` again; the admin can now see a **Share** action.

- [ ] **Step 3: Create a test share (owner) and capture its URL**

Owner creates a share of a small test folder at `https://docker-host.tail91459b.ts.net/files/` and provides the resulting `.../files/share/<token>` URL.

- [ ] **Step 4: Enumerate the routes the share page needs**

```sh
# from the laptop, on the tailnet
SHARE='https://docker-host.tail91459b.ts.net/files/share/<token>'
curl -sS "$SHARE" -o /tmp/share.html
grep -oE '(/files/[a-zA-Z0-9._/-]+)' /tmp/share.html | sort -u      # asset + API hints
curl -sS -o /dev/null -w '%{http_code}\n' "$SHARE"                  # page itself
```

Record every distinct `/files/...` path the page references (assets, share API, download endpoint). Try a folder listing and a file download.

- [ ] **Step 5: Confirm 1.5.6 share options and write the allowlist**

Note which share options exist in this version (expiry, password, download limit, disable-download). Write the final allowlist into the spec's open-questions table and carry it to Task 2.

Expected deliverable: e.g. `@share path /files/share/* /files/static/* /files/api/public/*` — **replaced by the empirically observed set**, not the hypothesis.

- [ ] **Step 6: Commit**

```bash
git add stacks/filebrowser/config/config.yaml
git commit -m "feat(filebrowser): enable read-only public share permission"
```

---

### Task 2: Author the `filebrowser-share` stack

**Files:**
- Create: `stacks/filebrowser-share/compose.yaml`
- Create: `stacks/filebrowser-share/Caddyfile`
- Create: `stacks/filebrowser-share/.env.example`
- Create: `stacks/filebrowser-share/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: the route allowlist from Task 1 (Step 5); the external `proxy` Docker network; `filebrowser:80` by DNS name.
- Produces: services **`fileshare-ts`** (container `fileshare-ts`, hostname `fileshare`) and **`share-gate`** (container `share-gate`, listens `:8080` in the sidecar netns), consumed by Tasks 3–4.

- [ ] **Step 1: Write `compose.yaml`**

```yaml
name: filebrowser-share

services:
  # Own tailnet node so the funnel is scoped here alone — never to docker-host.
  fileshare-ts:
    image: tailscale/tailscale:v1.102.4
    container_name: fileshare-ts
    hostname: fileshare
    restart: unless-stopped
    environment:
      TS_AUTHKEY: ${TS_AUTHKEY}
      TS_STATE_DIR: /var/lib/tailscale
      TS_USERSPACE: "false"
    volumes:
      - ./ts-state:/var/lib/tailscale
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    networks:
      - proxy

  # Shares the sidecar netns; the gate is the only thing the funnel can reach.
  share-gate:
    image: caddy:2.11.4-alpine
    container_name: share-gate
    restart: unless-stopped
    network_mode: "service:fileshare-ts"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    depends_on:
      fileshare-ts:
        condition: service_started

networks:
  proxy:
    external: true
```

- [ ] **Step 2: Write `Caddyfile`** (allowlist = Task 1 output; below is the hypothesis to replace)

```caddyfile
{
    auto_https off
}

:8080 {
    @share path /files/share/* /files/static/* /files/api/public/*
    handle @share {
        reverse_proxy filebrowser:80
    }
    handle {
        respond 404
    }
}
```

- [ ] **Step 3: Write `.env.example`**

```sh
# Copy to .env (git-ignored). Never commit real values.
# Tailscale auth key for the "fileshare" node.
# Admin console -> Settings -> Keys: Reusable ON, Ephemeral OFF, no tags.
TS_AUTHKEY=
```

- [ ] **Step 4: Write `README.md`** — mirror `stacks/zipline/README.md`: where things live (node `fileshare`, URL, source `ro`), deploy, the funnel on/off commands, "never funnel `docker-host`", and the off-tailnet verification note.

- [ ] **Step 5: Ignore sidecar state**

Append to `.gitignore`:

```gitignore
# Filebrowser-share Tailscale sidecar state (node key material)
stacks/filebrowser-share/ts-state/
```

- [ ] **Step 6: Validate**

```sh
cd stacks/filebrowser-share && docker compose config >/dev/null && echo OK
```

Expected: `OK` (no YAML/interpolation errors).

- [ ] **Step 7: Commit**

```bash
git add stacks/filebrowser-share .gitignore
git commit -m "feat(filebrowser-share): add tailnet sidecar + share-only Caddy gate"
```

---

### Task 3: Deploy tailnet-only and verify gate behavior

**Files:**
- No repo change (deploy from `stacks/filebrowser-share/`).

**Interfaces:**
- Consumes: Task 2 stack; `TS_AUTHKEY` (owner).
- Produces: a running `fileshare` node reachable on the tailnet at `https://fileshare.tail91459b.ts.net`, with the gate enforcing the allowlist — consumed by Task 4.

- [ ] **Step 1: Owner creates a Tailscale auth key** (reusable ON, ephemeral OFF, no tags).

- [ ] **Step 2: Deploy (no funnel yet)**

```sh
scp -r stacks/filebrowser-share rahul@docker-host:/tmp/fb-share
ssh rahul@docker-host 'sudo mkdir -p /opt/filebrowser-share && sudo cp -r /tmp/fb-share/* /opt/filebrowser-share/ && cd /opt/filebrowser-share && cp .env.example .env && sudo mkdir -p ts-state && echo "EDIT .env (TS_AUTHKEY) then run: sudo docker compose up -d"'
```

Fill `.env`, then `sudo docker compose up -d` and confirm the sidecar joined:

```sh
docker exec fileshare-ts tailscale status      # node "fileshare" present; key expiry disabled in console
```

- [ ] **Step 3: Verify the gate allows the share and blocks everything else** (from the laptop, on the tailnet)

```sh
BASE='https://fileshare.tail91459b.ts.net'
curl -sS -o /dev/null -w 'share  %{http_code}\n' "$BASE/files/share/<token>"   # expect 200
curl -sS -o /dev/null -w 'login  %{http_code}\n' "$BASE/files/login"           # expect 404
curl -sS -o /dev/null -w 'api    %{http_code}\n' "$BASE/files/api/users"       # expect 404
curl -sS -o /dev/null -w 'trav   %{http_code}\n' "$BASE/files/static/../api/users"  # expect 404
```

Expected: `200` for the share; `404` for login, admin API, and the traversal probe. **If any admin/auth route returns non-404, stop and fix the `path` matcher before Task 4.**

- [ ] **Step 4: Verify a download works through the gate** — download one file from the share successfully.

- [ ] **Step 5: Commit** — no repo change; skip. (Deployment is captured in the README/docs.)

---

### Task 4: Publish the node (policy + funnel)

**Files:**
- No repo change (Tailscale admin console + one command).

**Interfaces:**
- Consumes: the running `fileshare` node (Task 3) and its assigned tailnet IP.
- Produces: public reachability for the share link — verified in Task 5's docs.

- [ ] **Step 1: Owner adds the node to the funnel policy.** In the tailnet policy file, extend the existing `nodeAttrs` grant (currently `100.78.80.41` for Zipline) to include the `fileshare` node's IP. Record the IP.

- [ ] **Step 2: Enable the funnel (scoped to this node only)**

```sh
docker exec fileshare-ts tailscale funnel --bg --https=443 http://127.0.0.1:8080
docker exec fileshare-ts tailscale funnel status     # confirm the mapping
```

- [ ] **Step 3: Verify from a device with Tailscale OFF** (phone on mobile data)

- `https://fileshare.tail91459b.ts.net/files/share/<token>` → **works** (200, downloads).
- `https://docker-host.tail91459b.ts.net/files/` → **must not resolve/work**.
- Also confirm `docker-host`'s own `serve` mappings still read *(tailnet only)*.

- [ ] **Step 4: Record rollback** in the node README: `docker exec fileshare-ts tailscale funnel --https=443 off` + `docker compose down`.

---

### Task 5: Finalize docs, policy text, and diagram

**Files:**
- Modify: `AGENTS.md`, `docs/setup.md`, `docs/access-matrix.md`, `docs/schemas/homelab.dot`, `README.md`, `stacks/filebrowser/README.md`, `docs/specs/2026-10-05-filebrowser-public-shares-design.md`

**Interfaces:**
- Consumes: verified URL, node IP, and observed behavior from Tasks 3–4.
- Produces: a repo whose docs match reality (no DRAFT markers left).

- [ ] **Step 1: Amend the hard rule in `AGENTS.md`** — replace "single deliberate exception is the Zipline node" with the two-node wording from the spec, keeping **"never funnel `docker-host`"**.

- [ ] **Step 2: Promote the DRAFT section in `docs/setup.md`** to final: remove the DRAFT banner, fill the real node IP and URL, keep the funnel on/off + off-tailnet verification.

- [ ] **Step 3: Promote the DRAFT section in `docs/access-matrix.md`** to final: real hostname/IP, and update the "Public service (the one exception)" heading to reflect two public services.

- [ ] **Step 4: Add the node to `docs/schemas/homelab.dot`** (new green/dashed node + funnel edge, matching the existing style) and validate:

```sh
make schemas
```

- [ ] **Step 5: Update `README.md` and `stacks/filebrowser/README.md`** to mention read-only public share links and remove the "No external sharing" line's absolute wording.

- [ ] **Step 6: Mark the spec implemented** — Status → `Implemented <date>`, add an **As built** section recording deviations (which `share` mechanism worked, the observed route set, the node IP).

- [ ] **Step 7: Verify no DRAFT markers or placeholders remain**

```sh
grep -rn 'DRAFT\|<token>\|<IP assigned on join>\|<fileshare-node-ip>' docs README.md stacks/filebrowser-share stacks/filebrowser || echo "clean"
```

Expected: `clean`.

- [ ] **Step 8: Commit**

```bash
git add AGENTS.md docs/setup.md docs/access-matrix.md docs/schemas/homelab.dot README.md stacks/filebrowser/README.md docs/specs/2026-10-05-filebrowser-public-shares-design.md
git commit -m "docs: document public Filebrowser share links"
```

---

## Self-Review

**1. Spec coverage:** Every spec section maps to a task — sharing enablement (T1), gate + stack + no-copy (T2), share-only enforcement (T3), own-node funnel + never-`docker-host` (T4), policy/doc/diagram changes (T5), rollback (T4 Step 4). The spec's two open questions (route set, 1.5.6 options) are resolved *empirically* in T1 rather than assumed.

**2. Step scan:** Each step yields one action with a checkable result (a config edit, a file, a `curl` status, a validation command). No "handle edge cases" filler. The one intentional hypothesis (the `Caddyfile` allowlist in T2 Step 2) is explicitly labelled replaceable and is gated by T1.

**3. Type consistency:** Service/container names (`fileshare-ts`, `share-gate`), node name (`fileshare`), port (`8080`), network (`proxy`), upstream (`filebrowser:80`), and image tags are identical across T2, T3, T4 and the spec.

**4. Review Focus:** Each of the five lines has a pinning check — traversal → T3 Step 3 (`/files/static/../api/users`); leakage → T3 Step 3 + T4 Step 3; token enumeration → T3 Step 3 (`/files/api/users` 404); live-mirror mutation → T3 Step 4 download; funnel misconfig → T4 Steps 1–3.

**5. Proportion:** Shorter than the spec; code blocks are config the executor pastes, not invented program bodies.

## Execution Handoff

- Recommended: **Native** — tasks are strictly sequential and several require interactive owner steps (test share, auth key, policy, off-tailnet verification), which a subagent cannot drive. Cost of a mistake is low and reversible (funnel off).
- At execution time, isolate the work with the `superpowers:using-git-worktrees` skill (the repo has unrelated uncommitted changes), or explicitly stage only the files this plan touches.
