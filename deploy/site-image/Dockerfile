# The website: the Hugo build, the scenes' web build under /embed/
# and their screenshots, served as static files. Built by the release workflow
# (release.yml, "Site image"); TLS is the job of a proxy in front of it; this serves
# plain HTTP on 8080 inside the Docker network only.
# By its digest, as in the demo's image: a tag can be pushed again with other content.
FROM caddy:2.11-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0

# As in the demo's image: the binary's file capability would keep it from starting
# with every capability dropped and no-new-privileges.
RUN apk add --no-cache libcap \
    && setcap -r /usr/bin/caddy \
    && apk del libcap

COPY Caddyfile /etc/caddy/Caddyfile
COPY public /srv

USER 65534:65534
ENV XDG_DATA_HOME=/data XDG_CONFIG_HOME=/config
EXPOSE 8080
