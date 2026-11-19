---
title: Encryption on the home network
description: 'HTTPS for a Hiwiski server on the home network: certificates and encryption between the apps and the server.'
weight: 30
---

A server on the home network has no public name and so no certificate a browser accepts without a warning. There are three options. The app shows which one applies.

## 1. Your own name with a DNS challenge

With a domain of your own, Caddy fetches a publicly trusted certificate. The server does not have to be reachable from outside for this.

You need a Caddy image with your provider's DNS module (for example `xcaddy build --with github.com/caddy-dns/<provider>`) and an API token. The block for it is already prepared in the `Caddyfile`:

```caddyfile
{$HIWISKI_HOSTNAME} {
	encode gzip zstd
	tls {
		dns <provider> {$HIWISKI_DNS_TOKEN}
	}
	reverse_proxy app:8080 {
		header_up X-Forwarded-Proto {scheme}
		header_up X-Forwarded-For {client_ip}
	}
}
```

## 2. Cleartext on the home network

This is the default. The app and the sign-in point it out.

## 3. Self-signed

Caddy creates a certificate of its own. Every device has to confirm an exception for it.

```caddyfile
{$HIWISKI_HOSTNAME} {
	tls internal
	reverse_proxy app:8080 {
		header_up X-Forwarded-For {client_ip}
	}
}
```

## Another proxy in front of Caddy

If the family reaches the server through the NAS's own reverse proxy or a tunnel (Cloudflare, Tailscale Funnel), Caddy sees that proxy as every visitor. The server counts wrong passwords per address, so one stranger's attempts would then slow down the whole family. Name the proxy at the top of the `Caddyfile`, and Caddy passes on each visitor's own address:

```caddyfile
{
	servers {
		trusted_proxies static 192.168.1.2
		trusted_proxies_strict
	}
}
```

`192.168.1.2` is the proxy's address (or a range like `192.168.1.0/24`). Then `docker compose restart caddy`.
