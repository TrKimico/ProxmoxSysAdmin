#!/usr/bin/env bash
####################################################
# Goal:
#   Install the software and make it run as a service
#   (meant to run on a server)
#
# Global Variables:
#   Visual aid and network variables
#
# Requirements
#   A Debian-based / unprivileged /configured container
#   how to set it up ON HOST, not inside the LXC:
# 1. Fix - allow the device type and bind-mount it into the container.
#    Edit /etc/pve/lxc/<CTID>.conf and add:
#      lxc.cgroup2.devices.allow: c 10:200 rwm                               THIS
#      lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file       THIS
# 2. Restart the container:
#      pct stop <CTID> && pct start <CTID>                                   THIS
#
# Process:
#    check for requirements
#    enable ip forwarding
#    download and install the service
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

if [[ ! -e /dev/net/tun ]]; then
  echo "ERROR: /dev/net/tun not found inside this container." >&2
  echo "This means the host-side LXC config (cgroup2.devices.allow +" >&2
  echo "mount.entry for /dev/net/tun) has not been applied and the" >&2
  echo "container has not been restarted since. See the header of this" >&2
  echo "script for the exact host-side steps, then re-run." >&2
  exit 1
fi

apt-get update -y

# WGDashboard now requires Python 3.12+. Adjust below if your base image
# doesn't ship it (e.g. add deadsnakes PPA on older Ubuntu).
apt-get install -y wireguard-tools python3 python3-pip python3-venv git net-tools iptables qrencode sudo

PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
if ! python3 -c 'import sys; exit(0 if sys.version_info >= (3, 12) else 1)'; then
  echo "WARNING: WGDashboard requires Python 3.12+. You have $PY_VERSION." >&2
  echo "The install may fail or you'll need to install a newer Python" >&2
  exit 1
fi

# enabling IP forwarding
if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! sysctl -p /etc/sysctl.conf 2>/dev/null; then
  echo "WARNING: sysctl -p failed to apply inside the container." >&2
  echo "This can happen in unprivileged containers depending on what" >&2
  echo "the host exposes via /proc/sys. If forwarding doesn't work later," >&2
  echo "set net.ipv4.ip_forward=1 on the PROXMOX HOST as well." >&2
  exit 1
fi

CURRENT_FWD=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "unknown")
echo "${YELLOW}Current ip_forward value: ${CURRENT_FWD}${NC}"

# clone WGDashboard
INSTALL_DIR="${HOME}/WGDashboard"
if [[ -d "$INSTALL_DIR" ]]; then
  echo "    $INSTALL_DIR already exists, skipping clone."
else
  git clone https://github.com/WGDashboard/WGDashboard.git "$INSTALL_DIR"
fi
# move to the correct directory and make it executable
cd "$INSTALL_DIR/src"
chmod +x ./wgd.sh

# install WGDashboard
./wgd.sh install

# start WGDashboard
if ./wgd.sh start; then
  echo -e "${GREEN}${SEPARATOR}${NC}"
  echo -e "${GREEN} Installation successful! You can now access ${software} at ${SERVER_IP}:10086${NC}"
  echo -e "${YELLOW}Default login: admin / admin  (change this immediately)${NC}"
  echo -e "${YELLOW}Sanity checks if something's not working:${NC}"
  echo -e "${YELLOW}ip link show wg0                    # interface exists? ${NC}"
  echo -e "${YELLOW}wg show                             # any wg interfaces up?${NC}"
  echo -e "${YELLOW}cat /proc/sys/net/ipv4/ip_forward   # should print 1${NC}"
  echo -e "${GREEN}${SEPARATOR}${NC}"
else
    echo -e "${RED}WGDashboard startup failed${NC}"
    exit 1
fi