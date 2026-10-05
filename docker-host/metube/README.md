# MeTube

Web UI for `yt-dlp`. Downloads land on `/srv/metube` and auto-delete 24 h after
finishing (`CLEAR_COMPLETED_AFTER=86400` **seconds** + `DELETE_FILE_ON_TRASHCAN`).
Served at `/metube/`. This is the one image to bump regularly — `yt-dlp` must keep
up with the sites.

Deploy: `docker compose up -d`.
