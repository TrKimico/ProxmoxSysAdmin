#!/bin/bash

####################################################
# Goal:
#   Install the software and make it run as a service
#   (meant to run on a server)
#
# Global Variables:
#   - Console output coloring
#   - Network Identification
#
# Requirements
#   A Debian-based system
#   Root priviledge 
#
# Process:
#   Install Dependencies
#   Set Timezone
#   Install the service
#   Start the service
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="
# Software Name
SOFTWARE="ZoneMinder"

set -e  # Exit on any error

# Network Identification
GATEWAY_IFACE="$( ip route \
                  | grep '^default' \
                  | head -1 \
                  | grep -o 'dev [a-z0-9]* ' \
                  | awk '{ print $NF }' )"
IP_ADDRESS="$( ip address show dev "${GATEWAY_IFACE}" \
               | grep -w "inet .* ${GATEWAY_IFACE}$" \
               | awk '{ print $2 }' \
               | awk -F '/' '{ print $1 }' )"
PORT="80"

# Debconf preseeding for non-interactive zoneminder install
ZM_DB_PASS_FILE="/root/.zm_db_pass"
if [ -f "$ZM_DB_PASS_FILE" ]; then
    ZM_DB_PASS="$(cat "$ZM_DB_PASS_FILE")"
else
    ZM_DB_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
    echo "$ZM_DB_PASS" > "$ZM_DB_PASS_FILE"
    chmod 600 "$ZM_DB_PASS_FILE"
fi

export DEBIAN_FRONTEND=noninteractive

debconf-set-selections <<EOF
zoneminder zoneminder/dbconfig-install boolean true
zoneminder zoneminder/mysql/admin-pass password
zoneminder zoneminder/mysql/method select unix socket
zoneminder zoneminder/remote/host string localhost
zoneminder zoneminder/db/dbname string zm
zoneminder zoneminder/db/app-user string zmuser
EOF

# initial steps
# Start Installation
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN} Starting ${SOFTWARE} installation${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}\n"

# Update packages list
apt update && apt upgrade -y
# Install Dependencies
apt install -y apache2 mariadb-server php libapache2-mod-php php-mysql systemd-timesyncd lsb-release gnupg2 sudo curl debconf-utils

# Set Timezone
TZ=$(curl -s --max-time 5 "http://ip-api.com/line/?fields=timezone")
[ -z "$TZ" ] && TZ="Etc/UTC"
timedatectl set-timezone "$TZ"
sed -i "s|;date.timezone =.*|date.timezone = ${TZ}|" /etc/php/8.4/apache2/php.ini


# Install Zoneminder
tee /etc/apt/sources.list.d/zoneminder.list > /dev/null <<EOF
deb https://zmrepo.zoneminder.com/debian/release-1.38 $(lsb_release -c -s)/
EOF
wget -O- https://zmrepo.zoneminder.com/debian/archive-keyring.gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/zmrepo.gpg
apt update
apt install -y zoneminder
ZM_DB_PASS="$(grep '^ZM_DB_PASS' /etc/zm/zm.conf | cut -d= -f2)"
echo "$ZM_DB_PASS" > "$ZM_DB_PASS_FILE"
chmod 600 "$ZM_DB_PASS_FILE"

# Make Zoneminder run as a service
systemctl enable zoneminder
service zoneminder start

# Enable login (default admin/admin credentials, change later)
mariadb -u zmuser -p"${ZM_DB_PASS}" zm -e \
  "UPDATE Config SET Value=1 WHERE Name='ZM_OPT_USE_AUTH';"

# Configure Zoneminder
adduser www-data video
a2enconf zoneminder
a2enmod rewrite
a2enmod headers
a2enmod expires

# redirect to the /zm index automatically to avoid the default page
echo "RedirectMatch ^/$ /zm/" > /etc/apache2/conf-available/zm-redirect.conf
a2enconf zm-redirect

# Set the correct timezone in the database manually
mariadb-tzinfo-to-sql /usr/share/zoneinfo | mysql -u root mysql
mariadb -e "SET GLOBAL time_zone = '${TZ}';"
sed -i "/^bind-address            = 127.0.0.1/a default-time-zone       = \"${TZ}\"" /etc/mysql/mariadb.conf.d/50-server.cnf
service mariadb restart

# reload the webserver to enable all changes
service apache2 reload

# Finish Message
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}${SOFTWARE} installation completed!${NC}\n"
echo -e "${GREEN}Access ${SOFTWARE} at: http://${IP_ADDRESS}:${PORT}${NC}\n"
echo -e "${GREEN}ZoneMinder DB user 'zmuser' password: ${ZM_DB_PASS}${NC}"
echo -e "${GREEN}(also saved at ${ZM_DB_PASS_FILE})${NC}"
echo -e ""
echo -e "${YELLOW}Auth enabled with default admin/admin — change this in Options > Users${NC}"
echo -e ""
echo -e "${GREEN}To check service status: systemctl status apache2${NC}"
echo -e "${GREEN}To view logs           : journalctl -u zoneminder -f${NC}"
echo -e "${GREEN}To stop ${SOFTWARE}     : systemctl stop apache2${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"