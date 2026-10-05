# PairDrop

AirDrop-style file sharing in the browser — devices see each other and transfer
files **peer-to-peer (WebRTC)**. No apps to install.

Served at `https://docker-host.tail91459b.ts.net/pairdrop/` (via Caddy, tailnet-only).

On the internal `pairdrop` network; no host port published.

## Notes

- **Add to home screen** may open `/` instead of `/pairdrop` (PairDrop's PWA
  `start_url`); cosmetic, and Android is unaffected.
- Transfers are direct between devices; Caddy only serves the page + brokers.

## Operate

```sh
docker compose ps
docker compose logs -f
```
