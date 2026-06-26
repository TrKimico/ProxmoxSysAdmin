#!/bin/bash

# Find PHP version
php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

# Check current and latest version
current=$(sudo -u www-data php /var/www/nextcloud/occ status | grep versionstring | grep -oP '\d+\.\d+\.\d+')
latest=$(sudo -u www-data php /var/www/nextcloud/occ update:check 2>&1 | grep -oP 'Nextcloud \K[\d.]+' | head -1)

echo "Current version: $current"

if [[ -z "$latest" ]]; then
    echo "You already run the latest version ($current)"
    exit 0
else
    echo "Update available: $latest. Updating now."

    # Save enabled apps
    enabled_apps=$(sudo -u www-data php"$php_version" /var/www/nextcloud/occ app:list --output=json | grep -oP '(?<=")\w+(?=":)' | head -n -1)

    # Backup essentials
    mysqldump -u root nextcloud > ~/nextcloud.sql
    cd /var/www/nextcloud/
    tar -cpzvf ~/nextcloud-config.tar.gz config/

    # Upgrade Nextcloud
    cd /var/www/nextcloud/
    sudo -u www-data php"$php_version" updater/updater.phar --no-interaction

    # Post-upgrade routine
    sudo -u www-data php"$php_version" occ upgrade
    sudo -u www-data php"$php_version" occ db:add-missing-indices
    sudo -u www-data php"$php_version" occ db:convert-filecache-bigint

    # Re-enable apps
    for app in $enabled_apps; do
        sudo -u www-data php"$php_version" /var/www/nextcloud/occ app:enable "$app"
    done

    echo "Update complete. Now running $latest."
fi