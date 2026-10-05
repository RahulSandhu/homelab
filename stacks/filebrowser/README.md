# Filebrowser (FileBrowser Quantum)

A browsable, **read-only** web file manager over the laptop's backup mirror.

Served at `https://docker-host.tail91459b.ts.net/files/` (via Caddy, tailnet-only).

Uses **FileBrowser Quantum** (`gtstef/filebrowser`) — the maintained fork. The
original `filebrowser/filebrowser` was **archived on 2026-09-01**: no further
releases and no security fixes.

`/srv/backup` (the rclone mirror target) is bind-mounted **read-only** at `/srv`
inside the container, so the GUI can browse, preview and download but never
write — a write there would be silently reverted by the next `rclone sync`.
`config.yaml` additionally defaults every user to read-only permissions.

The SQLite index lives in `./data`; the config in `./config`.
On the internal `proxy` network; no host port published.

## First run — set the admin password

The database is initialised with an admin user whose password nobody knows, so
the service is unusable until you set it. **Only one process may touch the
database**, so the service must be stopped while the CLI runs:

```sh
cd /opt/filebrowser
sudo docker compose down
read -rsp "New Filebrowser admin password: " FBPW; echo
sudo docker compose run --rm --entrypoint ./filebrowser filebrowser \
  set -u "admin,$FBPW" -a -c /config/config.yaml
unset FBPW
sudo docker compose up -d
```

Reading the password into a variable keeps it out of your shell history.
The same command is the password **reset** (it also clears any 2FA).

> **Quirk on a brand-new database:** the *first* `set` invocation fails with a
> misleading `password must be at least 8 characters long` (the minimum isn't
> applied until the DB exists). It creates the DB anyway — **just run it again**
> and it succeeds.

Then sign in at `.../files`.

## Operate

```sh
docker compose ps
docker compose logs -f
```

## Notes

- **Indexing:** Quantum builds an index of the source on first start. With ~51k
  objects the first build takes a little while; it persists in `database.db`.
- `config/config.yaml` (mounted at `/config/config.yaml` via `FILEBROWSER_CONFIG`)
  sets `baseURL: /files` and the single source `/srv` ("Backup").
- File permissions are enforced twice: the user's permissions **and** the
  read-only bind mount.
- **Public share links are possible** (`share: true` for the owner). The public
  surface is served through the **share-only gate** at
  `fileshare.tail91459b.ts.net` (`stacks/filebrowser-share/`), which exposes only
  `/files/public/*`. This instance itself stays internal (no host port).
- CLI syntax note: this pinned 1.5.x release uses `set -u user,password`; the
  `user set --password` form is v2.0.0+.

## Users — there is no "delete user"

Quantum v1.5.x exposes **no user deletion** (neither the UI nor the API), and the
CLI only offers `set -u <user>,<password> [-a]`. So to *remove* a user (or to end
up with a single account), replace the database:

```sh
cd /opt/filebrowser
sudo docker compose stop
sudo cp data/database.db /tmp/filebrowser-database.db.bak   # keep a copy
sudo rm -f data/database.db
# fresh DB: the FIRST run fails with a misleading min-length error — run it twice
sudo docker compose run --rm --entrypoint ./filebrowser filebrowser set -u "admin,PASSWORD" -a -c /config/config.yaml
sudo docker compose run --rm --entrypoint ./filebrowser filebrowser set -u "admin,PASSWORD" -a -c /config/config.yaml
sudo docker compose start
```

The **file index rebuilds** on start (~minutes over ~51k files; watch the logs for
`initializing index`).

> **After replacing the database, browsers with an old session get a 500.**
> Quantum signs a JWT cookie (`filebrowser_quantum_jwt`) **per user**. If that user
> no longer exists, the app throws
> `500 {"message":"could not authenticate request"}` instead of redirecting to the
> login page. The token is trusted by *signature*, so a **valid old cookie is fatal**
> while a garbage one is simply ignored (→ anonymous, 200).
> **Fix: clear the site's cookies (or use a private window) and sign in again** —
> nothing is wrong server-side.

The admin API is reachable at `/files/api/…`; login is
`POST /files/api/auth/login?username=<u>&recaptcha=` with the password in an
**`X-Password` header** (not a JSON body), and returns a `filebrowser_quantum_jwt`
cookie.
