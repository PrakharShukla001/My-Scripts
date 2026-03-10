#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${RESET}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
log_step()  { echo -e "\n${BOLD}==> $1${RESET}"; }

# ─── INSTALL ──────────────────────────────────────────────────────────────────
install_docker() {
  log_step "Installing Docker on Ubuntu"

  log_info "Removing old versions..."
  sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

  log_info "Updating packages & installing dependencies..."
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  log_info "Adding Docker GPG key..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  log_info "Adding Docker repository..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  log_info "Installing Docker Engine + Compose..."
  sudo apt-get update -y
  sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  log_info "Enabling Docker service..."
  sudo systemctl enable docker
  sudo systemctl start docker

  log_info "Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"

  log_ok "Docker installed successfully!"
  docker --version
  docker compose version
  echo ""
  log_warn "Run: newgrp docker  (or re-login) to use Docker without sudo."
}

# ─── REMOVE ───────────────────────────────────────────────────────────────────
remove_docker() {
  log_step "Removing Docker from Ubuntu"
  echo -e "${RED}This will remove Docker and ALL its data (images, containers, volumes).${RESET}"
  read -rp "Type 'yes' to confirm: " confirm
  [[ "$confirm" != "yes" ]] && { echo "Cancelled."; exit 0; }

  log_info "Stopping Docker service..."
  sudo systemctl stop docker 2>/dev/null || true

  log_info "Purging Docker packages..."
  sudo apt-get purge -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-ce-rootless-extras 2>/dev/null || true

  log_info "Removing Docker data..."
  sudo rm -rf /var/lib/docker
  sudo rm -rf /var/lib/containerd

  log_info "Removing Docker repo & GPG key..."
  sudo rm -f /etc/apt/sources.list.d/docker.list
  sudo rm -f /etc/apt/keyrings/docker.gpg

  sudo apt-get autoremove -y
  sudo apt-get autoclean -y

  log_ok "Docker fully removed."
}

# ─── MENU ─────────────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║   🐳  Docker Setup — Ubuntu          ║"
echo "╚══════════════════════════════════════╝"
echo -e "${RESET}"
echo "  1) Install Docker"
echo "  2) Remove Docker"
echo "  0) Exit"
echo ""
read -rp "$(echo -e "${YELLOW}Choice:${RESET} ")" choice

case "$choice" in
  1) install_docker ;;
  2) remove_docker ;;
  0) exit 0 ;;
  *) echo "Invalid choice." ;;
esac
