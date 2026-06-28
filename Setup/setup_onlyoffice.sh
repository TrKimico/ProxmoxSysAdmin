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
#   Download dependencies
#   Configure the database and the webserver
#   Configure and start the service
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="

# Set local variables
software="Onlyoffice"
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

# fix ipv6 connectivity
echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf

# make sure everything is up to date
apt update -qq && apt upgrade -y

#Install the PostgreSQL version included in your version of Ubuntu/Debian
apt-get install gpg curl sudo postgresql -y

#After PostgreSQL is installed, create the PostgreSQL database and user:
#     The database user must have the onlyoffice name. You can specify any password.
sudo -i -u postgres psql -c "CREATE USER onlyoffice WITH PASSWORD 'onlyoffice';"
sudo -i -u postgres psql -c "CREATE DATABASE onlyoffice OWNER onlyoffice;"

#Installing rabbitmq:
apt-get install rabbitmq-server -y

#install potentially necessary dependencies
apt-get install nginx-extras -y

# Please write the port number instead of the <PORT_NUMBER> in the above command, skip to keep it default (80)
echo onlyoffice-documentserver onlyoffice/ds-port select 80 | debconf-set-selections

#Add GPG key
mkdir -p -m 700 ~/.gnupg
curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --no-default-keyring --keyring gnupg-ring:/tmp/onlyoffice.gpg --import
chmod 644 /tmp/onlyoffice.gpg
chown root:root /tmp/onlyoffice.gpg
mv /tmp/onlyoffice.gpg /usr/share/keyrings/onlyoffice.gpg

#Add Onlyoffice docx repository
echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" | tee /etc/apt/sources.list.d/onlyoffice.list

#Update the package manager cache
apt-get update

#installe mscorefonts
apt-get install ttf-mscorefonts-installer -y

#install ONLYOFFICE docs
#      During the installation process, you will be asked to provide a password for the onlyoffice PostgreSQL user. 
#      Please enter the onlyoffice password that you have specified when configuring PostgreSQL.
apt-get install onlyoffice-documentserver -y

#Activate the service system-wide for easier reboot
systemctl enable nginx

# Cleanly exit script
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN} Installation successful! you may now access ${software} at ${IP_ADDRESS}:80${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"
