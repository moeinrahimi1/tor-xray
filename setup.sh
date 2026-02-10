#!/usr/bin/env bash
set -e

UUID="4700dbf2-df05-4913-80ae-da9fec9e0da7"

echo "=== Tor + Xray + obfs4 Interactive Setup ==="


CONFIG_MARKER="/usr/local/etc/xray/config.json"
TOR_MARKER="/etc/tor/torrc"

# -------------------------
# Detect existing setup
# -------------------------
if [[ -f "$CONFIG_MARKER" && -f "$TOR_MARKER" ]]; then
  echo "[!] Existing Tor + Xray config detected."

  read -p "Show VLESS URI and exit? (y/N): " CHOICE
  CHOICE=${CHOICE,,}

  if [[ "$CHOICE" == "y" ]]; then
    SERVER_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    XRAY_PORT=$(jq -r '.inbounds[0].port' "$CONFIG_MARKER" 2>/dev/null || echo 8443)

    VLESS_URI="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&type=tcp#tor-xray"
    echo ""
    echo "======================================"
    echo " VLESS URI:"
    echo "$VLESS_URI"
    echo "======================================"
    exit 0
  fi

  echo "[*] Re-running setup from scratch..."
fi





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

echo ""
echo "Enter Tor obfs4 bridges (one per line)."
echo "When done, press ENTER on an empty line:"
BRIDGES=()
while true; do
  read -r LINE
  [[ -z "$LINE" ]] && break
  BRIDGES+=("$LINE")
done

# -------------------------
# Install dependencies
# -------------------------
install_if_missing tor obfs4proxy curl wget gnupg2 lsb-release jq

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

TORRC=$(mktemp)

cat > "$TORRC" <<EOF
SocksPort 9050

ExitNodes {$TOR_COUNTRY}
StrictNodes 0

UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

# Performance tuning
MaxCircuitDirtiness 3600
ConnLimit 4096
CircuitStreamTimeout 60
ClientUseIPv6 0
NumEntryGuards 1

EOF

# Append bridges
for B in "${BRIDGES[@]}"; do
  echo "Bridge $B" >> "$TORRC"
done

sudo mv "$TORRC" /etc/tor/torrc

sudo systemctl restart tor
sudo systemctl enable tor

# -------------------------
# Configure Xray
# -------------------------
echo "[*] Writing Xray config..."
sudo mkdir -p /usr/local/etc/xray

sudo tee /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "debug" },
  "inbounds": [
    {
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID", "flow": "" }],
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
      "settings": { "servers": [{ "address": "127.0.0.1", "port": 9050 }] },
      "tag": "tor"
    },
    { "protocol": "freedom", "tag": "direct" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "inboundTag": ["vless-in"], "outboundTag": "tor" }
    ]
  }
}
EOF

sudo systemctl restart xray
sudo systemctl enable xray

# -------------------------
# Detect server IP
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

# -------------------------
# Wait for Tor bootstrap
# -------------------------
# -------------------------
# Wait fixed time for Tor
# -------------------------
echo "[*] Waiting 15 seconds for Tor to stabilize..."
sleep 15

# -------------------------
# Test Tor IP with timeout
# -------------------------
echo "[*] Tor exit IP test (timeout 10s):"
curl --socks5 127.0.0.1:9050 \
     --connect-timeout 5 \
     --max-time 10 \
     https://api.ipify.org || echo "[!] Curl failed or timed out"
echo
