# Stirling PDF

Stateless PDF toolbox (merge, split, compress, OCR, convert, sign…). Served at
`:10000` on its own tailnet port — its UI cannot live under a subpath. Files are
processed in temp and deleted; nothing is stored.

Deploy: `docker compose up -d`.
