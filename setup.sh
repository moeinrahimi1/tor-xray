#!/usr/bin/env bash
set -e

UUID="4700dbf2-df05-4913-80ae-da9fec9e0da7"

echo "=== Tor + Xray + obfs4 Auto Setup ==="

# Ask user inputs
read -p "Enter Xray port (default 8443): " XRAY_PORT
XRAY_PORT=${XRAY_PORT:-8443}

read -p "Enter Tor ExitNode country code (e.g. de, nl, us): " TOR_COUNTRY
TOR_COUNTRY=${TOR_COUNTRY:-de}

# Install packages
echo "[*] Installing Tor + obfs4proxy..."
sudo apt update
sudo apt install -y tor obfs4proxy curl wget gnupg2 lsb-release

# Install Xray
echo "[*] Installing Xray..."
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# Configure Tor with bridges + tuning
echo "[*] Writing Tor config..."
sudo tee /etc/tor/torrc <<EOF
SocksPort 9050

# Exit country (only for non-bridge circuits)
ExitNodes {$TOR_COUNTRY}
StrictNodes 1

# Bridges
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

Bridge obfs4 83.113.75.134:12345 8545E750001414D1C03307D21BACA22323ECA7D3 cert=KApm8jSi61HBvG2yDOES041iA1ZY+4l5Zr48WIk5AX1xb96a7ZU7kynqIGvW8oc/alnFbw iat-mode=0
Bridge obfs4 65.108.148.241:9101 026F343E5CC9218C24D98FBBB26C6B4FA8CB9F3C cert=iytfhTD2yqW0hUk7z2uts7lZ24lmcBH9P5fv0CDNG9Go/ulbyim/+Woj3G0okW4OK0lMCQ iat-mode=0

# Performance / stability tuning
MaxCircuitDirtiness 3600
ConnLimit 4096
CircuitStreamTimeout 60
ClientUseIPv6 0
NumEntryGuards 1
EOF

# Restart Tor
sudo systemctl restart tor
sudo systemctl enable tor

# Create Xray config
echo "[*] Writing Xray config..."
sudo mkdir -p /usr/local/etc/xray

sudo tee /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "debug"
  },
  "inbounds": [
    {
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 9050
          }
        ]
      },
      "tag": "tor"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["vless-in"],
        "outboundTag": "tor"
      }
    ]
  }
}
EOF

# Restart Xray
sudo systemctl restart xray
sudo systemctl enable xray

# Get public IP
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Generate VLESS URI
VLESS_URI="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&type=tcp#tor-xray"

# Final output
echo "======================================"
echo " Tor + obfs4 + Xray Setup Completed"
echo " Xray Port: $XRAY_PORT"
echo " Tor Exit Country: $TOR_COUNTRY"
echo " UUID: $UUID"
echo " SOCKS5: 127.0.0.1:9050"
echo ""
echo "VLESS URI:"
echo "$VLESS_URI"
echo "======================================"

# Test Tor IP
echo "[*] Testing Tor exit IP:"
curl --socks5 127.0.0.1:9050 https://api.ipify.org || true
echo
