#!/bin/bash

####################################################
# Goal:
#   Update automatically the packages and the service of each LXC
#
# Global Variables:
#   None
#
# Requirements:
#   None
#
# Process:
#   Check if the container is running and has the right name
#   Detect the OS and update packages accordingly
#   If provided, execute the command to upgrade the specific service
#
# Setup:
#   Edit the first three arrays as follow, leave the other ones untouched:
#   - array containers: the number [number] and name "container0" of each container
#   - array version_commands: the command needed to retrieve the exact version of your service
#   - array service_update_commands : the commandline to upgrade the service if needed
####################################################

###########################################################
# VARIABLE DECLARATION
###########################################################

declare -A containers
declare -A version_commands
declare -A service_update_commands
declare -A os_pkg_update
declare -A os_pkg_upgrade

# --- containers array ---
containers["100"]="container0"
containers["101"]="container1"
containers["102"]="container2"
containers["103"]="container3"
containers["104"]="container4"
containers["105"]="container5"
containers["106"]="container6"
containers["107"]="container7"
containers["108"]="container8"
containers["109"]="container9"

# --- version_commands array ---
version_commands["100"]='command_to_find_the_version'
version_commands["101"]='command_to_find_the_version'
version_commands["102"]='command_to_find_the_version'
version_commands["103"]='command_to_find_the_version'
version_commands["104"]='command_to_find_the_version'
version_commands["105"]='command_to_find_the_version'
version_commands["106"]='command_to_find_the_version'
version_commands["107"]='command_to_find_the_version'
version_commands["108"]='command_to_find_the_version'
version_commands["109"]='command_to_find_the_version'

# --- service_update_commands array ---
# Service-specific update command for each container with some examples
service_update_commands["100"]='container0 -up' # specific software update command line
service_update_commands["101"]='' # updates through pkg update path, no specific command needed
service_update_commands["102"]=''
service_update_commands["103"]='cd /opt/app && docker compose pull && docker compose up -d' # docker update path
service_update_commands["104"]='cd /root/app && docker compose pull && docker compose up -d'
service_update_commands["105"]='cd /opt/app && docker-compose pull && docker-compose up -d'
service_update_commands["106"]=''
service_update_commands["107"]='yes | update' # updater script pre-installed with the software
service_update_commands["108"]=''
service_update_commands["109"]='/usr/local/bin/update-container9.sh' # handwritten script

# --- os_pkg_update array ---
# Maps the OS ID (from /etc/os-release) to its package index refresh command
# Add an entry here if your container runs a distro not listed below
os_pkg_update["debian"]='apt update -qq'
os_pkg_update["ubuntu"]='apt update -qq'
os_pkg_update["alpine"]='apk update'
os_pkg_update["arch"]='pacman -Sy'
os_pkg_update["fedora"]='dnf check-update'

# --- os_pkg_upgrade array ---
# Maps the OS ID (from /etc/os-release) to its full system upgrade command
# Add an entry here if your container runs a distro not listed below
# make sure that the commands accepts any dialog box automatically otherwise the script won't always run autonomously
os_pkg_upgrade["debian"]='DEBIAN_FRONTEND=noninteractive apt upgrade -y'
os_pkg_upgrade["ubuntu"]='DEBIAN_FRONTEND=noninteractive apt upgrade -y'
os_pkg_upgrade["alpine"]='apk upgrade'
os_pkg_upgrade["arch"]='pacman -Su --noconfirm'
os_pkg_upgrade["fedora"]='dnf upgrade -y'

# --- Log files ---
LOG_SUMMARY="/var/log/auto-update-summary.log"
LOG_VERBOSE="/var/log/auto-update-verbose.log"
LOG_ERROR="/var/log/auto-update-error.log"

###########################################################
# PROGRAM EXECUTION
###########################################################

# --- Create log files if they don't exist ---
touch "$LOG_SUMMARY" "$LOG_VERBOSE" "$LOG_ERROR"

# --- Header separator for this run ---
RUN_DATE=$(date "+%Y-%m-%d %H:%M:%S")
SEPARATOR="================================"

{
    echo "$SEPARATOR"
    echo "Starting : $RUN_DATE"
    echo "$SEPARATOR"
} | tee -a "$LOG_SUMMARY" >> "$LOG_VERBOSE"
echo "$SEPARATOR" >> "$LOG_ERROR"
echo "Starting : $RUN_DATE" >> "$LOG_ERROR"
echo "$SEPARATOR" >> "$LOG_ERROR"

for id in $(echo "${!containers[@]}" | tr ' ' '\n' | sort -n); do
    read status current_name < <(pct list 2>/dev/null | awk -v id="$id" '$1==id {print $2, $3}')
    name="${containers[$id]}"

    if [[ "$status" == "running" && "$current_name" == "$name" ]]; then
        echo "✔ Container $id ($name) is running." >> "$LOG_VERBOSE"
        # ================================================================= distro update / upgrade
        # --- OS detection ---
        os_id=$(pct exec "$id" -- bash -c 'source /etc/os-release && echo $ID' 2>>"$LOG_ERROR")
        if [[ -z "${os_pkg_update[$os_id]}" ]]; then
            echo "✘ Container $id ($name) : unsupported or undetected OS ($os_id), skipping package update." | tee -a "$LOG_VERBOSE" >> "$LOG_ERROR"
            continue
        fi
        echo "  → detected OS : $os_id" >> "$LOG_VERBOSE"

        # --- Package index refresh ---
        echo "  → package index refresh..." >> "$LOG_VERBOSE"
        pct exec "$id" -- bash -c "${os_pkg_update[$os_id]}" >> "$LOG_VERBOSE" 2>>"$LOG_ERROR"

        # --- System package upgrade ---
        echo "  → package upgrade (system)..." >> "$LOG_VERBOSE"
        pct exec "$id" -- bash -c "${os_pkg_upgrade[$os_id]}" >> "$LOG_VERBOSE" 2>>"$LOG_ERROR"

        # ================================================================= service update
        # --- Service Version before update ---
        v_before=$(pct exec "$id" -- bash -c "${version_commands[$id]}" 2>>"$LOG_ERROR")
        if [[ -n "$v_before" ]]; then
            echo "  → Before version : $v_before" >> "$LOG_VERBOSE"
        else
            echo "  → Before version : cannot be retrieved" >> "$LOG_VERBOSE"
        fi

        # --- Service-specific update (if defined) ---
        if [[ -n "${service_update_commands[$id]}" ]]; then
            echo "  → service update..." >> "$LOG_VERBOSE"
            pct exec "$id" -- bash -c "${service_update_commands[$id]}" >> "$LOG_VERBOSE" 2>>"$LOG_ERROR"
        fi

        # --- Version after update ---
        v_after=$(pct exec "$id" -- bash -c "${version_commands[$id]}" 2>>"$LOG_ERROR")
        if [[ -n "$v_after" ]]; then
            echo "  → After Version  : $v_after" >> "$LOG_VERBOSE"
        else
            echo "  → After Version  : cannot be retrieved" >> "$LOG_VERBOSE"
        fi
        # ================================================================= Recap
        if [[ "$v_before" != "$v_after" ]]; then
            echo "✅  Successfully updated : $v_before ➡️ $v_after" >> "$LOG_VERBOSE"
            echo "✅  $name ($id) : $v_before ➡️ $v_after" >> "$LOG_SUMMARY"
        else
            echo "ℹ️  Already up to date ($v_after)" >> "$LOG_VERBOSE"
            echo "ℹ️  $name ($id) : Already up to date ($v_after)" >> "$LOG_SUMMARY"
        fi

    else
        echo "❌  Container $id ($name) isn't available (status: ${status:-inconnu})" >> "$LOG_VERBOSE"
        echo "❌  $name ($id) : isn't available (status: ${status:-inconnu})" >> "$LOG_SUMMARY"
    fi

    echo "" >> "$LOG_VERBOSE"
done

echo "" >> "$LOG_SUMMARY"
echo "" >> "$LOG_VERBOSE"
echo "" >> "$LOG_ERROR"