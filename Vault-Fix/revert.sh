#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO="/etc/yum.repos.d/CentOS-Base.repo"

spinner() {
    local pid=$!
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local msg="$1"
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r  ${CYAN}${spin:$i:1}${NC}  $msg"
        i=$(( (i+1) % 10 ))
        sleep 0.1
    done
    printf "\r  ${GREEN}✔${NC}  $msg\n"
}

clear
echo -e "${RED}${BOLD}"
echo "  ██████╗ ███████╗██╗   ██╗███████╗██████╗ ████████╗"
echo "  ██╔══██╗██╔════╝██║   ██║██╔════╝██╔══██╗╚══██╔══╝"
echo "  ██████╔╝█████╗  ██║   ██║█████╗  ██████╔╝   ██║   "
echo "  ██╔══██╗██╔══╝  ╚██╗ ██╔╝██╔══╝  ██╔══██╗   ██║   "
echo "  ██║  ██║███████╗ ╚████╔╝ ███████╗██║  ██║   ██║   "
echo "  ╚═╝  ╚═╝╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝   ╚═╝   "
echo -e "${NC}"
echo -e "  ${YELLOW}CentOS 7 — Vault Fix Revert${NC}"
echo -e "  ${CYAN}Restoring original mirrorlist URLs${NC}"
echo -e "  ─────────────────────────────────────────────\n"
sleep 0.5

echo -e "  ${YELLOW}▶${NC} ${BOLD}Reverting CentOS-Base.repo patches...${NC}\n"

# os
(sudo sed -i 's|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os|g' $REPO
sudo sed -i 's|baseurl=http://vault.centos.org/7.9.2009/os/$basearch/|#baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/|g' $REPO) &
spinner "[base] os → mirrorlist restored"

# updates
(sudo sed -i 's|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates|g' $REPO
sudo sed -i 's|baseurl=http://vault.centos.org/7.9.2009/updates/$basearch/|#baseurl=http://mirror.centos.org/centos/$releasever/updates/$basearch/|g' $REPO) &
spinner "[updates] → mirrorlist restored"

# extras
(sudo sed -i 's|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras|g' $REPO
sudo sed -i 's|baseurl=http://vault.centos.org/7.9.2009/extras/$basearch/|#baseurl=http://mirror.centos.org/centos/$releasever/extras/$basearch/|g' $REPO) &
spinner "[extras] → mirrorlist restored"

# centosplus
(sudo sed -i 's|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus|g' $REPO
sudo sed -i 's|baseurl=http://vault.centos.org/7.9.2009/centosplus/$basearch/|#baseurl=http://mirror.centos.org/centos/$releasever/centosplus/$basearch/|g' $REPO) &
spinner "[centosplus] → mirrorlist restored"

echo -e "\n  ${YELLOW}▶${NC} ${BOLD}Cleaning yum cache...${NC}"
(sudo yum clean all &>/dev/null) &
spinner "Running yum clean all..."

echo -e "\n  ${YELLOW}▶${NC} ${BOLD}Rebuilding yum cache...${NC}"
(sudo yum makecache &>/dev/null) &
spinner "Running yum makecache..."

echo -e "\n  ─────────────────────────────────────────────"
echo -e "  ${GREEN}${BOLD}✔ Mirrorlist restored successfully!${NC}"
echo -e "  ─────────────────────────────────────────────\n"

