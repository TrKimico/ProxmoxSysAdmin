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
#   Set the database password
#   Remove any remaining Docker version and install it fresh
#   Fetch the docker yml config file
#   Configure the local .env file
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
software="Immich"
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

echo ""
read -s -p "Enter Immich database user password: " IMMICH_DB_PASSWORD
echo ""

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

# Create and navigate to immich directory
mkdir -p ./immich-app
cd ./immich-app

# Download Immich docker-compose file
wget -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml

# Create .env file with configuration
cat > .env << EOF
# You can find documentation for all the supported env variables at https://docs.immich.app/install/environment-variables

# The location where your uploaded files are stored
UPLOAD_LOCATION=./library

# The location where your database files are stored. Network shares are not supported for the database
DB_DATA_LOCATION=./postgres

# To set a timezone, uncomment the next line and change Etc/UTC to a TZ identifier from this list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List
TZ=FR

# The Immich version to use. You can pin this to a specific version like "v2.1.0"
IMMICH_VERSION=v2

# Connection secret for postgres. You should change it to a random password
# Please use only the characters `A-Za-z0-9`, without special characters or spaces
DB_PASSWORD=${IMMICH_DB_PASSWORD}

# The values below this line do not need to be changed
###################################################################################
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
EOF

# Start Immich
docker compose up -d

echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}Immich installation completed!${NC}\n"
echo -e "${GREEN}Access Immich at: http://${IP_ADDRESS}:2283${NC}\n"
echo -e "${GREEN}To check service status: docker compose ps${NC}"
echo -e "${GREEN}To view logs: docker compose logs -f${NC}"
echo -e "${GREEN}To stop Immich: docker compose down${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"

# Clear password variables from memory
unset IMMICH_DB_PASSWORD