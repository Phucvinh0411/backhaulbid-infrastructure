#!/usr/bin/env bash
# ==============================================================================
# BackHaulBid - Deploy len K3s tu file k3s/.env.k3s
#
# Script nay thuc hien:
#   1. Kiem tra tinh hop le cua k3s/.env.k3s (khong con placeholder CHANGE_ME)
#   2. Tao/cap nhat Namespace, Secret (khong ghi secret ra file YAML), ConfigMap
#   3. Tao Kustomize overlay tam thoi trong /tmp de ap dung IMAGE_REGISTRY/TAG
#      va INGRESS_HOST (giu git working tree sach 100%)
#   4. Trien khai theo dung thu tu:
#        Stateful (Postgres, Mongo, Redis, RabbitMQ)
#        -> Eureka Server
#        -> Core + Node + Web Services
#        -> API Gateway + Ingress (hoac 11-ingress-tls.yaml neu da cau hinh HTTPS)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$K3S_DIR/.env.k3s"
NAMESPACE="backhaulbid"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Khong tim thay $ENV_FILE" >&2
  echo "Hay tao file cau hinh: cp k3s/.env.k3s.example k3s/.env.k3s && chmod 600 k3s/.env.k3s && nano k3s/.env.k3s" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Default gia tri khong bat buoc
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
INGRESS_HOST="${INGRESS_HOST:-}"
COOKIE_SECURE="${COOKIE_SECURE:-false}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-backhaulbid}"
IMAGE_TAG="${IMAGE_TAG:-v1}"

POSTGRES_USER="${POSTGRES_USER:-backhaulbid}"
MONGO_USER="${MONGO_USER:-backhaulbid}"
RABBITMQ_USER="${RABBITMQ_USER:-backhaulbid}"

FRONTEND_ORIGIN="${FRONTEND_ORIGIN:-$PUBLIC_BASE_URL}"
FRONTEND_LAN_ORIGIN="${FRONTEND_LAN_ORIGIN:-http://localhost:3000}"
EXPO_WEB_ORIGIN="${EXPO_WEB_ORIGIN:-http://localhost:3002}"
EXPO_LAN_ORIGIN="${EXPO_LAN_ORIGIN:-http://localhost:3002}"

SWAGGER_ENABLED="${SWAGGER_ENABLED:-false}"
NEXT_PUBLIC_BIDDING_SOCKET_PATH="${NEXT_PUBLIC_BIDDING_SOCKET_PATH:-/bidding-socket}"
IDENTITY_FLYWAY_LOCATIONS="${IDENTITY_FLYWAY_LOCATIONS:-classpath:db/migration}"

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
AWS_S3_BUCKET="${AWS_S3_BUCKET:-backhaulbid-s3}"

CONTRACT_OTP_MAIL_ENABLED="${CONTRACT_OTP_MAIL_ENABLED:-true}"
MAIL_HOST="${MAIL_HOST:-smtp-relay.brevo.com}"
MAIL_PORT="${MAIL_PORT:-587}"
MAIL_USERNAME="${MAIL_USERNAME:-}"
MAIL_PASSWORD="${MAIL_PASSWORD:-}"
MAIL_FROM="${MAIL_FROM:-no-reply@backhaulbid.vn}"
MAIL_FROM_NAME="${MAIL_FROM_NAME:-BackhaulBid}"
MAIL_SMTP_AUTH="${MAIL_SMTP_AUTH:-true}"
MAIL_SMTP_STARTTLS="${MAIL_SMTP_STARTTLS:-true}"

SEPAY_ENABLED="${SEPAY_ENABLED:-false}"
SEPAY_MERCHANT_ID="${SEPAY_MERCHANT_ID:-}"
SEPAY_SECRET_KEY="${SEPAY_SECRET_KEY:-}"
SEPAY_IPN_SECRET="${SEPAY_IPN_SECRET:-$SEPAY_SECRET_KEY}"
SEPAY_CHECKOUT_URL="${SEPAY_CHECKOUT_URL:-https://pay-sandbox.sepay.vn/v1/checkout/init}"
SEPAY_SUCCESS_URL="${SEPAY_SUCCESS_URL:-${PUBLIC_BASE_URL}/carrier/wallet?payment=success}"
SEPAY_ERROR_URL="${SEPAY_ERROR_URL:-${PUBLIC_BASE_URL}/carrier/wallet?payment=error}"
SEPAY_CANCEL_URL="${SEPAY_CANCEL_URL:-${PUBLIC_BASE_URL}/carrier/wallet?payment=cancel}"

GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
NFC_EKYC_ENABLED="${NFC_EKYC_ENABLED:-false}"
EKYC_EVIDENCE_ENCRYPTION_KEY="${EKYC_EVIDENCE_ENCRYPTION_KEY:-}"
EKYC_AUTO_ACCEPT="${EKYC_AUTO_ACCEPT:-DISABLED}"
BUSINESS_LOOKUP_CLIENT_ID="${BUSINESS_LOOKUP_CLIENT_ID:-}"
BUSINESS_LOOKUP_API_KEY="${BUSINESS_LOOKUP_API_KEY:-}"
DRIVER_REPLAY_KEY="${DRIVER_REPLAY_KEY:-}"
ROUTING_BASE_URL="${ROUTING_BASE_URL:-https://router.project-osrm.org}"

# ------------------------------------------------------------------------------
# Validate bien bat buoc
# ------------------------------------------------------------------------------
REQUIRED_VARS=(
  PUBLIC_BASE_URL
  POSTGRES_PASSWORD
  MONGO_PASSWORD
  REDIS_PASSWORD
  RABBITMQ_PASSWORD
  JWT_SECRET
  INTERNAL_SERVICE_TOKEN
  INTERNAL_WALLET_TOKEN
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
)

VALIDATION_FAILED=false
for var_name in "${REQUIRED_VARS[@]}"; do
  val="${!var_name:-}"
  if [[ -z "$val" || "$val" == CHANGE_ME_* || "$val" == *"<EC2_PUBLIC_IP>"* ]]; then
    echo "ERROR: Bien bat buoc '$var_name' chua duoc dien hoac van con gia tri mau trong $ENV_FILE" >&2
    VALIDATION_FAILED=true
  fi
done

decode_base64_bytes() {
  local raw="$1"
  local decoded_len
  if ! decoded_len=$(printf '%s' "$raw" | base64 -d 2>/dev/null | wc -c); then
    echo "-1"
    return
  fi
  echo "${decoded_len// /}"
}

JWT_BYTES="$(decode_base64_bytes "$JWT_SECRET")"
if [[ "$JWT_BYTES" -lt 32 ]]; then
  echo "ERROR: JWT_SECRET phai la chuoi Base64 hop le >= 32 bytes (tao bang: openssl rand -base64 48)." >&2
  VALIDATION_FAILED=true
fi

if [[ "$DRIVER_REPLAY_KEY" == CHANGE_ME_* ]]; then
  echo "ERROR: DRIVER_REPLAY_KEY van con gia tri mau CHANGE_ME_* (tao bang: openssl rand -base64 32 hoac de trong)." >&2
  VALIDATION_FAILED=true
elif [[ -n "$DRIVER_REPLAY_KEY" ]]; then
  REPLAY_BYTES="$(decode_base64_bytes "$DRIVER_REPLAY_KEY")"
  if [[ "$REPLAY_BYTES" -ne 32 ]]; then
    echo "ERROR: DRIVER_REPLAY_KEY phai la chuoi Base64 dung 32 bytes (tao bang: openssl rand -base64 32)." >&2
    VALIDATION_FAILED=true
  fi
fi

if [[ "$NFC_EKYC_ENABLED" == "true" ]]; then
  EKYC_BYTES="$(decode_base64_bytes "$EKYC_EVIDENCE_ENCRYPTION_KEY")"
  if [[ -z "$EKYC_EVIDENCE_ENCRYPTION_KEY" || "$EKYC_BYTES" -ne 32 ]]; then
    echo "ERROR: NFC_EKYC_ENABLED=true can EKYC_EVIDENCE_ENCRYPTION_KEY la Base64 dung 32 bytes (openssl rand -base64 32)." >&2
    VALIDATION_FAILED=true
  fi
fi

if [[ "$SEPAY_ENABLED" == "true" && ( -z "$SEPAY_MERCHANT_ID" || -z "$SEPAY_SECRET_KEY" ) ]]; then
  echo "ERROR: SEPAY_ENABLED=true nhung thieu SEPAY_MERCHANT_ID hoac SEPAY_SECRET_KEY." >&2
  VALIDATION_FAILED=true
fi

if [[ "$VALIDATION_FAILED" == "true" ]]; then
  exit 1
fi

# Canh bao an toan cho cookie HTTP vs HTTPS
if [[ "$PUBLIC_BASE_URL" == http://* && "$COOKIE_SECURE" == "true" ]]; then
  echo "WARNING: PUBLIC_BASE_URL dung HTTP nhung COOKIE_SECURE=true -> trinh duyet se tu choi luu cookie dang nhap!" >&2
  echo "         Hay dat COOKIE_SECURE=false khi dung HTTP, hoac chuyen sang HTTPS domain." >&2
fi
if [[ "$PUBLIC_BASE_URL" == https://* && "$COOKIE_SECURE" != "true" ]]; then
  echo "WARNING: PUBLIC_BASE_URL dung HTTPS nhung COOKIE_SECURE=$COOKIE_SECURE -> khuyen nghi dat COOKIE_SECURE=true." >&2
fi

echo "==> [1/6] Tao Namespace '$NAMESPACE'..."
kubectl apply -f "$K3S_DIR/00-namespace.yaml"

echo "==> [2/6] Cap nhat Secret 'backhaulbid-secrets' (khong ghi secret ra file)..."
kubectl -n "$NAMESPACE" create secret generic backhaulbid-secrets \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=MONGO_PASSWORD="$MONGO_PASSWORD" \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --from-literal=RABBITMQ_PASSWORD="$RABBITMQ_PASSWORD" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=INTERNAL_SERVICE_TOKEN="$INTERNAL_SERVICE_TOKEN" \
  --from-literal=INTERNAL_WALLET_TOKEN="$INTERNAL_WALLET_TOKEN" \
  --from-literal=DRIVER_REPLAY_KEY="$DRIVER_REPLAY_KEY" \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=MAIL_USERNAME="$MAIL_USERNAME" \
  --from-literal=MAIL_PASSWORD="$MAIL_PASSWORD" \
  --from-literal=SEPAY_MERCHANT_ID="$SEPAY_MERCHANT_ID" \
  --from-literal=SEPAY_SECRET_KEY="$SEPAY_SECRET_KEY" \
  --from-literal=SEPAY_IPN_SECRET="$SEPAY_IPN_SECRET" \
  --from-literal=EKYC_EVIDENCE_ENCRYPTION_KEY="$EKYC_EVIDENCE_ENCRYPTION_KEY" \
  --from-literal=BUSINESS_LOOKUP_CLIENT_ID="$BUSINESS_LOOKUP_CLIENT_ID" \
  --from-literal=BUSINESS_LOOKUP_API_KEY="$BUSINESS_LOOKUP_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> [3/6] Cap nhat ConfigMap 'backhaulbid-config'..."
kubectl -n "$NAMESPACE" create configmap backhaulbid-config \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_DB="backhaulbid_identity" \
  --from-literal=POSTGRES_IDENTITY_URL="jdbc:postgresql://postgres:5432/backhaulbid_identity" \
  --from-literal=POSTGRES_FLEET_URL="jdbc:postgresql://postgres:5432/backhaulbid_fleet" \
  --from-literal=POSTGRES_WALLET_URL="jdbc:postgresql://postgres:5432/backhaulbid_wallet" \
  --from-literal=POSTGRES_CONTRACT_URL="jdbc:postgresql://postgres:5432/backhaulbid_contract" \
  --from-literal=MONGO_USER="$MONGO_USER" \
  --from-literal=MONGO_HOST="mongodb" \
  --from-literal=MONGO_PORT="27017" \
  --from-literal=MONGO_BIDDING_DATABASE="backhaulbid_bidding" \
  --from-literal=MONGO_NOTIFICATION_DATABASE="backhaulbid_notification" \
  --from-literal=REDIS_HOST="redis" \
  --from-literal=REDIS_PORT="6379" \
  --from-literal=RABBITMQ_USER="$RABBITMQ_USER" \
  --from-literal=RABBITMQ_HOST="rabbitmq" \
  --from-literal=RABBITMQ_PORT="5672" \
  --from-literal=EUREKA_URL="http://eureka-server:8761/eureka/" \
  --from-literal=INTERNAL_GATEWAY_URL="http://api-gateway:8080" \
  --from-literal=IDENTITY_SERVICE_URL="http://identity-service:8080" \
  --from-literal=FLEET_SERVICE_URL="http://fleet-service:8080" \
  --from-literal=WALLET_SERVICE_URL="http://wallet-service:8080" \
  --from-literal=CONTRACT_SERVICE_URL="http://contract-service:8080" \
  --from-literal=MEDIA_SERVICE_URL="http://media-service:8080" \
  --from-literal=NOTIFICATION_SERVICE_URL="http://notification-service:3002" \
  --from-literal=NEXT_PUBLIC_GATEWAY_URL="$PUBLIC_BASE_URL" \
  --from-literal=NEXT_PUBLIC_BIDDING_SOCKET_PATH="$NEXT_PUBLIC_BIDDING_SOCKET_PATH" \
  --from-literal=COOKIE_SECURE="$COOKIE_SECURE" \
  --from-literal=FRONTEND_ORIGIN="$FRONTEND_ORIGIN" \
  --from-literal=FRONTEND_LAN_ORIGIN="$FRONTEND_LAN_ORIGIN" \
  --from-literal=EXPO_WEB_ORIGIN="$EXPO_WEB_ORIGIN" \
  --from-literal=EXPO_LAN_ORIGIN="$EXPO_LAN_ORIGIN" \
  --from-literal=SWAGGER_ENABLED="$SWAGGER_ENABLED" \
  --from-literal=OPENAPI_GATEWAY_SERVER_URL="/api/v1/bidding" \
  --from-literal=OPENAPI_DIRECT_SERVER_URL="http://bidding-service:3001" \
  --from-literal=IDENTITY_FLYWAY_LOCATIONS="$IDENTITY_FLYWAY_LOCATIONS" \
  --from-literal=SPRING_JPA_SHOW_SQL="false" \
  --from-literal=SERVER_SHUTDOWN="graceful" \
  --from-literal=AWS_REGION="$AWS_REGION" \
  --from-literal=AWS_S3_BUCKET="$AWS_S3_BUCKET" \
  --from-literal=CONTRACT_OTP_MAIL_ENABLED="$CONTRACT_OTP_MAIL_ENABLED" \
  --from-literal=MAIL_HOST="$MAIL_HOST" \
  --from-literal=MAIL_PORT="$MAIL_PORT" \
  --from-literal=MAIL_FROM="$MAIL_FROM" \
  --from-literal=MAIL_FROM_NAME="$MAIL_FROM_NAME" \
  --from-literal=MAIL_SMTP_AUTH="$MAIL_SMTP_AUTH" \
  --from-literal=MAIL_SMTP_STARTTLS="$MAIL_SMTP_STARTTLS" \
  --from-literal=SEPAY_ENABLED="$SEPAY_ENABLED" \
  --from-literal=SEPAY_CHECKOUT_URL="$SEPAY_CHECKOUT_URL" \
  --from-literal=SEPAY_SUCCESS_URL="$SEPAY_SUCCESS_URL" \
  --from-literal=SEPAY_ERROR_URL="$SEPAY_ERROR_URL" \
  --from-literal=SEPAY_CANCEL_URL="$SEPAY_CANCEL_URL" \
  --from-literal=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
  --from-literal=NFC_EKYC_ENABLED="$NFC_EKYC_ENABLED" \
  --from-literal=EKYC_AUTO_ACCEPT="$EKYC_AUTO_ACCEPT" \
  --from-literal=ROUTING_BASE_URL="$ROUTING_BASE_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> [4/6] Trien khai tang du lieu (PostgreSQL, MongoDB, Redis, RabbitMQ)..."
kubectl apply -f "$K3S_DIR/02-postgres.yaml"
kubectl apply -f "$K3S_DIR/03-mongodb.yaml"
kubectl apply -f "$K3S_DIR/04-redis.yaml"
kubectl apply -f "$K3S_DIR/05-rabbitmq.yaml"

echo "    Dang cho cac StatefulSet san sang..."
kubectl -n "$NAMESPACE" rollout status statefulset/postgres --timeout=180s
kubectl -n "$NAMESPACE" rollout status statefulset/mongodb --timeout=180s
kubectl -n "$NAMESPACE" rollout status statefulset/redis --timeout=120s
kubectl -n "$NAMESPACE" rollout status statefulset/rabbitmq --timeout=240s

# Tao overlay tam thoi trong /tmp de override IMAGE_REGISTRY/TAG ma khong lam ban git
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$K3S_DIR/06-eureka-server.yaml" "$TMP_DIR/"
cp "$K3S_DIR/07-core-services.yaml" "$TMP_DIR/"
cp "$K3S_DIR/08-node-services.yaml" "$TMP_DIR/"
cp "$K3S_DIR/09-web-portal.yaml" "$TMP_DIR/"
cp "$K3S_DIR/10-api-gateway.yaml" "$TMP_DIR/"
cp "$K3S_DIR/11-ingress.yaml" "$TMP_DIR/"

cat > "$TMP_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - 06-eureka-server.yaml
  - 07-core-services.yaml
  - 08-node-services.yaml
  - 09-web-portal.yaml
  - 10-api-gateway.yaml
  - 11-ingress.yaml
images:
  - name: backhaulbid/eureka-server
    newName: ${IMAGE_REGISTRY}/eureka-server
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/identity-service
    newName: ${IMAGE_REGISTRY}/identity-service
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/fleet-service
    newName: ${IMAGE_REGISTRY}/fleet-service
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/wallet-service
    newName: ${IMAGE_REGISTRY}/wallet-service
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/contract-service
    newName: ${IMAGE_REGISTRY}/contract-service
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/media-service
    newName: ${IMAGE_REGISTRY}/media-service
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/bidding-service
    newName: ${IMAGE_REGISTRY}/bidding-service
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/notification-service
    newName: ${IMAGE_REGISTRY}/notification-service
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/web-portal
    newName: ${IMAGE_REGISTRY}/web-portal
    newTag: "${IMAGE_TAG}"
  - name: backhaulbid/api-gateway
    newName: ${IMAGE_REGISTRY}/api-gateway
    newTag: "${IMAGE_TAG}"
EOF

if [[ -n "$INGRESS_HOST" && ! -f "$K3S_DIR/11-ingress-tls.yaml" ]]; then
  cat >> "$TMP_DIR/kustomization.yaml" <<EOF
patches:
  - target:
      kind: Ingress
      name: backhaulbid-ingress
    patch: |-
      - op: add
        path: /spec/rules/0/host
        value: "${INGRESS_HOST}"
EOF
fi

echo "==> [5/6] Trien khai Eureka Server & cac microservices (${IMAGE_REGISTRY}/*:${IMAGE_TAG})..."
kubectl apply -k "$TMP_DIR"

if [[ -f "$K3S_DIR/11-ingress-tls.yaml" ]]; then
  echo "    Phat hien k3s/11-ingress-tls.yaml -> ap dung cau hinh HTTPS TLS..."
  kubectl apply -f "$K3S_DIR/11-ingress-tls.yaml"
fi

echo "==> [6/6] Dang cho cac Deployment san sang (co the mat 1-3 phut)..."
kubectl -n "$NAMESPACE" rollout status deploy/eureka-server --timeout=240s
for deploy in identity-service fleet-service wallet-service contract-service media-service bidding-service notification-service web-portal api-gateway; do
  kubectl -n "$NAMESPACE" rollout status "deploy/${deploy}" --timeout=300s
done

echo ""
echo "=============================================================================="
echo "TRIEN KHAI BACKHAULBID LEN K3S THANH CONG!"
echo "  Dia chi truy cap: ${PUBLIC_BASE_URL}"
echo "  Kiem tra Pods   : kubectl -n ${NAMESPACE} get pods -o wide"
echo "  Kiem tra Ingress: kubectl -n ${NAMESPACE} get ingress"
echo "=============================================================================="
kubectl -n "$NAMESPACE" get pods
