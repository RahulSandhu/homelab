# MeTube

Web UI for `yt-dlp`; downloads land on `/srv/metube`.

- **Served at:** `https://docker-host.tail91459b.ts.net/metube/` —
  tailnet-only.
- **Deploy:** `docker compose up -d`.

## Notes

- Bump the image every few weeks — `yt-dlp`'s tag is a date.
- Finished downloads auto-delete after 24 h (`CLEAR_COMPLETED_AFTER=86400`
  **seconds** + `DELETE_FILE_ON_TRASHCAN=true`).
