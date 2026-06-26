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
#   Remove any remaining docker installation
#   Reinstall a fresh docker instance
#   Configure the environment .yml file
#   Start the service
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="

# local variables
software="Homarr"
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

# Generate a secure random encryption key
SECRET_KEY=$(openssl rand -hex 32)

COMPOSE_FILE="docker-compose.yml"

cat > "${COMPOSE_FILE}" << EOF
#---------------------------------------------------------------------#
#     Homarr - A simple, yet powerful dashboard for your server.      #
#---------------------------------------------------------------------#
services:
  homarr:
    container_name: homarr
    image: ghcr.io/homarr-labs/homarr:latest
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock # Optional, only if you want docker integration
      - ./homarr/appdata:/appdata
    environment:
      - SECRET_ENCRYPTION_KEY=${SECRET_KEY}
    ports:
      - '7575:7575'
EOF

# Start Homarr
docker compose up -d

echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}Homarr installation completed!${NC}\n"
echo -e "${GREEN}Access Homarr at: http://${IP_ADDRESS}:7575 ${NC}\n"
echo -e "${GREEN}To check service status: docker compose ps${NC}"
echo -e "${GREEN}To view logs: docker compose logs -f${NC}"
echo -e "${GREEN}To stop Homarr: docker compose down${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"

#Clear Sensible Data From Memory
unset SECRET_KEY
