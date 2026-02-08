#!/usr/bin/env bash
set -e

UUID="4700dbf2-df05-4913-80ae-da9fec9e0da7"

echo "=== Tor + Xray + obfs4 Interactive Setup ==="

# -------------------------
# Dependency checker
# -------------------------
check_pkg() {
  dpkg -s "$1" >/dev/null 2>&1
}

install_if_missing() {
  local PKGS=()
  for pkg in "$@"; do
    if ! check_pkg "$pkg"; then
      PKGS+=("$pkg")
    fi
  done

  if [ ${#PKGS[@]} -gt 0 ]; then
    echo "[*] Installing missing packages: ${PKGS[*]}"
    sudo apt update
    sudo apt install -y "${PKGS[@]}"
  else
    echo "[*] All dependencies already installed"
  fi
}

# -------------------------
# Ask user inputs
# -------------------------
read -p "Enter Xray port (default 8443): " XRAY_PORT
XRAY_PORT=${XRAY_PORT:-8443}

read -p "Enter Tor ExitNode country code (e.g. de, nl, us): " TOR_COUNTRY
TOR_COUNTRY=${TOR_COUNTRY:-de}

# -------------------------
# Install dependencies
# -------------------------
install_if_missing tor obfs4proxy curl wget gnupg2 lsb-release

# -------------------------
# Install Xray if missing
# -------------------------
if ! command -v xray >/dev/null 2>&1; then
  echo "[*] Installing Xray..."
  bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
else
  echo "[*] Xray already installed"
fi

# -------------------------
# Configure Tor
# -------------------------
echo "[*] Writing Tor config..."

sudo tee /etc/tor/torrc <<EOF
SocksPort 9050

# Exit node preference
ExitNodes {$TOR_COUNTRY}
StrictNodes 1

# Bridges
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

Bridge obfs4 83.113.75.134:12345 8545E750001414D1C03307D21BACA22323ECA7D3 cert=KApm8jSi61HBvG2yDOES041iA1ZY+4l5Zr48WIk5AX1xb96a7ZU7kynqIGvW8oc/alnFbw iat-mode=0
Bridge obfs4 65.108.148.241:9101 026F343E5CC9218C24D98FBBB26C6B4FA8CB9F3C cert=iytfhTD2yqW0hUk7z2uts7lZ24lmcBH9P5fv0CDNG9Go/ulbyim/+Woj3G0okW4OK0lMCQ iat-mode=0

# Performance tuning
MaxCircuitDirtiness 3600
ConnLimit 4096
CircuitStreamTimeout 60
ClientUseIPv6 0
NumEntryGuards 1
EOF

sudo systemctl restart tor
sudo systemctl enable tor

# -------------------------
# Configure Xray
# -------------------------
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

sudo systemctl restart xray
sudo systemctl enable xray

# -------------------------
# Detect server IP using ip ONLY
# -------------------------
SERVER_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
if [ -z "$SERVER_IP" ]; then
  echo "[!] Failed to detect IP via ip route"
  exit 1
fi

# -------------------------
# Generate VLESS URI
# -------------------------
VLESS_URI="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&type=tcp#tor-xray"

# -------------------------
# Output
# -------------------------
echo "======================================"
echo " Tor + Xray + obfs4 Setup Complete"
echo " Xray Port: $XRAY_PORT"
echo " Tor Exit Country: $TOR_COUNTRY"
echo " UUID: $UUID"
echo " Server IP: $SERVER_IP"
echo " SOCKS5: 127.0.0.1:9050"
echo ""
echo "VLESS URI:"
echo "$VLESS_URI"
echo "======================================"

# Test Tor IP
echo "[*] Tor exit IP test:"
curl --socks5 127.0.0.1:9050 https://api.ipify.org || true
echo
