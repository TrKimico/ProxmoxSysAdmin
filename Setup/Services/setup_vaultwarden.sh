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
#   A pre-configured reverse proxy host for the service (e.g. on Nginx Proxy Manager)
#     because vaultwarden demands a secure HTTPS connection to run
#
# Process:
#   Remove any remaining docker instance and install it fresh
#   Configure the yml config file with provided address
#   Start the service 
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="
software="Vaultwarden"

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

# Create and navigate to vaultwarden directory
mkdir -p /opt/vaultwarden
cd /opt/vaultwarden

# Reference the Nginx Reverse Proxy address
echo "$SEPARATOR"
read -p "Enter the full address at which your reverse proxy redirects traffic (exp : http://vaultwarden.domain.com (default port:80)) " ADDRESS
echo "The address is : ${ADDRESS}"
echo "$SEPARATOR"
# create vaultwarden docker compose file
cat > compose.yml << EOF
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    environment:
      DOMAIN: "$ADDRESS"  # required when using a reverse proxy; your domain; vaultwarden needs to know it's https to work properly with attachments
      SIGNUPS_ALLOWED: "true" # Deactivate this with "false" after you have created your account so that no strangers can register
    volumes:
      - /opt/vaultwarden/vw-data:/data # the path before the : can be changed
    ports:
      - 80:80 # you can replace the first value with your preferred port
EOF

# Start vaultwarden
docker compose up -d

echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}vaultwarden installation completed!${NC}\n"
echo -e "${GREEN}Access vaultwarden at: ${ADDRESS}${NC}\n"
echo -e "${GREEN}To check service status: docker compose ps${NC}"
echo -e "${GREEN}To view logs: docker compose logs -f${NC}"
echo -e "${GREEN}To stop vaultwarden: docker compose down${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"
