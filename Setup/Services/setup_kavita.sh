#!/bin/bash

####################################################
# Goal:
#   Install the software and make it run as a service
#   (meant to run on a server)
#
# Global Variables:
#   Text colour display, network information, software name
#
# Requirements
#   A Debian-based system
#
# Process:
#   Set the database password
#   Remove any remaining Docker version and install it fresh
#   Fetch the docker yml config file
#   Start the service
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="

# Set local variables
software="Kavita"
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

# Remove old Docker versions if present
apt remove -y docker.io docker-compose docker-doc podman-docker containerd runc

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

# Create and navigate to the install directory
mkdir -p /opt/kavita
cd /opt/kavita

# Set Variable
TZ=$(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value)

# Setup docker-compose file
cat > docker-compose.yml << EOF
services:
  kavita:
    image: ghcr.io/kareadita/kavita:latest
    container_name: kavita
    volumes:
      - /your/path/to/saved/config:/kavita/config
    environment:
      - TZ=${TZ}
    ports:
      - "5000:5000"
    restart: unless-stopped

EOF

# Start Kavita
docker compose up -d

echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}Kavita installation completed!${NC}\n"
echo -e "${GREEN}Access Kavita at: http://${IP_ADDRESS}:5000${NC}\n"
echo -e "${GREEN}To check service status: docker compose ps${NC}"
echo -e "${GREEN}To view logs: docker compose logs -f${NC}"
echo -e "${GREEN}To stop Kavita: docker compose down${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"
