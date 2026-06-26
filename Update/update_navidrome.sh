#!/bin/bash

# get the latest version number
latest=$(curl -s https://api.github.com/repos/navidrome/navidrome/releases/latest | grep -oP '"tag_name": "v\K[^"]*')
# download the latest version
wget https://github.com/navidrome/navidrome/releases/download/v${latest}/navidrome_${latest}_linux_amd64.tar.gz
# stop the service
systemctl stop navidrome
# extract the new version from archive
tar -xvzf navidrome_${latest}_linux_amd64.tar.gz -C /opt/navidrome/
# make it executable in the correct location
chown navidrome:navidrome /opt/navidrome/navidrome
# restart the service
systemctl start navidrome
# prune archive
rm navidrome_${latest}_linux_amd64.tar.gz