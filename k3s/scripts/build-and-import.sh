#!/usr/bin/env bash
# ==============================================================================
# BackHaulBid - Build 9 Docker images & import vao K3s (hoac --push len Registry)
#
# Cach dung:
#   # Build tat ca & import thang vao K3s containerd tren EC2 (khong can registry):
#   ./k3s/scripts/build-and-import.sh
#
#   # Chi build lai 1 hoac vai service cu the (nhanh hon khi sua code):
#   ./k3s/scripts/build-and-import.sh web-portal api-gateway
#
#   # Build & push len Docker Hub / GHCR / AWS ECR (dung IMAGE_REGISTRY trong .env.k3s):
#   ./k3s/scripts/build-and-import.sh --push
#   ./k3s/scripts/build-and-import.sh --push --tag v1.0.1 identity-service bidding-service
#
# Tuy chon:
#   --push                 Day image len Registry thay vi import vao containerd
#   --tag <tag>            Ghi de IMAGE_TAG (mac dinh 'auto' -> Git short SHA)
#   --platform <arch>      Ghi de IMAGE_PLATFORM (mac dinh linux/amd64)
#   --no-cache             Truyen --no-cache cho docker build
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$(cd "$K3S_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$INFRA_DIR/.." && pwd)"
ENV_FILE="$K3S_DIR/.env.k3s"

# Giu lai bien moi truong truyen tu ben ngoai (uu tien cao hon .env.k3s)
ENV_OVERRIDE_REGISTRY="${IMAGE_REGISTRY-}"
ENV_OVERRIDE_PREFIX="${IMAGE_PREFIX-}"
ENV_OVERRIDE_TAG="${IMAGE_TAG-}"
ENV_OVERRIDE_PLATFORM="${IMAGE_PLATFORM-}"

PUSH_MODE=false
NO_CACHE=false
CLI_TAG=""
CLI_PLATFORM=""
TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH_MODE=true
      shift
      ;;
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    --tag)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --tag can gia tri cu the." >&2
        exit 1
      fi
      CLI_TAG="$2"
      shift 2
      ;;
    --tag=*)
      CLI_TAG="${1#*=}"
      shift
      ;;
    --platform)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --platform can gia tri cu the (vd: linux/amd64)." >&2
        exit 1
      fi
      CLI_PLATFORM="$2"
      shift 2
      ;;
    --platform=*)
      CLI_PLATFORM="${1#*=}"
      shift
      ;;
    -h|--help)
      sed -n '2,23p' "$0"
      exit 0
      ;;
    -*)
      echo "ERROR: Co khong hop le: $1" >&2
      exit 1
      ;;
    *)
      TARGETS+=("$1")
      shift
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

# Ap dung uu tien: CLI flag > env truyen tu shell > gia tri trong .env.k3s > mac dinh
IMAGE_REGISTRY="${ENV_OVERRIDE_REGISTRY:-${IMAGE_REGISTRY:-backhaulbid}}"
IMAGE_PREFIX="${ENV_OVERRIDE_PREFIX:-${IMAGE_PREFIX:-}}"
IMAGE_TAG="${CLI_TAG:-${ENV_OVERRIDE_TAG:-${IMAGE_TAG:-auto}}}"
IMAGE_PLATFORM="${CLI_PLATFORM:-${ENV_OVERRIDE_PLATFORM:-${IMAGE_PLATFORM:-linux/amd64}}}"

DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"
DOCKERHUB_SERVER="${DOCKERHUB_SERVER:-https://index.docker.io/v1/}"

PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-}"
NEXT_PUBLIC_BIDDING_SOCKET_PATH="${NEXT_PUBLIC_BIDDING_SOCKET_PATH:-/bidding-socket}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"

if [[ -z "$IMAGE_TAG" || "$IMAGE_TAG" == "auto" ]]; then
  if git -C "$INFRA_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
    IMAGE_TAG="$(git -C "$INFRA_DIR" rev-parse --short HEAD)"
  else
    IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
  fi
fi

# 9 service chuan tren K3s (eureka-server da loai khoi mac dinh vi dung K8s DNS)
ALL_SERVICES=(
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

if [[ "$PUSH_MODE" == "true" ]]; then
  if [[ "$IMAGE_REGISTRY" == "backhaulbid" ]]; then
    if [[ -n "$DOCKERHUB_USERNAME" ]]; then
      IMAGE_REGISTRY="$DOCKERHUB_USERNAME"
    else
      echo "ERROR: Khi dung --push, hay dat IMAGE_REGISTRY=<dockerhub_username_hoac_org> trong $ENV_FILE (hien dang la 'backhaulbid')." >&2
      exit 1
    fi
  fi

  if [[ -n "$DOCKERHUB_USERNAME" && -n "$DOCKERHUB_TOKEN" ]]; then
    echo "==> Dang nhap Docker Registry ($DOCKERHUB_SERVER) voi user '$DOCKERHUB_USERNAME'..."
    printf '%s' "$DOCKERHUB_TOKEN" | docker login "$DOCKERHUB_SERVER" -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null
  fi
fi

# Chi bat buoc PUBLIC_BASE_URL khi danh sach build co web-portal
for svc in "${TARGETS[@]}"; do
  if [[ "$svc" == "web-portal" ]]; then
    if [[ -z "$PUBLIC_BASE_URL" || "$PUBLIC_BASE_URL" == *"<EC2_PUBLIC_IP>"* ]]; then
      echo "ERROR: Hay dien PUBLIC_BASE_URL that trong $ENV_FILE truoc khi build web-portal." >&2
      exit 1
    fi
    break
  fi
done
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"

CORE_DIR="$WORKSPACE_DIR/backhaulbid-core-services"
NODE_DIR="$WORKSPACE_DIR/backhaulbid-node-services"
WEB_DIR="$WORKSPACE_DIR/backhaulbid-web-portal"

require_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: Khong tim thay thu muc repo: $dir" >&2
    echo "Dam bao cac repo nam ngang hang trong $WORKSPACE_DIR" >&2
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
  local image="${IMAGE_REGISTRY}/${IMAGE_PREFIX}${svc}:${IMAGE_TAG}"
  local build_flags=(--platform "$IMAGE_PLATFORM")
  if [[ "$NO_CACHE" == "true" ]]; then
    build_flags+=(--no-cache)
  fi

  echo ""
  echo "=============================================================================="
  echo "==> Building ${svc} -> ${image} (${IMAGE_PLATFORM})"
  echo "=============================================================================="

  case "$svc" in
    eureka-server)
      docker build "${build_flags[@]}" -t "$image" "$INFRA_DIR/eureka-server"
      ;;
    api-gateway)
      docker build "${build_flags[@]}" -t "$image" "$INFRA_DIR/api-gateway"
      ;;
    identity-service|fleet-service|wallet-service|contract-service|media-service)
      require_dir "$CORE_DIR"
      docker build "${build_flags[@]}" \
        --build-arg "MODULE=${svc}" \
        -t "$image" \
        "$CORE_DIR"
      ;;
    bidding-service)
      require_dir "$NODE_DIR"
      docker build "${build_flags[@]}" \
        --build-arg APP=bidding \
        --build-arg PORT=3001 \
        -t "$image" \
        "$NODE_DIR"
      ;;
    notification-service)
      require_dir "$NODE_DIR"
      docker build "${build_flags[@]}" \
        --build-arg APP=notification \
        --build-arg PORT=3002 \
        -t "$image" \
        "$NODE_DIR"
      ;;
    web-portal)
      require_dir "$WEB_DIR"
      docker build "${build_flags[@]}" \
        --build-arg "NEXT_PUBLIC_GATEWAY_URL=${PUBLIC_BASE_URL}" \
        --build-arg "NEXT_PUBLIC_BIDDING_SOCKET_PATH=${NEXT_PUBLIC_BIDDING_SOCKET_PATH}" \
        --build-arg "NEXT_PUBLIC_GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}" \
        -t "$image" \
        "$WEB_DIR"
      ;;
    *)
      echo "ERROR: Service khong hop le: $svc" >&2
      echo "Danh sach hop le: ${ALL_SERVICES[*]} (hoac eureka-server cho local Docker Compose)" >&2
      exit 1
      ;;
  esac

  deliver_image "$image"
}

for svc in "${TARGETS[@]}"; do
  build_service "$svc"
done

echo ""
echo "==> HOAN TAT! Da xu ly ${#TARGETS[@]} image (${IMAGE_REGISTRY}/${IMAGE_PREFIX}*:${IMAGE_TAG})."
if [[ "$PUSH_MODE" == "true" ]]; then
  echo "    Tren EC2, chay de deploy tag nay:"
  echo "    IMAGE_TAG=${IMAGE_TAG} ./k3s/scripts/deploy.sh"
else
  echo "    Kiem tra image trong K3s: sudo k3s ctr images ls | grep '${IMAGE_REGISTRY}/${IMAGE_PREFIX}'"
fi
