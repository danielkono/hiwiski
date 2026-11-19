# The public demo: the web app built with HIWISKI_DEMO, served as static
# files. No server, no database, nothing written -- whatever a visitor does stays in
# their browser tab.
#
# Built by the release workflow from the web build in `web/` (release.yml, "Demo image");
# TLS is the job of a proxy in front of it; this serves plain HTTP on 8080 inside the
# Docker network only.
# The base by its digest, the tag only for the reader: a tag can be pushed again with
# other content, and this image is published under the project's name. Dependabot
# moves both together (.github/dependabot.yml).
FROM caddy:2.11-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0

# The official binary carries the file capability to bind ports below 1024. Port 8080
# needs none, and with every capability dropped and no-new-privileges (as the compose
# file runs it) the kernel refuses to start a binary that asks for one.
RUN apk add --no-cache libcap \
    && setcap -r /usr/bin/caddy \
    && apk del libcap

COPY Caddyfile /etc/caddy/Caddyfile
COPY web /srv

# Not root: nothing here needs it. Caddy keeps its state in /data and /config, which
# the compose file mounts as tmpfs -- the container's own file system stays read-only.
USER 65534:65534
ENV XDG_DATA_HOME=/data XDG_CONFIG_HOME=/config
EXPOSE 8080
