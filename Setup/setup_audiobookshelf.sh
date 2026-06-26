#!/bin/bash

####################################################
# Goal:
#   Install the software and make it run as a service
#   (meant to run on a server)
#
# Global Variables:
#   None
#
# Requirements:
#   Running a debian based system
#   AMD64 architecture
#
# Process:
#   Update the package list and install dependencies
#   Activate the software's repository
#   Install the software
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="

set -e  # Exit on any error

# Set local variables
software="Audiobookshelf"
GATEWAY_IFACE="$( ip route \
                  | grep '^default' \
                  | head -1 \
                  | grep -o 'dev [a-z0-9]* ' \
                  | awk '{ print $NF }' )"
SERVER_IP="$( ip address show dev "${GATEWAY_IFACE}" \
               | grep -w "inet .* ${GATEWAY_IFACE}$" \
               | awk '{ print $2 }' \
               | awk -F '/' '{ print $1 }' )"

# Start Installation
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN} Starting ${software} installation${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}\n"

# Update package list and install dependencies
echo -e "${YELLOW}Step 1/3 : updating packages list & installing tools${NC}"
apt update -qq && apt upgrade -y
apt install gnupg curl wget -y
apt update -qq && apt upgrade -y

# Activate the repository
echo -e "${YELLOW}Step 2/3 : activate the software's repository${NC}"
wget -O- https://advplyr.github.io/audiobookshelf-ppa/KEY.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adb-archive-keyring.gpg
curl -s -o /etc/apt/sources.list.d/audiobookshelf.list https://advplyr.github.io/audiobookshelf-ppa/audiobookshelf.list

# Install Audiobookshelf
echo -e "${YELLOW}Step 3/3 : install the service ${NC}"
apt update && apt upgrade -y
apt install audiobookshelf && \
    echo -e "${GREEN}${SEPARATOR}${NC}"
    echo -e "${GREEN} Installation successful! you may now access ${software} at ${SERVER_IP}:13378${NC}"
    echo -e "${GREEN}${SEPARATOR}${NC}"