# InkShelf server extension

This directory contains the standalone library service used by the iOS app. It
does not import document-center code or use its accounts, sessions, database, or
audit log. It stores original books in `data/books` and exposes only
`/inkshelf-api/` through Nginx.

The service intentionally has no login. It supports metadata and cover requests,
byte-range downloads, streaming uploads up to the Nginx limit, deletion, and one
shared reading progress record. It does not transcode original book files.

Deployment targets:

- `/home/admin/inkshelf-server/inkshelf_server.py`
- `/etc/systemd/system/inkshelf-library.service`
- `/etc/nginx/default.d/inkshelf.conf`

After copying the files, run `systemctl daemon-reload`, enable the service,
validate Nginx configuration, and reload Nginx. The service binds only to
`127.0.0.1:8001` and must not be exposed directly. Its systemd unit does not
reference the document-center service or environment file.
