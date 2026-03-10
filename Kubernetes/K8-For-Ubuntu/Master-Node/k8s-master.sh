#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${RESET}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
log_error() { echo -e "${RED}[ERR]${RESET}   $1"; }
log_step()  { echo -e "\n${BOLD}==> $1${RESET}"; }

K8S_VERSION="1.32"
POD_CIDR="192.168.0.0/16"
MASTER_IP=$(hostname -I | awk '{print $1}')

# ⚠️  IMPORTANT — IP WARNING
# EC2 instance restart hone pe PUBLIC IP change hoti hai.
# Private IP (MASTER_IP) same rehti hai — lekin NAYA instance launch karne pe
# Private IP bhi change ho sakti hai.
#
# PERMANENT FIX — Elastic IP use karo:
#   AWS Console → EC2 → Elastic IPs → Allocate → Associate → This instance
#
# Agar IP change ho gayi hai toh:
#   1. Master pe: sudo kubeadm reset -f && rm -rf $HOME/.kube
#   2. Worker pe: sudo kubeadm reset -f
#   3. Dono scripts dobara run karo

banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════════╗"
  echo "║   ☸️   Kubernetes — MASTER NODE               ║"
  echo "║        kubeadm v${K8S_VERSION} — Ubuntu                ║"
  echo "╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo -e "${RED}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${RED}${BOLD}║  ⚠️  IP CHANGE WARNING                        ║${RESET}"
  echo -e "${RED}║  EC2 restart   → Public IP badlegi           ║${RESET}"
  echo -e "${RED}║  Naya instance → Private IP bhi badlegi      ║${RESET}"
  echo -e "${RED}║  FIX: Elastic IP assign karo AWS Console pe  ║${RESET}"
  echo -e "${RED}║  AWS → EC2 → Elastic IPs → Allocate+Associate║${RESET}"
  echo -e "${RED}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Current Master IP: ${GREEN}${MASTER_IP}${RESET}"
  echo ""
}

# ─── INSTALL MASTER ───────────────────────────────────────────────────────────
install_master() {
  log_step "Preflight"
  log_info "Hostname:   $(hostname)"
  log_info "Master IP:  ${MASTER_IP}"
  log_info "Ubuntu:     $(lsb_release -ds)"
  log_info "RAM:        $(free -h | awk '/^Mem/{print $2}')"
  log_info "CPUs:       $(nproc)"

  # ── Step 1: Disable Swap ──────────────────────────────────────────────────
  log_step "Step 1 — Disable Swap"
  sudo swapoff -a
  sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  log_ok "Swap disabled."

  # ── Step 2: Kernel Modules ────────────────────────────────────────────────
  log_step "Step 2 — Kernel Modules"
  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter
  log_ok "Modules loaded."

  # ── Step 3: Sysctl ───────────────────────────────────────────────────────
  log_step "Step 3 — Sysctl"
  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system > /dev/null
  log_ok "Sysctl applied."

  # ── Step 4: containerd ───────────────────────────────────────────────────
  log_step "Step 4 — Install containerd"
  sudo apt-get update -y -q
  sudo apt-get install -y -q ca-certificates curl gnupg lsb-release apt-transport-https

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -y -q
  sudo apt-get install -y -q containerd.io

  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd
  log_ok "containerd running with SystemdCgroup=true."

  # ── Step 5: kubeadm kubelet kubectl ──────────────────────────────────────
  log_step "Step 5 — Install kubeadm, kubelet, kubectl (v${K8S_VERSION})"
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  sudo chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

  sudo apt-get update -y -q
  sudo apt-get install -y kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl
  sudo systemctl enable kubelet
  log_ok "kubeadm, kubelet, kubectl installed and held."

  # ── Step 6: Fix Hostname ─────────────────────────────────────────────────
  log_step "Step 6 — Fix Hostname"
  CURRENT_HOSTNAME=$(hostname)
  if ! grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
    echo "127.0.0.1   $CURRENT_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
  fi
  log_ok "Hostname OK: $CURRENT_HOSTNAME"

  # ── Step 7: kubeadm init ─────────────────────────────────────────────────
  log_step "Step 7 — kubeadm init (Control Plane)"
  log_info "Master IP : ${MASTER_IP}"
  log_info "Pod CIDR  : ${POD_CIDR}"

  RAM_MB=$(free -m | awk '/^Mem/{print $2}')
  CPU_COUNT=$(nproc)
  IGNORE_ERRORS="Hostname"

  if [[ "$RAM_MB" -lt 1700 ]]; then
    log_warn "RAM ${RAM_MB}MB < 1700MB — ignoring Mem check (t2.micro)"
    IGNORE_ERRORS="${IGNORE_ERRORS},Mem"
  fi

  if [[ "$CPU_COUNT" -lt 2 ]]; then
    log_warn "CPU ${CPU_COUNT} < 2 — ignoring NumCPU check (t2.micro)"
    IGNORE_ERRORS="${IGNORE_ERRORS},NumCPU"
  fi

  log_info "Ignoring preflight errors: ${IGNORE_ERRORS}"

  sudo kubeadm init \
    --apiserver-advertise-address="${MASTER_IP}" \
    --pod-network-cidr="${POD_CIDR}" \
    --node-name="$(hostname)-master" \
    --ignore-preflight-errors="${IGNORE_ERRORS}" \
    | tee /tmp/kubeadm-init.log

  # ── Step 8: kubectl config ───────────────────────────────────────────────
  log_step "Step 8 — Configure kubectl"
  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  log_ok "kubectl configured."

  # ── Step 9: Calico CNI ───────────────────────────────────────────────────
  log_step "Step 9 — Install Calico CNI"
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
  log_ok "Calico CNI applied."

  # ── Save join command ────────────────────────────────────────────────────
  kubeadm token create --print-join-command > /tmp/worker-join-command.sh 2>/dev/null || true

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}║        ✅  Master Node Ready!                 ║${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}┌─ Worker Join Command (worker pe run karo) ───┐${RESET}"
  echo ""
  cat /tmp/worker-join-command.sh
  echo ""
  echo -e "${YELLOW}${BOLD}└──────────────────────────────────────────────┘${RESET}"
  echo ""
  log_warn "Upar wali command copy karke worker pe run karo!"
  log_info "File bhi save hai: /tmp/worker-join-command.sh"

  log_info "20s wait kar raha hoon pods ke liye..."
  sleep 20
  show_status
}

# ─── REMOVE MASTER ────────────────────────────────────────────────────────────
remove_master() {
  log_step "Master Node Remove"
  echo -e "${RED}Yeh master node aur poora cluster wipe kar dega!${RESET}"
  read -rp "Type 'yes' to confirm: " confirm
  [[ "$confirm" != "yes" ]] && { echo "Cancelled."; exit 0; }

  sudo kubeadm reset -f 2>/dev/null || true
  sudo systemctl stop kubelet containerd 2>/dev/null || true
  sudo apt-get purge -y kubeadm kubectl kubelet kubernetes-cni containerd.io 2>/dev/null || true
  sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /var/lib/containerd "$HOME/.kube"
  sudo rm -rf /etc/cni /opt/cni /var/lib/cni
  sudo rm -f /etc/apt/sources.list.d/kubernetes.list /etc/apt/sources.list.d/docker.list
  sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg /etc/apt/keyrings/docker.gpg
  sudo rm -f /etc/modules-load.d/k8s.conf /etc/sysctl.d/k8s.conf
  sudo iptables -F && sudo iptables -X && sudo iptables -t nat -F && sudo iptables -t nat -X 2>/dev/null || true
  sudo apt-get autoremove -y && sudo apt-get autoclean -y
  log_ok "Master removed. Reboot: sudo reboot"
}

# ─── START SERVICES ───────────────────────────────────────────────────────────
start_services() {
  log_step "Starting Services"
  sudo systemctl start containerd && log_ok "containerd started." || log_error "containerd failed."

  if [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
    log_warn "Cluster not initialized. Run option 1 first."
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

  sleep 5
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
    log_warn "kubelet skip — cluster not initialized."
  fi
  sleep 3
  show_status
}

# ─── SHOW STATUS ──────────────────────────────────────────────────────────────
show_status() {
  log_step "Master Node — Cluster Status"

  echo -e "\n${BOLD}── Services ─────────────────────────────────${RESET}"
  systemctl is-active --quiet containerd \
    && echo -e "  containerd   ${GREEN}● running${RESET}" \
    || echo -e "  containerd   ${RED}✗ stopped${RESET}"

  if systemctl is-active --quiet kubelet; then
    echo -e "  kubelet      ${GREEN}● running${RESET}"
  elif [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
    echo -e "  kubelet      ${YELLOW}⚠ cluster not initialized yet${RESET}"
  else
    echo -e "  kubelet      ${RED}✗ stopped${RESET}"
    log_warn "Last kubelet logs:"
    sudo journalctl -u kubelet --no-pager -n 10
  fi

  [[ ! -f "$HOME/.kube/config" ]] && {
    echo -e "\n${YELLOW}[WARN]${RESET} ~/.kube/config not found. Run Install first."
    return
  }

  echo -e "\n${BOLD}── Nodes ────────────────────────────────────${RESET}"
  kubectl get nodes -o wide 2>/dev/null || log_warn "API server unreachable."

  echo -e "\n${BOLD}── All Pods ─────────────────────────────────${RESET}"
  kubectl get pods -A 2>/dev/null || true

  echo -e "\n${BOLD}── Cluster Info ─────────────────────────────${RESET}"
  kubectl cluster-info 2>/dev/null || log_warn "Cluster unreachable."

  echo -e "\n${BOLD}── Node Resource Usage ──────────────────────${RESET}"
  kubectl top nodes 2>/dev/null || log_warn "Metrics server not installed."
}

# ─── SHOW JOIN COMMAND ────────────────────────────────────────────────────────
show_join_command() {
  log_step "Worker Join Command (fresh token)"
  echo -e "\n${CYAN}"
  kubeadm token create --print-join-command 2>/dev/null \
    || log_error "kubeadm not initialized."
  echo -e "${RESET}"
}

# ─── MENU ─────────────────────────────────────────────────────────────────────
banner
echo "  1) Install Master Node"
echo "  2) Remove Master Node"
echo "  3) Start Services"
echo "  4) Stop Services"
echo "  5) Restart Services"
echo "  6) Show Cluster Status"
echo "  7) Show Worker Join Command"
echo "  0) Exit"
echo ""
read -rp "$(echo -e "${YELLOW}Choice:${RESET} ")" choice

case "$choice" in
  1) install_master ;;
  2) remove_master ;;
  3) start_services ;;
  4) stop_services ;;
  5) restart_services ;;
  6) show_status ;;
  7) show_join_command ;;
  0) exit 0 ;;
  *) log_error "Invalid choice." ;;
esac

