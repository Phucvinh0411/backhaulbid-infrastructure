#!/usr/bin/env bash
# ==============================================================================
# BackHaulBid - Bootstrap script cho AWS EC2 Ubuntu 22.04 / 24.04 (x86_64) moi
#
# Script nay thuc hien:
#   1. Cap nhat he thong & cai cac cong cu co ban (curl, git, openssl, jq)
#   2. Tao 4GB swap (giup build Maven/Next.js tren EC2 8GB RAM khong bi OOM)
#   3. Cai Docker Engine (dung de build container image truc tiep neu khong dung CI)
#   4. Cai K3s (single-node Kubernetes kem Traefik Ingress + local-path PVC + metrics-server)
#   5. Cau hinh kubeconfig cho user hien tai (chay kubectl khong can sudo)
#
# Cach chay tren EC2:
#   chmod +x k3s/scripts/ec2-bootstrap.sh
#   ./k3s/scripts/ec2-bootstrap.sh
# ==============================================================================
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: Script nay chi chay tren Linux (AWS EC2 Ubuntu)." >&2
  exit 1
fi

echo "==> [1/5] Cap nhat goi he thong va cai cong cu co ban..."
sudo apt-get update -y
sudo apt-get install -y curl git ca-certificates gnupg lsb-release openssl jq

echo "==> [2/5] Kiem tra & tao Swap 4GB..."
if ! swapon --show | grep -q '/swapfile'; then
  if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
  fi
  sudo swapon /swapfile
  if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  fi
  echo "    Da bat Swap 4GB."
else
  echo "    Swap da ton tai, bo qua."
fi

echo "==> [3/5] Cai dat Docker Engine (neu chua co)..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
  echo "    Da cai Docker. Luu y: dang xuat & SSH lai (hoac chay 'newgrp docker') de dung docker khong can sudo."
else
  echo "    Docker da duoc cai san: $(docker --version)"
fi

echo "==> [4/5] Cai dat K3s..."
if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode 644" sh -
else
  echo "    K3s da duoc cai san: $(k3s --version | head -n1)"
fi

echo "==> [5/5] Cau hinh kubeconfig cho user $USER..."
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

if ! grep -q 'KUBECONFIG=' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export KUBECONFIG="$HOME/.kube/config"' >> "$HOME/.bashrc"
fi
export KUBECONFIG="$HOME/.kube/config"

echo "==> Dang cho K3s node san sang..."
for _ in $(seq 1 30); do
  if kubectl get nodes 2>/dev/null | grep -q ' Ready '; then
    break
  fi
  sleep 2
done

kubectl get nodes
echo ""
echo "=============================================================================="
echo "HOAN TAT BOOTSTRAP EC2 + K3S!"
echo "Buoc tiep theo:"
echo "  1. Chay 'newgrp docker' (hoac dang xuat & SSH lai) de nhan quyen docker."
echo "  2. Dam bao 4 repo nam cung mot thu muc cha:"
echo "       ~/backhaulbid/backhaulbid-infrastructure"
echo "       ~/backhaulbid/backhaulbid-core-services"
echo "       ~/backhaulbid/backhaulbid-node-services"
echo "       ~/backhaulbid/backhaulbid-web-portal"
echo "  3. Copy va dien bien moi truong:"
echo "       cd ~/backhaulbid/backhaulbid-infrastructure"
echo "       cp k3s/.env.k3s.example k3s/.env.k3s && chmod 600 k3s/.env.k3s && nano k3s/.env.k3s"
echo "  4. Build & import image vao K3s:"
echo "       ./k3s/scripts/build-and-import.sh"
echo "  5. Deploy toan bo stack:"
echo "       ./k3s/scripts/deploy.sh"
echo "=============================================================================="
