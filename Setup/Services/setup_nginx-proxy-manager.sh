#!/bin/bash

####################################################
# Goal:
#   Install the software and make it run as a service
#   (meant to run on a server)
#
# Global Variables:
#   Cosmetic command display and Network paths
#
# Requirements
#   A Debian-based system
#
# Process:
#   Remove any remaining Docker version and install it fresh
#   Configure the docker yml config file
#   Start the service
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="

set -e  # Exit on any error
set -o pipefail # Exit if pipes fail

# Check that we're root; if not, fail out
if [[ $(whoami) != "root" ]]; then
    echo -e "${RED}ERROR: This script must be run as 'root' or with 'sudo' to function.${NC}"
    exit 1
fi

# Set local variables
software="Nginx Proxy Manager"
GATEWAY_IFACE="$( ip route \
                  | grep '^default' \
                  | head -1 \
                  | grep -o 'dev [a-z0-9]* ' \
                  | awk '{ print $NF }' )"
IP_ADDRESS="$( ip address show dev "${GATEWAY_IFACE}" \
               | grep -w "inet .* ${GATEWAY_IFACE}$" \
               | awk '{ print $2 }' \
               | awk -F '/' '{ print $1 }' )"

# Start Installation
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN} Starting ${software} installation${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}\n"

# Remove old Docker versions if present
apt remove -y docker.io docker-compose docker-doc podman-docker containerd runc || true

# Add Docker's official GPG key
apt update && apt upgrade -y
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
   tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation
docker run --rm hello-world

# Create .yml file with configuration
mkdir -p /opt/npm
cd /opt/npm

COMPOSE_FILE="docker-compose.yml"
TZ="$(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")"

cat > "${COMPOSE_FILE}" << EOF
services:
  app:
    image: 'jc21/nginx-proxy-manager:2.15.1'
    restart: unless-stopped

    ports:
      # These ports are in format <host-port>:<container-port>
      - '80:80' # Public HTTP Port
      - '443:443' # Public HTTPS Port
      - '81:81' # Admin Web Port
      # Add any other Stream port you want to expose
      # - '21:21' # FTP

    environment:
      TZ: "${TZ}"

      # Uncomment this if you want to change the location of
      # the SQLite DB file within the container
      # DB_SQLITE_FILE: "/data/database.sqlite"

      # Uncomment this if IPv6 is not enabled on your host
      DISABLE_IPV6: 'true'

    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

# Start NPM
docker compose up -d

echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}${software} installation completed!${NC}\n"
echo -e "${GREEN}Access ${software} at: http://${IP_ADDRESS}:81${NC}\n"
echo -e "${YELLOW}IPV6 has been disabled by default, you can activate it by${NC}"
echo -e "${YELLOW}       commenting the corresponding line in the .yml file${NC}"
echo -e "${YELLOW}To check service status: docker compose ps${NC}"
echo -e "${YELLOW}To view logs: docker compose logs -f${NC}"
echo -e "${YELLOW}To stop ${software}: docker compose down${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"