# **Proxmox Admin Project**
This project is meant to grow as I document all the means to download and maintain my Proxmox infrastructure. The project is made of two main directories : 
- Setup  : contains the install scripts for each service.
- Update : contains the update scripts for the services that can't be upgraded with a single line of code provided by the vendor.

⚠️⚠️ **Always** double check scripts found online before running them on your machine. The files provided here come with no warranty whatsoever. ⚠️⚠️

## **Why this Project?**
The Proxmox community already has a long list of install scripts available in a dedicated repository, but they're very long and opaque for someone who isn't versed in the ways of bash scripting. These scripts, on the other hand directly compile software from source or with docker, and are as short as possible, making them easy to audit and learn from. This project also allows me to improve at writing scripts, feel free to point out weaknesses.

## **Recommended Architecture**
It's strongly recommended not to install these software directly into your Proxmox node, but in a dedicated LXC (LinuX Container) or VM (Virtual Machine) with a one machine = one software logic. This logic of containerization makes it easy to :
- delete an LXC if something went wrong during the install and starting fresh in a few minutes
- separating concerns; if there is something wrong with Apache (software used to host webservers), it will only be disrupting one service, not the whole architecture.
- easier debugging; if a service isn't working, the source of the problem is easier to pin down.

## **Available Scripts**
```
├── Setup
│   ├── setup_audiobookshelf.sh
│   ├── setup_fireflyIII.sh
│   ├── setup_homarr.sh
│   ├── setup_immich.sh
│   ├── setup_navidrome.sh
│   ├── setup_nextcloud.sh
│   ├── setup_onlyoffice.sh
│   └── setup_vaultarden.sh
└── Update
    ├── update_all_containers.sh
    ├── update_navidrome.sh
    └── update_nextcloud.sh
```

## **Set Up**
- The methods are described for the Setup/ scripts but will work just as well for the update scripts.
- All scripts are meant to be executed in a dedicated LXC / VM except update_all_containers.sh which should live in your node shell.
- Execute all commands after replacing "/<directory>/<file.sh>" with the path to the file you wish to use.
- All scripts are ready out of the box except update_all_containers which has to be manually configured. Use method 2.
### **Method 1: One-Liner Installation**
Simply run this command inside your LXC / VM console
``` bash
bash <(curl -s https://raw.githubusercontent.com/TrKimico/ProxmoxAdminScripts/main/<directory>/<file.sh>)
```

### **Method 2: Download and Launch**
Download the script inside your LXC / VM console
``` bash
curl -O https://raw.githubusercontent.com/TrKimico/ProxmoxAdminScripts/main/<directory>/<file.sh>
```
Make it executable :
``` bash
chmod +x <file.sh>
```
Run it :
``` bash
bash <file.sh>
```

Side Note: AI was only used in this project for debugging purposes, 99% of the code is handwritten.
