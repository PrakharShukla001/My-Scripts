#!/bin/bash
set -e

# ─── UBUNTU CHECK ─────────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script is for Ubuntu Linux only."; exit 1
fi

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
  echo "Warning: This does not appear to be Ubuntu. Proceed with caution."
fi

UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")

# ─── COLORS ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${RESET} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
log_error() { echo -e "${RED}[ERR]${RESET}   $1"; }
log_step()  { echo -e "\n${BOLD}==> $1${RESET}"; }

ask() { read -rp "$(echo -e "${YELLOW}$1:${RESET} ")" val; echo "$val"; }
require_arg() { [[ -n "$1" ]] && echo "$1" || ask "$2"; }
confirm() { read -rp "$(echo -e "${RED}$1 Type 'yes' to confirm:${RESET} ")" c; [[ "$c" == "yes" ]]; }

# ─── INSTALL DOCKER ───────────────────────────────────────────────────────────
install_docker() {
  log_step "Installing Docker on Ubuntu ($UBUNTU_CODENAME)"

  log_info "Removing old Docker packages..."
  sudo apt-get remove -y \
    docker docker-engine docker.io containerd runc \
    docker-desktop docker-doc docker-compose \
    podman-docker 2>/dev/null || true

  log_info "Installing apt dependencies..."
  sudo apt-get update -y
  sudo apt-get install -y \
    ca-certificates curl gnupg \
    lsb-release apt-transport-https software-properties-common

  log_info "Adding Docker's official GPG key..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  log_info "Setting up Docker apt repository..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  log_info "Installing Docker Engine, CLI, Compose plugin..."
  sudo apt-get update -y
  sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  log_info "Enabling & starting Docker service..."
  sudo systemctl enable docker
  sudo systemctl start docker

  log_info "Adding '$USER' to docker group (no sudo needed after re-login)..."
  sudo usermod -aG docker "$USER"

  log_ok "Docker installed successfully!"
  docker --version
  docker compose version
  echo ""
  log_warn "Log out & back in (or run: newgrp docker) to use Docker without sudo."
}

# ─── UNINSTALL DOCKER ─────────────────────────────────────────────────────────
uninstall_docker() {
  log_step "Uninstalling Docker from Ubuntu"
  confirm "This will REMOVE Docker and all its data!" || { log_info "Cancelled."; return; }

  sudo apt-get purge -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

  sudo rm -rf /var/lib/docker /var/lib/containerd
  sudo rm -f /etc/apt/sources.list.d/docker.list
  sudo rm -f /etc/apt/keyrings/docker.gpg

  log_ok "Docker fully removed."
}

# ─── UPDATE DOCKER ────────────────────────────────────────────────────────────
update_docker() {
  log_step "Updating Docker Engine"
  sudo apt-get update -y
  sudo apt-get install --only-upgrade -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  log_ok "Docker updated."
  docker --version
  docker compose version
}

# ─── SERVICE CONTROL ──────────────────────────────────────────────────────────
service_status()  { sudo systemctl status docker --no-pager; }
service_start()   { sudo systemctl start docker;   log_ok "Docker service started."; }
service_stop()    { sudo systemctl stop docker;    log_ok "Docker service stopped."; }
service_restart() { sudo systemctl restart docker; log_ok "Docker service restarted."; }
service_enable()  { sudo systemctl enable docker;  log_ok "Docker enabled on boot."; }
service_disable() { sudo systemctl disable docker; log_warn "Docker disabled on boot."; }

# ─── CONTAINERS ───────────────────────────────────────────────────────────────
list_containers()     { log_step "Running Containers";  docker ps; }
list_all_containers() { log_step "All Containers";      docker ps -a; }

start_container()   { docker start   "$(require_arg "$1" "Container name")" && log_ok "Started"; }
stop_container()    { docker stop    "$(require_arg "$1" "Container name")" && log_ok "Stopped"; }
restart_container() { docker restart "$(require_arg "$1" "Container name")" && log_ok "Restarted"; }

remove_container() {
  local name; name=$(require_arg "$1" "Container name")
  docker rm -f "$name" && log_ok "Removed: $name"
}

container_logs()  { docker logs -f "$(require_arg "$1" "Container name")"; }
container_stats() { log_step "Live Stats (Ctrl+C to exit)"; docker stats; }
exec_container()  {
  local name; name=$(require_arg "$1" "Container name")
  docker exec -it "$name" bash 2>/dev/null || docker exec -it "$name" sh
}
inspect_container() { docker inspect "$(require_arg "$1" "Container name")"; }

# ─── IMAGES ───────────────────────────────────────────────────────────────────
list_images()  { log_step "Images"; docker images; }
pull_image()   { docker pull "$(require_arg "$1" "Image (e.g. ubuntu:24.04)")"; }
remove_image() { docker rmi  "$(require_arg "$1" "Image name")"; }
push_image()   { docker push "$(require_arg "$1" "Image to push")"; }

build_image() {
  local tag; tag=$(require_arg "$1" "Tag (e.g. myapp:1.0)")
  local ctx; ctx=$(require_arg "$2" "Build context (default: .)")
  docker build -t "$tag" "${ctx:-.}"
}

tag_image() {
  docker tag \
    "$(require_arg "$1" "Source image")" \
    "$(require_arg "$2" "Target tag")"
  log_ok "Tagged."
}

save_image() {
  local img; img=$(require_arg "$1" "Image name")
  local out; out=$(require_arg "$2" "Output .tar file")
  docker save "$img" > "$out" && log_ok "Saved to $out"
}

load_image() {
  local file; file=$(require_arg "$1" ".tar file path")
  docker load < "$file" && log_ok "Loaded."
}

# ─── VOLUMES ──────────────────────────────────────────────────────────────────
list_volumes()    { log_step "Volumes"; docker volume ls; }
create_volume()   { docker volume create "$(require_arg "$1" "Volume name")" && log_ok "Created"; }
remove_volume()   { docker volume rm     "$(require_arg "$1" "Volume name")" && log_ok "Removed"; }
inspect_volume()  { docker volume inspect "$(require_arg "$1" "Volume name")"; }

# ─── NETWORKS ─────────────────────────────────────────────────────────────────
list_networks()   { log_step "Networks"; docker network ls; }
create_network()  { docker network create  "$(require_arg "$1" "Network name")" && log_ok "Created"; }
remove_network()  { docker network rm      "$(require_arg "$1" "Network name")" && log_ok "Removed"; }
connect_network() {
  docker network connect \
    "$(require_arg "$1" "Network name")" \
    "$(require_arg "$2" "Container name")" && log_ok "Connected"
}

# ─── DOCKER COMPOSE ───────────────────────────────────────────────────────────
compose_up()          { log_step "Compose Up";    docker compose up -d; }
compose_down()        { log_step "Compose Down";  docker compose down; }
compose_down_vols()   { log_warn "Removing containers + volumes..."; docker compose down -v; }
compose_logs()        { docker compose logs -f; }
compose_ps()          { docker compose ps; }
compose_build()       { log_step "Compose Build"; docker compose build; }
compose_pull()        { log_step "Compose Pull";  docker compose pull; }
compose_restart() {
  local svc; svc=$(ask "Service name (blank = all)")
  docker compose restart $svc && log_ok "Restarted"
}
compose_exec() {
  local svc; svc=$(require_arg "$1" "Service name")
  docker compose exec "$svc" bash 2>/dev/null || docker compose exec "$svc" sh
}

# ─── QUICK RUN ────────────────────────────────────────────────────────────────
run_nginx() {
  log_step "NGINX on :8080"
  docker run -d --name nginx-demo --rm -p 8080:80 nginx
  log_ok "http://localhost:8080"
}
run_postgres() {
  log_step "PostgreSQL on :5432"
  docker run -d --name pg-demo --rm \
    -e POSTGRES_PASSWORD=secret -p 5432:5432 postgres:16
  log_ok "PostgreSQL ready  (password: secret)"
}
run_redis() {
  log_step "Redis on :6379"
  docker run -d --name redis-demo --rm -p 6379:6379 redis:alpine
  log_ok "Redis ready"
}
run_mysql() {
  log_step "MySQL on :3306"
  docker run -d --name mysql-demo --rm \
    -e MYSQL_ROOT_PASSWORD=secret -p 3306:3306 mysql:8
  log_ok "MySQL ready  (root password: secret)"
}
run_mongo() {
  log_step "MongoDB on :27017"
  docker run -d --name mongo-demo --rm -p 27017:27017 mongo:7
  log_ok "MongoDB ready"
}
run_ubuntu_container() {
  log_step "Interactive Ubuntu 24.04 container"
  docker run -it --rm ubuntu:24.04 bash
}

# ─── REGISTRY ─────────────────────────────────────────────────────────────────
docker_login()          { docker login; }
docker_login_registry() { docker login "$(require_arg "$1" "Registry URL")"; }
docker_logout()         { docker logout && log_ok "Logged out"; }

# ─── SYSTEM ───────────────────────────────────────────────────────────────────
system_info() {
  log_step "Docker Info"
  docker info
  echo ""
  log_step "Disk Usage"
  docker system df
}
docker_version() {
  docker --version
  docker compose version
}
system_prune() {
  log_warn "Removing stopped containers + dangling images..."
  docker system prune -f && log_ok "Done"
}
system_prune_all() {
  confirm "Remove ALL unused images, containers, networks?" || { log_info "Cancelled"; return; }
  docker system prune -af && log_ok "Done"
}
system_prune_volumes() {
  confirm "Remove ALL unused images + volumes? ⚠️ DESTRUCTIVE. " || { log_info "Cancelled"; return; }
  docker system prune -af --volumes && log_ok "Done"
}

# ─── BANNER & MENU ────────────────────────────────────────────────────────────
banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════════╗"
  echo "║     🐳  Docker Manager — Ubuntu Edition      ║"
  echo "║         Ubuntu: ${UBUNTU_CODENAME}                          ║"
  echo "╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

menu() {
  echo -e "
${BOLD}── INSTALL / MANAGE ─────────────────────${RESET}
   1)  Install Docker
   2)  Update Docker
   3)  Uninstall Docker
   4)  Docker version

${BOLD}── SERVICE (systemctl) ──────────────────${RESET}
   5)  Status
   6)  Start service
   7)  Stop service
   8)  Restart service
   9)  Enable on boot
  10)  Disable on boot

${BOLD}── CONTAINERS ───────────────────────────${RESET}
  11)  List running
  12)  List all
  13)  Start
  14)  Stop
  15)  Restart
  16)  Remove (force)
  17)  Logs (follow)
  18)  Shell into container
  19)  Live stats
  20)  Inspect

${BOLD}── IMAGES ───────────────────────────────${RESET}
  21)  List images
  22)  Pull image
  23)  Build image
  24)  Remove image
  25)  Tag image
  26)  Push image
  27)  Save to .tar
  28)  Load from .tar

${BOLD}── VOLUMES ──────────────────────────────${RESET}
  29)  List
  30)  Create
  31)  Remove
  32)  Inspect

${BOLD}── NETWORKS ─────────────────────────────${RESET}
  33)  List
  34)  Create
  35)  Remove
  36)  Connect container

${BOLD}── DOCKER COMPOSE ───────────────────────${RESET}
  37)  Up (detached)
  38)  Down
  39)  Down + remove volumes
  40)  Logs (follow)
  41)  Status (ps)
  42)  Build
  43)  Pull
  44)  Restart service
  45)  Exec into service

${BOLD}── QUICK RUN ─────────────────────────────${RESET}
  46)  NGINX          :8080
  47)  PostgreSQL 16  :5432
  48)  Redis          :6379
  49)  MySQL 8        :3306
  50)  MongoDB 7      :27017
  51)  Ubuntu 24.04 shell

${BOLD}── REGISTRY ─────────────────────────────${RESET}
  52)  Login (Docker Hub)
  53)  Login (custom registry)
  54)  Logout

${BOLD}── SYSTEM ───────────────────────────────${RESET}
  55)  Info + disk usage
  56)  Prune (dangling only)
  57)  Full prune (all unused)
  58)  Full prune + volumes ⚠️

   0)  Exit
"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner

while true; do
  menu
  read -rp "$(echo -e "${YELLOW}Choice:${RESET} ")" choice
  case "$choice" in
    1)  install_docker ;;
    2)  update_docker ;;
    3)  uninstall_docker ;;
    4)  docker_version ;;
    5)  service_status ;;
    6)  service_start ;;
    7)  service_stop ;;
    8)  service_restart ;;
    9)  service_enable ;;
    10) service_disable ;;
    11) list_containers ;;
    12) list_all_containers ;;
    13) start_container ;;
    14) stop_container ;;
    15) restart_container ;;
    16) remove_container ;;
    17) container_logs ;;
    18) exec_container ;;
    19) container_stats ;;
    20) inspect_container ;;
    21) list_images ;;
    22) pull_image ;;
    23) build_image ;;
    24) remove_image ;;
    25) tag_image ;;
    26) push_image ;;
    27) save_image ;;
    28) load_image ;;
    29) list_volumes ;;
    30) create_volume ;;
    31) remove_volume ;;
    32) inspect_volume ;;
    33) list_networks ;;
    34) create_network ;;
    35) remove_network ;;
    36) connect_network ;;
    37) compose_up ;;
    38) compose_down ;;
    39) compose_down_vols ;;
    40) compose_logs ;;
    41) compose_ps ;;
    42) compose_build ;;
    43) compose_pull ;;
    44) compose_restart ;;
    45) compose_exec ;;
    46) run_nginx ;;
    47) run_postgres ;;
    48) run_redis ;;
    49) run_mysql ;;
    50) run_mongo ;;
    51) run_ubuntu_container ;;
    52) docker_login ;;
    53) docker_login_registry ;;
    54) docker_logout ;;
    55) system_info ;;
    56) system_prune ;;
    57) system_prune_all ;;
    58) system_prune_volumes ;;
    0)  echo -e "\n${CYAN}Goodbye! 🐳${RESET}\n"; exit 0 ;;
    *)  log_warn "Invalid choice, try again." ;;
  esac
done

