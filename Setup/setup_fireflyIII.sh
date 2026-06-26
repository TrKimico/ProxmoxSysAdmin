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
#   Update package list, install dependencies
#   Configure the database and the webserver
#   Install the service
#   Configure the service
####################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# visual aid
SEPARATOR="==========================="

set -e  # Exit on any error

# Configuration variables
FIREFLY_VERSION="6.4.16"
FIREFLY_URL="https://github.com/firefly-iii/firefly-iii/releases/download/v${FIREFLY_VERSION}/FireflyIII-v${FIREFLY_VERSION}.tar.gz"
INSTALL_DIR="/var/www/firefly-iii"
DB_NAME="firefly"
DB_USER="firefly"
DB_PASSWORD=$(openssl rand -base64 32)  # Generate random password
APP_KEY=""  # Will be generated later
software="fireflyIII"

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

################################################################################
# Step 1: Update System
################################################################################
echo -e "${YELLOW}[Step 1/13] Updating system packages...${NC}"
apt update
apt upgrade -y

################################################################################
# Step 1.5: Configure Locale
################################################################################
echo -e "${YELLOW}[Step 1.5/13] Configuring locale...${NC}"
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=fr_FR.UTF-8

################################################################################
# Step 2: Install Prerequisites
################################################################################
echo -e "${YELLOW}[Step 2/13] Installing prerequisites...${NC}"
apt install -y \
    apt-transport-https \
    lsb-release \
    ca-certificates \
    wget \
    curl \
    sudo \
    gnupg2 \
    unzip \
    git

################################################################################
# Step 3: Add PHP 8.4 Repository (Sury)
################################################################################
echo -e "${YELLOW}[Step 3/13] Adding PHP 8.4 repository...${NC}"
curl -sSL https://packages.sury.org/php/README.txt
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
apt update

################################################################################
# Step 4: Install PHP 8.4 and Required Extensions
################################################################################
echo -e "${YELLOW}[Step 4/13] Installing PHP 8.4 and extensions...${NC}"
apt install -y \
    php8.4 \
    php8.4-cli \
    php8.4-fpm \
    php8.4-mysql \
    php8.4-curl \
    php8.4-gd \
    php8.4-mbstring \
    php8.4-xml \
    php8.4-zip \
    php8.4-bcmath \
    php8.4-intl \
    libapache2-mod-php8.4

# Verify PHP version
php -v

################################################################################
# Step 5: Install MariaDB
################################################################################
echo -e "${YELLOW}[Step 5/13] Installing MariaDB...${NC}"
apt install -y mariadb-server mariadb-client

# Start and enable MariaDB
systemctl start mariadb
systemctl enable mariadb

################################################################################
# Step 6: Secure MariaDB and Create Database
################################################################################
echo -e "${YELLOW}[Step 6/13] Creating database and user...${NC}"

# Create database and user
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo -e "${GREEN}Database created successfully!${NC}"
echo -e "${GREEN}Database: ${DB_NAME}${NC}"
echo -e "${GREEN}User: ${DB_USER}${NC}"
echo -e "${GREEN}Password: ${DB_PASSWORD}${NC}"
echo -e "${YELLOW}IMPORTANT: Save these credentials!${NC}\n"

################################################################################
# Step 7: Install Apache
################################################################################
echo -e "${YELLOW}[Step 7/13] Installing Apache...${NC}"
apt install -y apache2

# Enable required Apache modules
a2enmod rewrite
a2enmod ssl
a2enmod headers

################################################################################
# Step 8: Install Composer
################################################################################
echo -e "${YELLOW}[Step 8/13] Installing Composer...${NC}"
cd /tmp
curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# Verify Composer
composer --version

################################################################################
# Step 9: Download Firefly III
################################################################################
echo -e "${YELLOW}[Step 9/13] Downloading Firefly III v${FIREFLY_VERSION}...${NC}"
cd /tmp
wget -O firefly-iii.tar.gz "${FIREFLY_URL}"

################################################################################
# Step 10: Extract and Setup Firefly III
################################################################################
echo -e "${YELLOW}[Step 10/13] Extracting Firefly III...${NC}"

# Create installation directory
mkdir -p ${INSTALL_DIR}

# Extract
tar -xzf firefly-iii.tar.gz -C ${INSTALL_DIR} --strip-components=1

# Clean up
rm firefly-iii.tar.gz

################################################################################
# Step 11: Configure Firefly III
################################################################################
echo -e "${YELLOW}[Step 11/13] Configuring Firefly III...${NC}"

# Copy environment file
cd ${INSTALL_DIR}
cp .env.example .env

# Generate APP_KEY
APP_KEY=$(php artisan key:generate --show)

# Configure .env file
sed -i "s|APP_ENV=.*|APP_ENV=production|g" .env
sed -i "s|APP_DEBUG=.*|APP_DEBUG=false|g" .env
sed -i "s|APP_KEY=.*|APP_KEY=${APP_KEY}|g" .env
sed -i "s|APP_URL=.*|APP_URL=http://localhost|g" .env
sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=mysql|g" .env
sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|g" .env
sed -i "s|DB_PORT=.*|DB_PORT=3306|g" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env

# Set proper permissions
chown -R www-data:www-data ${INSTALL_DIR}
chmod -R 775 ${INSTALL_DIR}/storage
chmod -R 775 ${INSTALL_DIR}/bootstrap/cache

# Install Composer dependencies
cd ${INSTALL_DIR}
sudo -u www-data composer install --no-dev --no-interaction

# Initialize database
sudo -u www-data php artisan migrate:fresh --seed --force
sudo -u www-data php artisan firefly-iii:upgrade-database
sudo -u www-data php artisan firefly-iii:correct-database
sudo -u www-data php artisan firefly-iii:report-integrity
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache

################################################################################
# Step 12: Configure Apache Virtual Host
################################################################################
echo -e "${YELLOW}[Step 12/13] Configuring Apache virtual host...${NC}"

cat > /etc/apache2/sites-available/firefly-iii.conf <<'APACHE_CONF'
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/firefly-iii/public

    <Directory /var/www/firefly-iii/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/firefly-iii-error.log
    CustomLog ${APACHE_LOG_DIR}/firefly-iii-access.log combined
</VirtualHost>
APACHE_CONF

# Disable default site and enable Firefly III
a2dissite 000-default.conf
a2ensite firefly-iii.conf

################################################################################
# Step 13: Restart Services
################################################################################
echo -e "${YELLOW}[Step 13/13] Restarting services...${NC}"
systemctl restart apache2
systemctl restart php8.4-fpm

################################################################################
# Installation Complete
################################################################################
echo -e "\n${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}\n"

echo -e "${GREEN}Firefly III has been successfully installed!${NC}\n"
echo -e "${YELLOW}Important Information:${NC}"
echo -e "Installation Directory: ${INSTALL_DIR}"
echo -e "Database Name: ${DB_NAME}"
echo -e "Database User: ${DB_USER}"
echo -e "Database Password: ${DB_PASSWORD}"
echo -e "APP_KEY: ${APP_KEY}\n"

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Access Firefly III at: ${SERVER_IP}"
echo -e "2. Create your first user account"
echo -e "3. Consider setting up SSL/TLS with Let's Encrypt"
echo -e "4. Update APP_URL in ${INSTALL_DIR}/.env if using a domain name\n"

echo -e "${YELLOW}IMPORTANT: Save the database credentials above!${NC}\n"

# Save credentials to file
cat > /root/firefly-iii-credentials.txt <<CREDS
Firefly III Installation Credentials
=====================================
Installation Date: $(date)
Version: ${FIREFLY_VERSION}

Database Information:
- Database Name: ${DB_NAME}
- Database User: ${DB_USER}
- Database Password: ${DB_PASSWORD}

Application:
- APP_KEY: ${APP_KEY}
- Installation Directory: ${INSTALL_DIR}
- .env file location: ${INSTALL_DIR}/.env

Access:
- URL: ${SERVER_IP}
CREDS

chmod 600 /root/firefly-iii-credentials.txt

echo -e "${GREEN}Credentials saved to: /root/firefly-iii-credentials.txt${NC}\n"
echo "Feel free to edit the credential file at /root/firefly-iii-credentials.txt with the URL of your reverse proxy"

#Clear Sensible Data From Memory
unset DB_PASSWORD 
unset APP_KEY