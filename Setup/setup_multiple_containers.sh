#!/bin/bash

#######################################
# SETUP
#######################################

# define visual cues for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
SEPARATOR="==========================="

# define useful variables
NOTES_FILE="/root/auto_install_notes.log"
LOG_FILE="/root/auto_install_output.log"
TEMPLATE=$(pveam available | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)
GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
PVE_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
BASE_IP=$(echo "$PVE_IP" | cut -d. -f1-3)
EXCLUDE=(50)   # reserved for Proxmox itself
# helper: find the next free IP in BASE_IP.11-99, skipping EXCLUDE, checking both existing configs and live ping
# NOTE: assumes a /24 subnet and only scans the .11-.99 range - won't find
# addresses outside that window (e.g. smaller subnets, or sites needing
# more than ~89 CTs). Adjust the seq range or BASE_IP logic if a site's
# addressing scheme doesn't fit this assumption.
find_free_ip() {
    for i in $(seq 11 99); do
        if [[ " ${EXCLUDE[@]} " =~ " $i " ]]; then
            continue
        fi
        candidate="${BASE_IP}.${i}"

        if grep -rq "ip=${candidate}/" /etc/pve/lxc/ /etc/pve/qemu-server/ 2>/dev/null; then
            continue
        fi
        if ping -c 1 -W 1 "$candidate" &>/dev/null; then
            continue
        fi

        echo "$candidate"
        return 0
    done
    return 1
}

#######################################
# PROGRAM EXECUTION
#######################################

# install dependencies
apt install jq -y -qq >> "$LOG_FILE" 2>&1

# list the available storage devices for template install
mapfile -t montedstorageslist < <(pvesm status --content vztmpl 2>/dev/null | awk 'NR>1 {print $1}')
# build tag/description pairs for whiptail
menu_items=()
for storage in "${montedstorageslist[@]}"; do
    menu_items+=("$storage" "")
done
# whiptail : select the storage on which the CT template will be stored/downloaded
TEMPLATE_STORAGE=$(whiptail --title "Choosing Template Storage" --menu "On which of these devices should the container template be stored?" 25 78 16 \
"${menu_items[@]}" 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    echo -e "${GREEN}You selected: ${TEMPLATE_STORAGE}${NC}"
else
    echo -e "${RED}User canceled input.${NC}"
    exit 1
fi

# list the available storage devices for container rootfs
mapfile -t rootfsstoragelist < <(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 {print $1}')
# build tag/description pairs for whiptail
rootfs_menu_items=()
for storage in "${rootfsstoragelist[@]}"; do
    rootfs_menu_items+=("$storage" "")
done
# whiptail : select the storage on which you wish to install the containers' root filesystem
ROOTFS_STORAGE=$(whiptail --title "Choosing Installation Storage" --menu "On which of these devices do you wish to install the services (container rootfs)?" 25 78 16 \
"${rootfs_menu_items[@]}" 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    echo -e "${GREEN}You selected: ${ROOTFS_STORAGE}${NC}"
else
    echo -e "${RED}User canceled input.${NC}"
    exit 1
fi

# check the list of templates available for the latest Debian
pveam update >> "$LOG_FILE" 2>&1
if [[ -z "$(pveam available 2>>"$LOG_FILE" | grep debian-13)" ]] ; then
    echo -e "${YELLOW}The latest Debian template isn't installed, downloading it...${NC}"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >> "$LOG_FILE" 2>&1
else
    echo -e "${GREEN}Recent Debian template found, checking for exact version${NC}"
    # download it locally on the chosen storage if not already cached there
    if ! pveam list "$TEMPLATE_STORAGE" 2>>"$LOG_FILE" | grep -q "$TEMPLATE"; then
        echo -e "${YELLOW}Downloading the exact version${NC}"
        pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >> "$LOG_FILE" 2>&1
    else
        echo -e "${GREEN}Latest Debian template already installed${NC}"
    fi
fi

# Prepare the services to install with Whiptail
mapfile -t servicenames < <(curl -s "https://api.github.com/repos/TrKimico/ProxmoxSysAdmin/contents/Setup/Services" \
  | jq -r '.[] | select(.type == "file") | .name' \
  | sed -E 's/^setup_//; s/\.sh$//')
# Generate the whiptail menu items
checklist_items=()
for service in "${servicenames[@]}"; do
    checklist_items+=("$service" "" "OFF")
done
# WHIPTAIL checklist menu where the user can select which services they wish to install
SERVICES=$(whiptail --title "Choosing Services" --checklist "Which services should be installed?" 25 78 16 \
"${checklist_items[@]}" 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    echo -e "${GREEN}You selected: $SERVICES${NC}"
else
    echo -e "${RED}User canceled input.${NC}"
    exit 1
fi
# parse the whiptail checklist output into an array
eval "selected_services=($SERVICES)"

# start deploying CTs
echo "=== CT deployment run $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$NOTES_FILE"

for service in "${selected_services[@]}"; do
    CTID=$(pvesh get /cluster/nextid)
    IP=$(find_free_ip)
    if [ -z "$IP" ]; then
        echo "No free IP available for $service, skipping."
        continue
    fi
    PASSWORD=$(openssl rand -base64 12)

    echo -e "${YELLOW}Creating CT $CTID ($service) at $IP ...${NC}"

    pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
        --hostname "$service" \
        --cores 2 \
        --memory 2048 \
        --swap 512 \
        --rootfs "${ROOTFS_STORAGE}:8" \
        --net0 name=eth0,bridge=vmbr0,ip=${IP}/24,gw=${GATEWAY},firewall=1 \
        --unprivileged 1 \
        --features nesting=1 \
        --password "$PASSWORD" \
        --onboot 1 \
        --start 0 >> "$LOG_FILE" 2>&1
    CREATE_STATUS=$?

    if [ "$CREATE_STATUS" -ne 0 ]; then
        echo -e "${RED}CT creation failed for $service (CTID $CTID), see $LOG_FILE${NC}"
        INSTALL_STATUS="failed (pct create error)"
        # append to the recap log
        {
            echo "Service:  $service"
            echo "Install:  $INSTALL_STATUS"
            echo "$SEPARATOR"
        } >> "$NOTES_FILE"
        continue
    else
        echo -e "${GREEN}CT creation successful for $service${NC}"
    fi
    # --- wireguard-specific host-side prep, before first start ---
    if [ "$service" == "wireguard" ]; then
        echo -e "${YELLOW}Applying host-side tun device config for CT $CTID ...${NC}"

        modprobe wireguard 2>>"$LOG_FILE"
        if ! lsmod | grep -q wireguard; then
            echo -e "${RED}wireguard kernel module failed to load on host, skipping $service${NC}"
            INSTALL_STATUS="failed (host module missing)"
            {
                echo "Service:  $service"
                echo "CTID:     $CTID"
                echo "Install:  $INSTALL_STATUS"
                echo "$SEPARATOR"
            } >> "$NOTES_FILE"
            continue
        fi

        cat >> "/etc/pve/lxc/${CTID}.conf" <<EOF
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
    fi

    pct start "$CTID" >> "$LOG_FILE" 2>&1
    # wait for the container's network to actually be reachable before
    # trying to fetch/run the install script inside it
    echo -e "${YELLOW}Waiting for network in CT $CTID ...${NC}"
    network_ready=0
    for attempt in $(seq 1 15); do
        if pct exec "$CTID" -- ping -c 1 -W 1 8.8.8.8 >> "$LOG_FILE" 2>&1; then
            network_ready=1
            break
        fi
        sleep 2
    done

    INSTALL_STATUS="skipped (no network)"
    if [ "$network_ready" = 1 ]; then
        echo -e "${GREEN}Connection established in CT $CTID ...${NC}"
        # install curl to be able to fetch the install script
        pct exec "$CTID" -- bash -c "apt-get update -qq && apt-get install -y -qq curl" >> "$LOG_FILE" 2>&1

        RAW_URL="https://raw.githubusercontent.com/TrKimico/ProxmoxSysAdmin/main/Setup/Services/setup_${service}.sh"
        echo -e "${YELLOW}Running install script for $service in CT $CTID ...${NC}"
        if pct exec "$CTID" -- bash -c "set -o pipefail; curl -fsSL ${RAW_URL} | bash" >> "$LOG_FILE" 2>&1; then
            INSTALL_STATUS="success"
            echo -e "${GREEN}Install script for $service in CT $CTID ran successfully${NC}"
        else
            INSTALL_STATUS="failed"
            echo -e "${RED}Install script for $service in CT $CTID failed${NC}"
        fi
    else
        echo -e "${RED}Network never came up in CT $CTID, skipping install script.${NC}"
    fi

    # append to the recap log
    {
        echo "Service:  $service"
        echo "CTID:     $CTID"
        echo "IP:       $IP/24"
        echo "Port: "
        echo "Gateway:  $GATEWAY"
        echo "Password: $PASSWORD"
        echo "Install:  $INSTALL_STATUS"
        echo "$SEPARATOR"
    } >> "$NOTES_FILE"

    # exclude this IP's last octet from further picks in this same run
    EXCLUDE+=("$(echo "$IP" | cut -d. -f4)")
done
echo -e "${GREEN}${SEPARATOR}${NC}"
echo -e "${GREEN}The install process succeeded. See $NOTES_FILE for the recap and $LOG_FILE for full command output.${NC}"
echo -e "${GREEN}${SEPARATOR}${NC}"
