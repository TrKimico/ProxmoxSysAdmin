#!/bin/bash

####################################################
# Goal:
#   Install the software and make it run as a service
#   (meant to run on a server)
#
# Global Variables:
#   None
#
# Requirements
#   A Debian-based system
#
# Process:
#   Check local configuration
#   Download dependencies and software zipped archive
#   Unpack the archive and install the service
#   Configure the service and start it
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="

# Set local variables
software="Navidrome"
GATEWAY_IFACE="$( ip route \
                  | grep '^default' \
                  | head -1 \
                  | grep -o 'dev [a-z0-9]* ' \
                  | awk '{ print $NF }' )"
IP_ADDRESS="$( ip address show dev "${GATEWAY_IFACE}" \
               | grep -w "inet .* ${GATEWAY_IFACE}$" \
               | awk '{ print $2 }' \
               | awk -F '/' '{ print $1 }' )"


set -e  # Exit on any error


# Start Installation
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN} Starting ${software} installation${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}\n"


# Update system
apt update && apt upgrade -y

# Install dependencies
apt install -y curl wget

# Debug info
echo "System info:"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -s)"
echo ""

# Get latest release info from GitHub API
echo "Fetching latest Navidrome release info..."
API_RESPONSE=$(curl -s "https://api.github.com/repos/navidrome/navidrome/releases/latest")

# Check if API response is valid
if echo "$API_RESPONSE" | grep -q "API rate limit exceeded"; then
    echo "GitHub API rate limit exceeded. Using fallback version..."
    # Fallback to a known working version
    TAG_NAME="v0.59.0"
else
    TAG_NAME=$(echo "$API_RESPONSE" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
fi

echo "Latest version: $TAG_NAME"

# Try different URL patterns - the correct one seems to be lowercase 'linux_amd64'
URL_PATTERNS=(
    https://github.com/navidrome/navidrome/releases/download/v0.59.0/navidrome_0.59.0_linux_amd64.tar.gz
)

# Try to find a working download URL
DOWNLOAD_URL=""
for url in "${URL_PATTERNS[@]}"; do
    echo "Testing URL: $url"
    if curl --head --silent --fail "$url" > /dev/null 2>&1; then
        DOWNLOAD_URL="$url"
        echo "✓ Valid URL found: $DOWNLOAD_URL"
        break
    else
        echo "✗ URL not accessible"
    fi
done

# If no URL found, exit
if [ -z "$DOWNLOAD_URL" ]; then
    echo "ERROR: Could not find a valid download URL!"
    echo "Please manually check: https://github.com/navidrome/navidrome/releases"
    echo "and update the script with the correct URL pattern."
    exit 1
fi

# Create installation directory
echo ""
echo "Creating installation directory..."
install -d /opt/navidrome

# Download with wget (more reliable than curl for GitHub releases)
echo "Downloading Navidrome..."
cd /opt/navidrome
wget --show-progress -O navidrome.tar.gz "$DOWNLOAD_URL"

# Verify download
echo ""
echo "Verifying download..."
if [ ! -s "navidrome.tar.gz" ]; then
    echo "ERROR: Downloaded file is empty!"
    exit 1
fi

FILE_TYPE=$(file -b navidrome.tar.gz)
echo "File type: ${FILE_TYPE}"

if echo "$FILE_TYPE" | grep -q "gzip compressed data"; then
    echo "File is valid gzip archive. Extracting..."
    tar -xvzf navidrome.tar.gz
    echo "Contents extracted:"
    ls -la
else
    echo "ERROR: Downloaded file is not a valid gzip archive!"
    echo "First 200 bytes of file:"
    head -c 200 navidrome.tar.gz
    echo ""
    exit 1
fi

# Clean up
rm navidrome.tar.gz

# Create user and directories
echo ""
echo "Creating system user and directories..."
if ! id navidrome &>/dev/null; then
    useradd -r -s /bin/false navidrome
    echo "Created user: navidrome"
else
    echo "User 'navidrome' already exists"
fi

# Create required directories
mkdir -p /var/lib/navidrome
mkdir -p /mnt/music

# Set permissions
chown -R navidrome:navidrome /var/lib/navidrome
chown -R navidrome:navidrome /mnt/music

# Create config file
echo ""
echo "Creating configuration file..."
cat > /var/lib/navidrome/navidrome.toml << 'EOF'
MusicFolder = "/mnt/music"
DataFolder = "/var/lib/navidrome"
Port = 4533
LogLevel = "info"
# ScanSchedule = "1h"
# BaseURL = ""
# Address = "0.0.0.0"
EOF

echo "Config file created at: /var/lib/navidrome/navidrome.toml"

# Create systemd service
echo ""
echo "Creating systemd service..."
cat > /etc/systemd/system/navidrome.service << 'EOF'
[Unit]
Description=Navidrome Music Server
After=network.target
Requires=network.target

[Service]
User=navidrome
Group=navidrome
Type=simple
ExecStart=/opt/navidrome/navidrome --configfile /var/lib/navidrome/navidrome.toml
WorkingDirectory=/var/lib/navidrome
TimeoutStopSec=20
KillMode=process
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/navidrome /mnt/music

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo ""
echo "Enabling and starting Navidrome service..."
systemctl daemon-reload
systemctl enable navidrome
systemctl start navidrome

# Wait a moment for service to start
sleep 2

# Check service status
echo ""
echo "Checking service status..."
SERVICE_STATUS=$(systemctl is-active navidrome)
if [ "$SERVICE_STATUS" = "active" ]; then
    echo "✓ Navidrome is running!"
else
    echo "⚠ Service status: $SERVICE_STATUS"
    echo "Check logs with: journalctl -u navidrome -f"
fi

echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}Navidrome should be accessible at:${NC}"
echo -e "${GREEN}  http://${IP_ADDRESS}:4533${NC}\n"
echo -e "${GREEN}Useful commands:${NC}"
echo -e "${GREEN}  Check status:  systemctl status navidrome${NC}"
echo -e "${GREEN}  View logs:     journalctl -u navidrome -f${NC}"
echo -e "${GREEN}  Restart:       systemctl restart navidrome${NC}"
echo -e "${GREEN}  Stop:          systemctl stop navidrome${NC}\n"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "${YELLOW}  1. Place your music files in /mnt/music${NC}"
echo -e "${YELLOW}  2. Access the web interface to set up your admin account${NC}"
echo -e "${YELLOW}  3. Configure reverse proxy if needed (nginx/apache)${NC}\n"
echo -e "${YELLOW}For more info: https://www.navidrome.org/docs/${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"
