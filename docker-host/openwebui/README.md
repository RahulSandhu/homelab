# Open WebUI — local chat for Ollama

Tailnet-only chat UI for the local model on `pve`.

- **Served at:** <https://chat.tail91459b.ts.net> — **tailnet-only, never funneled**.
- **Model:** `ministral-3:3b-chat` on `pve` (Ollama at `pve:11434`, CPU-only, ~8–18 tok/s).
  It is a thin variant of `ministral-3:3b` with a short system prompt and
  `num_predict=384`; the stock model injects a ~560-token default system prompt.
- **Background model calls** (title/tags/follow-up/autocomplete) are disabled in
  `compose.yaml` so they don't queue ahead of the chat.
- **Deploy:** fill `.env` (`TS_AUTHKEY`, `WEBUI_SECRET_KEY`), then:

  ```sh
  docker compose up -d
  docker exec openwebui-ts tailscale serve --bg --https=443 http://127.0.0.1:8080
  ```

- **First run:** open the URL and sign up — the first account becomes admin.
  Then set `ENABLE_SIGNUP=false` in `.env` and run `docker compose up -d` again.
- **Ollama:** installed on the PVE host (`/etc/systemd/system/ollama.service.d/override.conf`),
  bound to `0.0.0.0:11434` (LAN/tailnet only). It has **no auth** — never port-forward it.
  The model is `ministral-3:3b`; models live under `/usr/share/ollama/.ollama`.
