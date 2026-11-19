---
title: Verschlüsselung im Heimnetz
url: /de/einrichtung/verschluesselung/
weight: 30
---

Ein Server im Heimnetz hat keinen öffentlichen Namen und damit kein Zertifikat, das ein Browser ohne Warnung annimmt. Es gibt drei Möglichkeiten. Die App zeigt an, welche gerade gilt.

## 1. Eigener Name mit DNS-Challenge

Mit einer eigenen Domain holt Caddy ein öffentlich gültiges Zertifikat. Der Server muss dafür nicht von außen erreichbar sein.

Du brauchst ein Caddy-Image mit dem DNS-Modul deines Anbieters (zum Beispiel per `xcaddy build --with github.com/caddy-dns/<anbieter>`) und einen API-Token. Im `Caddyfile` ist der Block dafür schon vorbereitet:

```caddyfile
{$HIWISKI_HOSTNAME} {
	encode gzip zstd
	tls {
		dns <anbieter> {$HIWISKI_DNS_TOKEN}
	}
	reverse_proxy app:8080 {
		header_up X-Forwarded-Proto {scheme}
		header_up X-Forwarded-For {client_ip}
	}
}
```

## 2. Unverschlüsselt im Heimnetz

Das ist die Standardeinstellung. Die App und die Anmeldung weisen darauf hin.

## 3. Selbst signiert

Caddy erzeugt ein eigenes Zertifikat. Auf jedem Gerät muss dafür eine Ausnahme bestätigt werden.

```caddyfile
{$HIWISKI_HOSTNAME} {
	tls internal
	reverse_proxy app:8080 {
		header_up X-Forwarded-For {client_ip}
	}
}
```

## Noch ein Proxy vor Caddy

Erreicht die Familie den Server über den eigenen Reverse-Proxy des NAS oder einen Tunnel (Cloudflare, Tailscale Funnel), sieht Caddy diesen Proxy als jeden Besucher. Der Server zählt falsche Passwörter pro Adresse – die Versuche eines Fremden würden dann die ganze Familie bremsen. Trag den Proxy oben im `Caddyfile` ein, dann gibt Caddy die eigene Adresse jedes Besuchers weiter:

```caddyfile
{
	servers {
		trusted_proxies static 192.168.1.2
		trusted_proxies_strict
	}
}
```

`192.168.1.2` ist die Adresse des Proxys (oder ein Bereich wie `192.168.1.0/24`). Danach `docker compose restart caddy`.
