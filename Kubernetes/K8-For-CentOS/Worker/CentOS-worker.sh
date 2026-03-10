#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${RESET}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
log_error() { echo -e "${RED}[ERR]${RESET}   $1"; }
log_step()  { echo -e "\n${BOLD}==> $1${RESET}"; }

K8S_VERSION="1.32"

# ⚠️  IP WARNING
# EC2 restart pe PUBLIC IP change hoti hai — Private IP same rehti hai.
# Lekin NAYA instance launch karne pe Private IP bhi change ho sakti hai.
# Agar master ka IP change ho gaya → upar prompt mein naya IP daal do.
# PERMANENT FIX: AWS Console → EC2 → Elastic IPs → Allocate → Associate → Master instance

# Master IP — script start pe auto-poochega
SAVED_MASTER_IP="172.31.52.49"
echo ""
echo -e "\033[1;33m┌─────────────────────────────────────────────────┐\033[0m"
echo -e "\033[1;33m│  Master Node ka Private IP enter karo:          │\033[0m"
echo -e "\033[1;33m│  (Master pe 'hostname -I' run karke check karo) │\033[0m"
echo -e "\033[0;36m│  Last saved IP: ${SAVED_MASTER_IP}                  │\033[0m"
echo -e "\033[1;33m└─────────────────────────────────────────────────┘\033[0m"
read -rp "Master Private IP [Enter = ${SAVED_MASTER_IP}]: " INPUT_IP
MASTER_IP="${INPUT_IP:-$SAVED_MASTER_IP}"
echo -e "\033[0;32m[ OK ]\033[0m  Master IP set: ${MASTER_IP}"
echo ""

banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════════╗"
  echo "║   ☸️   Kubernetes — WORKER NODE (CentOS 7)   ║"
  echo "║        Master IP : ${MASTER_IP}              ║"
  echo "║        kubeadm v${K8S_VERSION}                        ║"
  echo "╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo -e "${RED}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${RED}${BOLD}║  ⚠️  IP CHANGE WARNING                        ║${RESET}"
  echo -e "${RED}║  EC2 restart   → Public IP badlegi           ║${RESET}"
  echo -e "${RED}║  Naya instance → Private IP bhi badlegi      ║${RESET}"
  echo -e "${RED}║  Agar IP badla → upar prompt mein naya IP do ║${RESET}"
  echo -e "${RED}║  FIX: Elastic IP assign karo AWS Console pe  ║${RESET}"
  echo -e "${RED}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Master IP (set):     ${GREEN}${MASTER_IP}${RESET}"
  echo -e "  ${BOLD}Worker IP (current): ${GREEN}$(hostname -I | awk '{print $1}')${RESET}"
  echo ""
}

# ─── INSTALL WORKER ───────────────────────────────────────────────────────────
install_worker() {
  log_step "Preflight"
  log_info "Hostname:   $(hostname)"
  log_info "Worker IP:  $(hostname -I | awk '{print $1}')"
  log_info "OS:         $(cat /etc/redhat-release)"
  log_info "RAM:        $(free -h | awk '/^Mem/{print $2}')"
  log_info "CPUs:       $(nproc)"

  # ── Step 1: Disable Swap ──────────────────────────────────────────────────
  log_step "Step 1 — Disable Swap"
  sudo swapoff -a
  sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  log_ok "Swap disabled."

  # ── Step 2: Disable SELinux ───────────────────────────────────────────────
  log_step "Step 2 — Disable SELinux"
  sudo setenforce 0 2>/dev/null || true
  sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
  log_ok "SELinux set to permissive."

  # ── Step 3: Disable Firewall ──────────────────────────────────────────────
  log_step "Step 3 — Disable Firewalld"
  sudo systemctl stop firewalld 2>/dev/null || true
  sudo systemctl disable firewalld 2>/dev/null || true
  log_ok "Firewalld disabled."

  # ── Step 4: Kernel Modules ────────────────────────────────────────────────
  log_step "Step 4 — Kernel Modules"
  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter
  log_ok "Modules loaded."

  # ── Step 5: Sysctl ───────────────────────────────────────────────────────
  log_step "Step 5 — Sysctl"
  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system > /dev/null
  log_ok "Sysctl applied."

  # ── Step 6: Install dependencies ─────────────────────────────────────────
  log_step "Step 6 — Install Dependencies"
  sudo yum install -y yum-utils device-mapper-persistent-data lvm2 curl wget
  log_ok "Dependencies installed."

  # ── Step 7: Install containerd ───────────────────────────────────────────
  log_step "Step 7 — Install containerd"
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum install -y containerd.io

  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd

  log_info "containerd socket ready hone ka wait..."
  for i in {1..15}; do
    [[ -S /var/run/containerd/containerd.sock ]] && break
    sleep 1; echo -n "."
  done; echo ""
  log_ok "containerd running with SystemdCgroup=true."

  # ── Step 8: kubeadm kubelet kubectl ──────────────────────────────────────
  log_step "Step 8 — Install kubeadm, kubelet, kubectl (v${K8S_VERSION})"
  cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

  sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
  sudo systemctl enable kubelet
  log_ok "kubeadm, kubelet, kubectl installed."

  # ── Step 9: Fix Hostname ─────────────────────────────────────────────────
  log_step "Step 9 — Fix Hostname"
  CURRENT_HOSTNAME=$(hostname)
  if ! grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
    echo "127.0.0.1   $CURRENT_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
  fi
  log_ok "Hostname OK: $CURRENT_HOSTNAME"

  # ── Step 10: Join Cluster ────────────────────────────────────────────────
  log_step "Step 10 — Join Cluster"
  echo ""
  echo -e "${YELLOW}${BOLD}┌─ Master pe yeh command run karo ─────────────┐${RESET}"
  echo -e "${CYAN}│  kubeadm token create --print-join-command    │${RESET}"
  echo -e "${YELLOW}${BOLD}└───────────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "${BOLD}Wahan se milne wali command yahan paste karo:${RESET}"
  echo -e "${CYAN}(kubeadm join ${MASTER_IP}:6443 --token ... --discovery-token-ca-cert-hash ...)${RESET}"
  echo ""
  read -rp "> " join_cmd

  if [[ -z "$join_cmd" ]]; then
    log_warn "Command nahi diya. Baad mein manually join karo:"
    log_info "sudo kubeadm join ${MASTER_IP}:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
    return
  fi

  # Auto RAM + CPU check
  RAM_MB=$(free -m | awk '/^Mem/{print $2}')
  CPU_COUNT=$(nproc)
  IGNORE_ERRORS=""

  if [[ "$RAM_MB" -lt 1700 ]]; then
    log_warn "RAM ${RAM_MB}MB < 1700MB — ignoring Mem check"
    IGNORE_ERRORS="Mem"
  fi
  if [[ "$CPU_COUNT" -lt 2 ]]; then
    log_warn "CPU ${CPU_COUNT} < 2 — ignoring NumCPU check"
    IGNORE_ERRORS="${IGNORE_ERRORS:+${IGNORE_ERRORS},}NumCPU"
  fi

  IGNORE_FLAG=""
  [[ -n "$IGNORE_ERRORS" ]] && IGNORE_FLAG="--ignore-preflight-errors=${IGNORE_ERRORS}"
  [[ -n "$IGNORE_FLAG" ]] && log_info "Ignoring preflight: ${IGNORE_ERRORS}"

  log_info "Cluster join ho raha hai..."
  eval "sudo $join_cmd $IGNORE_FLAG --node-name=$(hostname)-worker"

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}║     ✅  Worker Cluster se Join Ho Gaya!       ║${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  log_info "Master pe verify karo: kubectl get nodes"
  echo ""
  show_status
}

# ─── REMOVE WORKER ────────────────────────────────────────────────────────────
remove_worker() {
  log_step "Worker Node Remove (CentOS 7)"
  echo -e "${RED}Yeh worker node se Kubernetes completely remove kar dega.${RESET}"
  read -rp "Type 'yes' to confirm: " confirm
  [[ "$confirm" != "yes" ]] && { echo "Cancelled."; exit 0; }

  sudo kubeadm reset -f 2>/dev/null || true
  sudo systemctl stop kubelet containerd 2>/dev/null || true
  sudo yum remove -y kubeadm kubectl kubelet containerd.io 2>/dev/null || true
  sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/containerd
  sudo rm -rf /etc/cni /opt/cni /var/lib/cni
  sudo rm -f /etc/yum.repos.d/kubernetes.repo
  sudo rm -f /etc/modules-load.d/k8s.conf /etc/sysctl.d/k8s.conf
  sudo iptables -F && sudo iptables -X 2>/dev/null || true

  log_ok "Worker removed."
  log_warn "Master pe bhi run karo: kubectl delete node $(hostname)-worker"
  log_warn "Reboot recommended: sudo reboot"
}

# ─── START SERVICES ───────────────────────────────────────────────────────────
start_services() {
  log_step "Starting Services"
  sudo systemctl start containerd
  for i in {1..15}; do
    [[ -S /var/run/containerd/containerd.sock ]] && break
    sleep 1; echo -n "."
  done; echo ""
  log_ok "containerd started."

  if [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
    log_warn "Worker cluster se joined nahi hai. Run option 1 first."
    echo -e "  containerd   ${GREEN}● running${RESET}"
    echo -e "  kubelet      ${YELLOW}⚠ join pending${RESET}"
    return
  fi

  sudo systemctl start kubelet
  log_info "kubelet stabilize hone ka wait..."
  for i in {1..20}; do
    systemctl is-active --quiet kubelet && break
    sleep 1; echo -n "."
  done; echo ""

  systemctl is-active --quiet kubelet \
    && log_ok "kubelet running." \
    || { log_error "kubelet failed. Logs:"; sudo journalctl -u kubelet --no-pager -n 15; }

  show_status
}

# ─── STOP SERVICES ────────────────────────────────────────────────────────────
stop_services() {
  log_step "Stopping Services"
  sudo systemctl stop kubelet    2>/dev/null && log_ok "kubelet stopped."    || log_warn "kubelet not running."
  sudo systemctl stop containerd 2>/dev/null && log_ok "containerd stopped." || log_warn "containerd not running."
}

# ─── RESTART SERVICES ─────────────────────────────────────────────────────────
restart_services() {
  log_step "Restarting Services"
  sudo systemctl restart containerd && log_ok "containerd restarted."
  if [[ -f /etc/kubernetes/kubelet.conf ]]; then
    sudo systemctl restart kubelet && log_ok "kubelet restarted."
  else
    log_warn "kubelet skip — cluster join pending."
  fi
  sleep 3
  show_status
}

# ─── SHOW STATUS ──────────────────────────────────────────────────────────────
show_status() {
  log_step "Worker Node — Status"

  echo -e "\n${BOLD}── Services ─────────────────────────────────${RESET}"
  systemctl is-active --quiet containerd \
    && echo -e "  containerd   ${GREEN}● running${RESET}" \
    || echo -e "  containerd   ${RED}✗ stopped${RESET}"

  if systemctl is-active --quiet kubelet; then
    echo -e "  kubelet      ${GREEN}● running${RESET}"
  elif [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
    echo -e "  kubelet      ${YELLOW}⚠ cluster se join nahi hua yet${RESET}"
  else
    echo -e "  kubelet      ${RED}✗ stopped${RESET}"
    log_warn "Last kubelet logs:"
    sudo journalctl -u kubelet --no-pager -n 10
  fi

  echo -e "\n${BOLD}── Cluster Join State ───────────────────────${RESET}"
  if [[ -f /etc/kubernetes/kubelet.conf ]]; then
    echo -e "  Joined   ${GREEN}✔ Yes${RESET}"
    APISERVER=$(grep 'server:' /etc/kubernetes/kubelet.conf 2>/dev/null | head -1 | awk '{print $2}')
    log_info "Master API: ${APISERVER}"
  else
    echo -e "  Joined   ${YELLOW}✗ No — Run option 1 to join${RESET}"
  fi

  echo -e "\n${BOLD}── Running Containers ───────────────────────${RESET}"
  sudo crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps 2>/dev/null \
    || log_warn "No containers running or crictl unavailable."

  echo -e "\n${BOLD}── System Resources ─────────────────────────${RESET}"
  echo -e "  Memory : $(free -h | awk '/^Mem/{printf "%s used / %s total", $3, $2}')"
  echo -e "  Disk   : $(df -h / | awk 'NR==2{printf "%s used / %s total (%s)", $3, $2, $5}')"
  echo -e "  CPUs   : $(nproc)"
}

# ─── MENU ─────────────────────────────────────────────────────────────────────
banner
echo "  1) Install & Join Worker Node"
echo "  2) Remove Worker Node"
echo "  3) Start Services"
echo "  4) Stop Services"
echo "  5) Restart Services"
echo "  6) Show Status"
echo "  0) Exit"
echo ""
read -rp "$(echo -e "${YELLOW}Choice:${RESET} ")" choice

case "$choice" in
  1) install_worker ;;
  2) remove_worker ;;
  3) start_services ;;
  4) stop_services ;;
  5) restart_services ;;
  6) show_status ;;
  0) exit 0 ;;
  *) log_error "Invalid choice." ;;
esac

