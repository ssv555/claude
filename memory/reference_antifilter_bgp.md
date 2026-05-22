---
name: antifilter.network BGP feed
description: Public BGP peer with RKN-blocked IP prefixes for router-side policy routing
type: reference
---

[antifilter.network/bgp](https://antifilter.network/bgp) — public BGP feed of RKN registry (~30–40k prefixes), auto-updated.

- Peer IPv4: `45.148.244.55` / IPv6: `2001:41d0:701:1100::1db1`
- Their AS: `65444`, local AS: `64999` (private)
- Port `179`, no auth, `hold timer = 240s`
- Exclude `45.148.244.55` from received prefixes (loop)
- Community `65432:500` — extra geo-blocked services

Use: router (Keenetic/MikroTik/OpenWRT) routes RKN-listed IPs to VPN automatically for whole LAN. No DPI bypass, no CDN/SNI routing (AI services on Cloudflare — route on PC via Xray/Hiddify by domain, not here).
