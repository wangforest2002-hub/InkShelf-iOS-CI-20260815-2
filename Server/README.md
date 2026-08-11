# InkShelf server extension

This directory contains the isolated private-library service used by the iOS
app. It reuses document-center accounts and sessions, stores original books in
`data/inkshelf/books`, and exposes only `/api/inkshelf/` through Nginx.

The service supports authenticated metadata and cover requests, byte-range
downloads, streaming uploads up to the Nginx limit, deletion by administrators,
and per-user reading progress. It does not transcode original book files.

Deployment targets:

- `/home/admin/document-center/inkshelf_server.py`
- `/etc/systemd/system/inkshelf-library.service`
- `/etc/nginx/default.d/inkshelf.conf`

After copying the files, run `systemctl daemon-reload`, enable the service,
validate Nginx configuration, and reload Nginx. The service binds only to
`127.0.0.1:8001` and must not be exposed directly.
