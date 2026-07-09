#!/bin/bash

####################################################
# Goal:
#   Install the software and make it run as a service
#   (meant to run on a server)
#
# Global Variables:
#   Visual cues
#   Network exploration variables
#
# Requirements:
#   Running a debian based system
#   AMD64 architecture
#
# Process:
#   Update the package list and install dependencies
#   Fetch the official install script
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
software="Pi-Hole"
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

# update packages list
apt update -qq && apt upgrade -y

# install dependencies
apt install curl wget -y

# install pi-hole
if wget -O basic-install.sh https://install.pi-hole.net; then
    echo -e "${GREEN}${SEPARATOR}${NC}"
# I didn't start the setup right away because it would pop up a whiptail menu that is incompatible with scripting from host
    echo -e "${GREEN}Installation successful! you may now run 'bash basic-install.sh' to start the simplified configuraiton protocol${NC}"
    echo -e "${GREEN} You will then be able to access ${software} at ${SERVER_IP}${NC}"
    echo -e "${GREEN}${SEPARATOR}${NC}"
else
    echo -e "${RED}Archive download failed.${NC}"
    exit 1
fi