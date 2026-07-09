#!/bin/bash

####################################################
# IMPORTANT NOTE
# This script isn't my own and comes from the official Jellyfin documentation,
# You'll find it here for convenience, do go read the content of the script for yourself
# at https://jellyfin.org/docs/general/installation/linux/
# I didn't feel the need to write it for myself as it's very thorough
#
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
set -o pipefail # Exit if pipes fail

# Check that we're root; if not, fail out
if [[ $(whoami) != "root" ]]; then
    echo -e "${RED}ERROR: This script must be run as 'root' or with 'sudo' to function.${NC}"
    exit 1
fi

# Set local variables
software="Jellyfin"
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
apt install -y curl

# fetch the official repo install script and verify it
curl -sf https://repo.jellyfin.org/install-debuntu.sh -O && \
curl -s https://repo.jellyfin.org/install-debuntu.sh.sha256sum -O && \
if ! sha256sum -c install-debuntu.sh.sha256sum; then
    echo -e "${RED} Integrity check failed, check the source or try another download path.${NC}"
    exit 1
fi

# run it
if bash install-debuntu.sh; then
    echo -e "${GREEN}${SEPARATOR}${NC}"
    echo -e "${GREEN} Installation successful! You can now access ${software} at ${SERVER_IP}:8096${NC}"
    echo -e "${GREEN}${SEPARATOR}${NC}"
    rm install-debuntu.sh
else
    echo -e "${RED}Installation failed.${NC}"
    exit 1
fi

# remove install files (the install scripts delets itself)
rm install-debuntu.sh.sha256sum