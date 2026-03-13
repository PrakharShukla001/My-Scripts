#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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
echo -e "${CYAN}${BOLD}"
echo "  ██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗    ███████╗██╗██╗  ██╗"
echo "  ██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝    ██╔════╝██║╚██╗██╔╝"
echo "  ██║   ██║███████║██║   ██║██║     ██║       █████╗  ██║ ╚███╔╝ "
echo "  ╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║       ██╔══╝  ██║ ██╔██╗ "
echo "   ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║       ██║     ██║██╔╝ ██╗"
echo "    ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝       ╚═╝     ╚═╝╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "  ${YELLOW}CentOS 7 — Vault Repo Fix${NC}"
echo -e "  ─────────────────────────────────────────────\n"
sleep 0.5

echo -e "  ${YELLOW}▶${NC} ${BOLD}Patching CentOS-Base.repo...${NC}\n"

# os
(sudo sed -i 's|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os|g' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|#baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/|baseurl=http://vault.centos.org/7.9.2009/os/$basearch/|g' /etc/yum.repos.d/CentOS-Base.repo) &
spinner "[base] os → vault.centos.org"

# updates
(sudo sed -i 's|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates|g' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|#baseurl=http://mirror.centos.org/centos/$releasever/updates/$basearch/|baseurl=http://vault.centos.org/7.9.2009/updates/$basearch/|g' /etc/yum.repos.d/CentOS-Base.repo) &
spinner "[updates] → vault.centos.org"

# extras
(sudo sed -i 's|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras|g' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|#baseurl=http://mirror.centos.org/centos/$releasever/extras/$basearch/|baseurl=http://vault.centos.org/7.9.2009/extras/$basearch/|g' /etc/yum.repos.d/CentOS-Base.repo) &
spinner "[extras] → vault.centos.org"

# centosplus
(sudo sed -i 's|mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus|g' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|#baseurl=http://mirror.centos.org/centos/$releasever/centosplus/$basearch/|baseurl=http://vault.centos.org/7.9.2009/centosplus/$basearch/|g' /etc/yum.repos.d/CentOS-Base.repo) &
spinner "[centosplus] → vault.centos.org"

echo -e "\n  ${YELLOW}▶${NC} ${BOLD}Cleaning yum cache...${NC}"
(sudo yum clean all &>/dev/null) &
spinner "Running yum clean all..."

echo -e "\n  ${YELLOW}▶${NC} ${BOLD}Rebuilding yum cache...${NC}"
(sudo yum makecache &>/dev/null) &
spinner "Running yum makecache..."

echo -e "\n  ─────────────────────────────────────────────"
echo -e "  ${GREEN}${BOLD}🎉 Vault fix applied successfully!${NC}"
echo -e "  ─────────────────────────────────────────────\n"

