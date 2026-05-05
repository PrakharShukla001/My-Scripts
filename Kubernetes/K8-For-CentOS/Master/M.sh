#!/bin/bash
# ============================================================
#  Kubernetes Master Node Setup Script — CentOS 7 / VMware
#  Run as: sudo bash k8s-master-setup.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
err()  { echo -e "${RED}[✘] $1${NC}"; exit 1; }
info() { echo -e "${CYAN}[➜] $1${NC}"; }

[ "$EUID" -ne 0 ] && err "Please run as root: sudo bash $0"

# ── Detect Node IP ──────────────────────────────────────────
NODE_IP=$(hostname -I | awk '{print $1}')
POD_CIDR="192.168.0.0/16"   # Calico default — change if needed
K8S_VERSION="1.28.0"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Kubernetes Master Setup — CentOS 7 / VMware      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
info "Node IP     : $NODE_IP"
info "Pod CIDR    : $POD_CIDR"
info "K8s Version : $K8S_VERSION"
echo ""

# ── 1. Disable SELinux ──────────────────────────────────────
info "Step 1: Disabling SELinux..."
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
log "SELinux set to permissive"

# ── 2. Disable Swap ─────────────────────────────────────────
info "Step 2: Disabling Swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab
log "Swap disabled"

# ── 3. Firewall — disable for lab/dev (re-enable in prod) ───
info "Step 3: Stopping firewall..."
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
log "Firewalld disabled"

# ── 4. Kernel Modules ───────────────────────────────────────
info "Step 4: Loading kernel modules..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
log "Kernel modules loaded"

# ── 5. Sysctl Params ────────────────────────────────────────
info "Step 5: Applying sysctl params..."
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null
log "Sysctl params applied"

# ── 6. Install Docker (containerd) ──────────────────────────
info "Step 6: Installing Docker / containerd..."
yum install -y yum-utils device-mapper-persistent-data lvm2 > /dev/null 2>&1
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null 2>&1
yum install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1

# Configure containerd with SystemdCgroup
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd
systemctl enable --now docker
log "Docker + containerd installed and running"

# ── 7. Add Kubernetes Repo ──────────────────────────────────
info "Step 7: Adding Kubernetes repo..."
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
log "Kubernetes repo added"

# ── 8. Install kubeadm, kubelet, kubectl ────────────────────
info "Step 8: Installing kubeadm, kubelet, kubectl..."
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes > /dev/null 2>&1
systemctl enable --now kubelet
log "kubeadm, kubelet, kubectl installed"

# ── 9. Initialize Kubernetes Control Plane ──────────────────
info "Step 9: Initializing Kubernetes control plane..."
kubeadm init \
  --apiserver-advertise-address="$NODE_IP" \
  --pod-network-cidr="$POD_CIDR" \
  --ignore-preflight-errors=NumCPU \
  2>&1 | tee /var/log/kubeadm-init.log

log "Control plane initialized"

# ── 10. Setup kubeconfig for root ───────────────────────────
info "Step 10: Setting up kubeconfig..."
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
log "kubeconfig configured for root"

# Also setup for any sudo user
if [ -n "$SUDO_USER" ]; then
  USER_HOME=$(eval echo "~$SUDO_USER")
  mkdir -p "$USER_HOME/.kube"
  cp -f /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
  chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/.kube"
  log "kubeconfig also set for user: $SUDO_USER"
fi

# ── 11. Install Calico CNI ───────────────────────────────────
info "Step 11: Installing Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml \
  > /dev/null 2>&1
log "Calico CNI applied"

# ── 12. Save join command ────────────────────────────────────
info "Step 12: Saving worker node join command..."
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
echo "$JOIN_CMD" > /root/k8s-worker-join.sh
chmod +x /root/k8s-worker-join.sh
log "Join command saved → /root/k8s-worker-join.sh"

# ── Done ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅  MASTER NODE SETUP COMPLETE!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📋 Cluster Status:${NC}"
kubectl get nodes
echo ""
echo -e "${CYAN}📋 System Pods:${NC}"
kubectl get pods -n kube-system
echo ""
echo -e "${YELLOW}🔗 Worker Join Command (also saved to /root/k8s-worker-join.sh):${NC}"
echo -e "${WHITE}$JOIN_CMD${NC}"
echo ""
warn "Wait 2-3 mins for Calico pods to become Running before joining workers."
echo ""

