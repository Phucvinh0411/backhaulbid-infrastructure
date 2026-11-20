#!/usr/bin/env bash
# ==============================================================================
# BackHaulBid - Build 10 Docker images & import vao K3s (hoac --push len Registry)
#
# Cach dung:
#   # Build tat ca & import thang vao K3s containerd tren EC2 (khong can registry):
#   ./k3s/scripts/build-and-import.sh
#
#   # Chi build lai 1 hoac vai service cu the (nhanh hon khi sua code):
#   ./k3s/scripts/build-and-import.sh web-portal api-gateway
#
#   # Build & push len Docker Hub / GHCR / AWS ECR (can docker login truoc):
#   ./k3s/scripts/build-and-import.sh --push
#   ./k3s/scripts/build-and-import.sh --push identity-service bidding-service
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$(cd "$K3S_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$INFRA_DIR/.." && pwd)"
ENV_FILE="$K3S_DIR/.env.k3s"

PUSH_MODE=false
TARGETS=()

for arg in "$@"; do
  case "$arg" in
    --push)
      PUSH_MODE=true
      ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      TARGETS+=("$arg")
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Khong tim thay $ENV_FILE" >&2
  echo "Hay chay: cp k3s/.env.k3s.example k3s/.env.k3s && nano k3s/.env.k3s" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

IMAGE_REGISTRY="${IMAGE_REGISTRY:-backhaulbid}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-}"
NEXT_PUBLIC_BIDDING_SOCKET_PATH="${NEXT_PUBLIC_BIDDING_SOCKET_PATH:-/bidding-socket}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"

if [[ -z "$PUBLIC_BASE_URL" || "$PUBLIC_BASE_URL" == *"<EC2_PUBLIC_IP>"* ]]; then
  echo "ERROR: Hay dien PUBLIC_BASE_URL that trong $ENV_FILE truoc khi build web-portal." >&2
  exit 1
fi

# Bo dau / cuoi neu co
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"

ALL_SERVICES=(
  eureka-server
  api-gateway
  identity-service
  fleet-service
  wallet-service
  contract-service
  media-service
  bidding-service
  notification-service
  web-portal
)

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=("${ALL_SERVICES[@]}")
fi

CORE_DIR="$WORKSPACE_DIR/backhaulbid-core-services"
NODE_DIR="$WORKSPACE_DIR/backhaulbid-node-services"
WEB_DIR="$WORKSPACE_DIR/backhaulbid-web-portal"

require_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: Khong tim thay thu muc repo: $dir" >&2
    echo "Dam bao 4 repo nam ngang hang trong $WORKSPACE_DIR" >&2
    exit 1
  fi
}

deliver_image() {
  local image="$1"
  if [[ "$PUSH_MODE" == "true" ]]; then
    echo "    -> Pushing $image ..."
    docker push "$image"
  else
    echo "    -> Importing $image vao K3s containerd ..."
    docker save "$image" | sudo k3s ctr images import -
  fi
}

build_service() {
  local svc="$1"
  local image="${IMAGE_REGISTRY}/${svc}:${IMAGE_TAG}"
  echo ""
  echo "=============================================================================="
  echo "==> Building ${svc} (${image})"
  echo "=============================================================================="

  case "$svc" in
    eureka-server)
      docker build -t "$image" "$INFRA_DIR/eureka-server"
      ;;
    api-gateway)
      docker build -t "$image" "$INFRA_DIR/api-gateway"
      ;;
    identity-service|fleet-service|wallet-service|contract-service|media-service)
      require_dir "$CORE_DIR"
      docker build \
        --build-arg "MODULE=${svc}" \
        -t "$image" \
        "$CORE_DIR"
      ;;
    bidding-service)
      require_dir "$NODE_DIR"
      docker build \
        --build-arg APP=bidding \
        --build-arg PORT=3001 \
        -t "$image" \
        "$NODE_DIR"
      ;;
    notification-service)
      require_dir "$NODE_DIR"
      docker build \
        --build-arg APP=notification \
        --build-arg PORT=3002 \
        -t "$image" \
        "$NODE_DIR"
      ;;
    web-portal)
      require_dir "$WEB_DIR"
      docker build \
        --build-arg "NEXT_PUBLIC_GATEWAY_URL=${PUBLIC_BASE_URL}" \
        --build-arg "NEXT_PUBLIC_BIDDING_SOCKET_PATH=${NEXT_PUBLIC_BIDDING_SOCKET_PATH}" \
        --build-arg "NEXT_PUBLIC_GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}" \
        -t "$image" \
        "$WEB_DIR"
      ;;
    *)
      echo "ERROR: Service khong hop le: $svc" >&2
      echo "Danh sach hop le: ${ALL_SERVICES[*]}" >&2
      exit 1
      ;;
  esac

  deliver_image "$image"
}

for svc in "${TARGETS[@]}"; do
  build_service "$svc"
done

echo ""
echo "==> HOAN TAT! Da build & nap ${#TARGETS[@]} image (${IMAGE_REGISTRY}/*:${IMAGE_TAG})."
if [[ "$PUSH_MODE" == "false" ]]; then
  echo "    Kiem tra image trong K3s: sudo k3s ctr images ls | grep '${IMAGE_REGISTRY}/'"
fi
