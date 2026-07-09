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
#   Install dependencies and update package list
#   Configure the webserver and the database
#   Start the service
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="
software="Nextcloud"

set -e  # Exit on any error

# Start Installation
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN} Starting ${software} installation${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}\n"


# Function to validate IP address format
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        echo "ERROR: Invalid IP address format: $ip"
        return 1
    fi
}

# Determine the IP address of the interface which contains the default gateway
# This is a relatively sure bet to be the IP address that the service can be accessed on, for later display
GATEWAY_IFACE="$( ip route \
                  | grep '^default' \
                  | head -1 \
                  | grep -o 'dev [a-z0-9]* ' \
                  | awk '{ print $NF }' )"
SERVER_IP="$( ip address show dev "${GATEWAY_IFACE}" \
               | grep -w "inet .* ${GATEWAY_IFACE}$" \
               | awk '{ print $2 }' \
               | awk -F '/' '{ print $1 }' )"

# Prompt for variables
#echo ""
#read -p "Enter the server IP address for NextCloud: " SERVER_IP
#validate_ip "$SERVER_IP" || exit 1
echo ""
read -s -p "Enter MariaDB root password (for database setup): " MYSQL_ROOT_PASSWORD
echo ""
read -s -p "Enter NextCloud database user password: " NEXTCLOUD_DB_PASSWORD
echo ""

# Optional confirmation for passwords
read -p "Proceed with installation? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo "=== Starting installation... ==="

# Update system
echo "Updating package lists..."
apt update && apt upgrade -y

# Install required packages
echo "Installing Apache, MariaDB, PHP and dependencies..."
apt install -y apache2 mariadb-server php php-mysql php-gd php-json php-curl \
    php-mbstring php-intl php-imagick php-xml php-zip php-apcu php-redis \
    redis-server wget

# Download and extract NextCloud
echo "Downloading NextCloud..."
wget -q https://download.nextcloud.com/server/releases/latest.tar.bz2
echo "Extracting NextCloud to /var/www/..."
tar -xjf latest.tar.bz2 -C /var/www/
rm latest.tar.bz2

# Set permissions
echo "Setting permissions..."
chown -R www-data:www-data /var/www/nextcloud

# Enable Apache modules
echo "Configuring Apache modules..."
a2enmod rewrite headers env dir mime

# STOP Apache first to avoid port conflicts
echo "Stopping Apache to avoid port conflicts..."
systemctl stop apache2 || true

# Create Apache configuration
echo "Creating Apache VirtualHost configuration..."
cat > /etc/apache2/sites-available/nextcloud.conf << EOF
<VirtualHost *:80>
    DocumentRoot /var/www/nextcloud
    ServerName $SERVER_IP

    <Directory /var/www/nextcloud>
        Options FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

# Disable default site FIRST, then enable NextCloud site
echo "Configuring Apache sites..."
a2dissite 000-default.conf 2>/dev/null || true
a2ensite nextcloud.conf

# Now start Apache with the new configuration
echo "Starting Apache with NextCloud configuration..."
systemctl start apache2

# Check if Apache started successfully
if systemctl is-active --quiet apache2; then
    echo "Apache is running successfully."
else
    echo "ERROR: Apache failed to start. Checking logs..."
    systemctl status apache2
    journalctl -xeu apache2.service --no-pager | tail -50
    exit 1
fi

# Configure MariaDB database
echo "Setting up MariaDB database..."

# Try to connect to MariaDB with provided root password
if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
    echo "ERROR: Could not connect to MariaDB with provided root password."
    echo "Please ensure MariaDB root password is correct."
    exit 1
fi

# Execute database setup commands
mysql -u root -p"$MYSQL_ROOT_PASSWORD" << EOF
CREATE DATABASE IF NOT EXISTS nextcloud;
CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
EOF

# Enable the service system-wide for easier reboot
systemctl enable apache2

echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}Installation complete!${NC}\n"
echo -e "${GREEN}Summary:${NC}"
echo -e "${GREEN}  NextCloud installed at: /var/www/nextcloud${NC}"
echo -e "${GREEN}  Server IP: ${SERVER_IP}${NC}"
echo -e "${GREEN}  Database name: nextcloud${NC}"
echo -e "${GREEN}  Database user: nextcloud${NC}\n"
echo -e "${GREEN}Access NextCloud at: http://${SERVER_IP}${NC}\n"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "${YELLOW}1. Complete the web-based NextCloud setup wizard${NC}"
echo -e "${YELLOW}2. Consider setting up SSL/TLS for secure connections${NC}"
echo -e "${YELLOW}3. Configure memory caching for better performance${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"

# Clear password variables from memory
unset MYSQL_ROOT_PASSWORD
unset NEXTCLOUD_DB_PASSWORD