#!/bin/bash

# ─────────────────────────────────────────
#   Docker Manager — Animated Edition
#   CentOS 7  |  sudo ./docker.sh
# ─────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ── Spinner ──────────────────────────────
spinner() {
    local pid=$1
    local msg=$2
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC}  ${msg}"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.08
    done
    printf "\r  ${GREEN}✔${NC}  ${msg}\n"
}

# ── Progress Bar ─────────────────────────
progress_bar() {
    local label="$1"
    local duration="$2"
    local width=30
    echo -ne "  ${DIM}${label}${NC}\n  ["
    for ((i=0; i<=width; i++)); do
        sleep "$(echo "$duration / $width" | bc -l)"
        echo -ne "${GREEN}█${NC}"
    done
    echo -e "]  ${GREEN}done${NC}"
}

# ── Typewriter ───────────────────────────
typewrite() {
    local text="$1"
    local delay="${2:-0.03}"
    for ((i=0; i<${#text}; i++)); do
        echo -ne "${text:$i:1}"
        sleep "$delay"
    done
    echo
}

# ── Banner ───────────────────────────────
show_banner() {
    clear
    echo -e "${CYAN}"
    sleep 0.05; echo "  ██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗ "
    sleep 0.05; echo "  ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗"
    sleep 0.05; echo "  ██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝"
    sleep 0.05; echo "  ██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗"
    sleep 0.05; echo "  ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║"
    sleep 0.05; echo "  ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}Manager for CentOS 7${NC}  ${DIM}|  sudo required${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────${NC}\n"
    sleep 0.3
}

# ── Menu ─────────────────────────────────
show_menu() {
    echo -e "  ${BOLD}What do you want to do?${NC}\n"
    echo -e "  ${GREEN}[1]${NC}  🚀  Install Docker"
    echo -e "  ${RED}[2]${NC}  🗑️   Remove Docker"
    echo -e "  ${DIM}[3]${NC}  ❌  Exit\n"
    echo -ne "  ${CYAN}➜${NC} Choose (1/2/3): "
    read -r choice
}

# ── Step Logger ──────────────────────────
step() {
    local num="$1"
    local msg="$2"
    echo -e "\n  ${MAGENTA}[${num}]${NC} ${WHITE}${msg}${NC}"
}

run_cmd() {
    local msg="$1"; shift
    ("$@" > /tmp/docker_out.log 2>&1) &
    spinner $! "$msg"
    if [[ $? -ne 0 ]] && ! wait $!; then
        echo -e "  ${RED}✘  Failed! Check /tmp/docker_out.log${NC}"
        exit 1
    fi
}

# ── Install ──────────────────────────────
install_docker() {
    echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    typewrite "  🐳  Starting Docker Installation..." 0.04
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    sleep 0.5

    step "1/5" "Removing old Docker versions..."
    (yum remove -y docker docker-common docker-engine > /tmp/docker_out.log 2>&1) &
    spinner $! "Cleaning old packages"

    step "2/5" "Installing dependencies..."
    (yum install -y yum-utils device-mapper-persistent-data lvm2 >> /tmp/docker_out.log 2>&1) &
    spinner $! "Installing yum-utils, lvm2"

    step "3/5" "Adding Docker CE repository..."
    (yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >> /tmp/docker_out.log 2>&1) &
    spinner $! "Fetching repo from docker.com"

    step "4/5" "Installing Docker CE..."
    echo ""
    progress_bar "Downloading & installing docker-ce..." 6
    yum install -y docker-ce docker-ce-cli containerd.io >> /tmp/docker_out.log 2>&1

    step "5/5" "Starting Docker service..."
    (systemctl start docker && systemctl enable docker >> /tmp/docker_out.log 2>&1) &
    spinner $! "Enabling docker.service"

    echo -e "\n  ${DIM}────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}${BOLD}✔  Docker installed successfully!${NC}"
    echo -e "  ${DIM}────────────────────────────────────────${NC}"
    echo -e "  Version : ${CYAN}$(docker --version 2>/dev/null)${NC}"
    echo -e "  Service : ${GREEN}$(systemctl is-active docker)${NC}\n"
    typewrite "  💡 Tip: Add user to docker group → sudo usermod -aG docker \$USER" 0.02
    echo ""
}

# ── Remove ───────────────────────────────
remove_docker() {
    echo -e "\n  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    typewrite "  🗑️   Starting Docker Removal..." 0.04
    echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    sleep 0.5

    echo -ne "\n  ${YELLOW}⚠  This will delete all containers & images. Continue? (y/N): ${NC}"
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo -e "  ${DIM}Aborted.${NC}\n" && return

    step "1/4" "Stopping Docker service..."
    (systemctl stop docker > /tmp/docker_out.log 2>&1) &
    spinner $! "Stopping docker.service"

    step "2/4" "Removing Docker packages..."
    (yum remove -y docker-ce docker-ce-cli containerd.io >> /tmp/docker_out.log 2>&1) &
    spinner $! "Uninstalling packages"

    step "3/4" "Deleting Docker data..."
    echo ""
    progress_bar "Wiping /var/lib/docker..." 2
    rm -rf /var/lib/docker /var/lib/containerd

    step "4/4" "Cleaning up repository..."
    (rm -f /etc/yum.repos.d/docker-ce.repo && yum clean all >> /tmp/docker_out.log 2>&1) &
    spinner $! "Removing Docker repo"

    echo -e "\n  ${DIM}────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}${BOLD}✔  Docker removed successfully!${NC}"
    echo -e "  ${DIM}────────────────────────────────────────${NC}\n"
}

# ── Main ─────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Run with sudo: sudo ./docker.sh"
    exit 1
fi

show_banner
show_menu

case "$choice" in
    1) install_docker ;;
    2) remove_docker  ;;
    3) echo -e "\n  ${DIM}Bye! 👋${NC}\n"; exit 0 ;;
    *) echo -e "\n  ${RED}Invalid option.${NC}\n"; exit 1 ;;
esac

