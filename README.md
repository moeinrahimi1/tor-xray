# tor-xray
configure xray with tor as outbound easily
xray act as client and route traffic through tor's socks proxy
optimized for high load usage

# How To Use
```
bash <(curl -L https://raw.githubusercontent.com/moeinrahimi1/tor-xray/refs/heads/main/setup.sh)
```

# How It Works
```
                 ┌──────────────────────────┐
                 │        Client            │
                 │ (v2rayN / Nekobox / etc) │
                 └─────────────┬────────────┘
                               │ VLESS TCP
                               │ (no TLS)
                               ▼
┌──────────────────────────────────────────────────┐
│                    Xray Server                  │
│                                                  │
│  Inbound:                                        │
│    0.0.0.0:XRAY_PORT (VLESS)                     │
│    tag = "vless-in"                              │
│                                                  │
│  Routing Rule:                                   │
│    inboundTag "vless-in" → outbound "tor"        │
│                                                  │
│  Outbound:                                       │
│    SOCKS5 → 127.0.0.1:9050                        │
└──────────────────────────┬───────────────────────┘
                           │ SOCKS5
                           ▼
┌──────────────────────────────────────────────────┐
│                    Tor Client                   │
│                                                  │
│  Entry: obfs4 Bridge (DPI bypass)                │
│                                                  │
│  Tor Circuit:                                    │
│    Bridge → Guard → Middle → ExitNode            │
│                                                  │
│  ExitNodes: {COUNTRY} (best-effort)               │
└──────────────────────────┬───────────────────────┘
                           │
                           ▼
                   🌍 Public Internet

```