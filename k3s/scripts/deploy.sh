#!/usr/bin/env bash
# ==============================================================================
# BackHaulBid - Deploy len K3s tu file k3s/.env.k3s (Stateless App-Only + External DB)
#
# Cach dung:
#   ./k3s/scripts/deploy.sh
#   ./k3s/scripts/deploy.sh --tag v1.0.2
#   ./k3s/scripts/deploy.sh --tag v1.0.2 --services web-portal,api-gateway
#   IMAGE_TAG=a1b2c3d ./k3s/scripts/deploy.sh
#
# Script nay thuc hien:
#   1. Kiem tra tinh hop le cua k3s/.env.k3s (bao gom URI CSDL ngoai: Aiven/Atlas/CloudAMQP)
#   2. Tao/cap nhat Namespace, Secret (gom dockerhub-regcred, MONGO_*_URI, REDIS_URL, RABBITMQ_URL)
#   3. Tach URI thanh tham so ket noi va cap nhat ConfigMap 'backhaulbid-config'
#   4. Render Kustomize overlay tam thoi (overlays/http hoac overlays/tls) trong /tmp
#   5. Trien khai & cho 9 Deployment stateless + Traefik Ingress san sang
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$(cd "$K3S_DIR/.." && pwd)"
ENV_FILE="$K3S_DIR/.env.k3s"
NAMESPACE="backhaulbid"

# Giu lai bien truyen tu shell/CLI (uu tien cao hon .env.k3s)
ENV_OVERRIDE_REGISTRY="${IMAGE_REGISTRY-}"
HAS_OVERRIDE_PREFIX=false
if [[ -n "${IMAGE_PREFIX+x}" ]]; then
  HAS_OVERRIDE_PREFIX=true
  ENV_OVERRIDE_PREFIX="$IMAGE_PREFIX"
fi
ENV_OVERRIDE_TAG="${IMAGE_TAG-}"
ENV_OVERRIDE_PULL_POLICY="${IMAGE_PULL_POLICY-}"
ENV_OVERRIDE_REPLICAS="${APP_REPLICAS-}"
ENV_OVERRIDE_SERVICES="${DEPLOY_SERVICES-}"
CLI_TAG=""
CLI_SERVICES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --services)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --services can danh sach service hoac 'all'." >&2
        exit 1
      fi
      CLI_SERVICES="$2"
      shift 2
      ;;
    --services=*)
      CLI_SERVICES="${1#*=}"
      shift
      ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: Tham so khong hop le: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Khong tim thay $ENV_FILE" >&2
  echo "Hay tao file cau hinh: cp k3s/.env.k3s.example k3s/.env.k3s && chmod 600 k3s/.env.k3s && nano k3s/.env.k3s" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/_load-env.sh"
load_env_file "$ENV_FILE"

# Default gia tri & ap dung uu tien override
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
INGRESS_HOST="${INGRESS_HOST:-}"
COOKIE_SECURE="${COOKIE_SECURE:-false}"

IMAGE_REGISTRY="${ENV_OVERRIDE_REGISTRY:-${IMAGE_REGISTRY:-backhaulbid}}"
if [[ "$HAS_OVERRIDE_PREFIX" == "true" ]]; then
  IMAGE_PREFIX="$ENV_OVERRIDE_PREFIX"
else
  IMAGE_PREFIX="${IMAGE_PREFIX:-}"
fi
IMAGE_TAG="${CLI_TAG:-${ENV_OVERRIDE_TAG:-${IMAGE_TAG:-auto}}}"
IMAGE_PULL_POLICY="${ENV_OVERRIDE_PULL_POLICY:-${IMAGE_PULL_POLICY:-}}"
APP_REPLICAS="${ENV_OVERRIDE_REPLICAS:-${APP_REPLICAS:-2}}"
DB_POOL_MAX_SIZE="${DB_POOL_MAX_SIZE:-2}"
DB_POOL_LIGHT_MAX_SIZE="${DB_POOL_LIGHT_MAX_SIZE:-2}"
DB_POOL_MIN_IDLE="${DB_POOL_MIN_IDLE:-1}"
DEPLOY_SERVICES="${CLI_SERVICES:-${ENV_OVERRIDE_SERVICES:-all}}"

if [[ -z "$IMAGE_TAG" || "$IMAGE_TAG" == "auto" ]]; then
  if git -C "$INFRA_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
    IMAGE_TAG="$(git -C "$INFRA_DIR" rev-parse --short HEAD)"
  else
    IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
  fi
fi

ALL_SERVICES=(identity-service fleet-service wallet-service contract-service media-service bidding-service notification-service web-portal api-gateway)
PARTIAL_DEPLOY=false
TARGET_SERVICES_CSV=""
if [[ -n "$DEPLOY_SERVICES" && "$DEPLOY_SERVICES" != "all" ]]; then
  PARTIAL_DEPLOY=true
  if [[ "$DEPLOY_SERVICES" != "none" ]]; then
    IFS=',' read -r -a RAW_SERVICES <<< "$DEPLOY_SERVICES"
    for raw_svc in "${RAW_SERVICES[@]}"; do
      svc="$(printf '%s' "$raw_svc" | tr -d '[:space:]')"
      [[ -z "$svc" ]] && continue
      valid=false
      for known in "${ALL_SERVICES[@]}"; do
        if [[ "$svc" == "$known" ]]; then
          valid=true
          break
        fi
      done
      if [[ "$valid" != "true" ]]; then
        echo "ERROR: Service khong hop le trong --services: '$svc'. Hop le: all, none, ${ALL_SERVICES[*]}" >&2
        exit 1
      fi
      if [[ ",${TARGET_SERVICES_CSV}," != *",${svc},"* ]]; then
        TARGET_SERVICES_CSV="${TARGET_SERVICES_CSV:+${TARGET_SERVICES_CSV},}${svc}"
      fi
    done
    if [[ -z "$TARGET_SERVICES_CSV" ]]; then
      echo "ERROR: Danh sach --services rong." >&2
      exit 1
    fi
  fi
fi

if [[ "$IMAGE_TAG" == "latest" ]]; then
  echo "WARNING: Dang dung IMAGE_TAG=latest — khuyen nghi dung version tag co dinh (vd v1.0.0) hoac Git SHA de K3s roll out nhat quan." >&2
fi

if [[ -z "$IMAGE_PULL_POLICY" ]]; then
  if [[ "$IMAGE_REGISTRY" != "backhaulbid" && ( "$IMAGE_TAG" == "latest" || "$IMAGE_TAG" == "dev" ) ]]; then
    IMAGE_PULL_POLICY="Always"
  else
    IMAGE_PULL_POLICY="IfNotPresent"
  fi
fi

DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"
DOCKERHUB_SERVER="${DOCKERHUB_SERVER:-https://index.docker.io/v1/}"
IMAGE_PULL_SECRET_NAME="${IMAGE_PULL_SECRET_NAME:-dockerhub-regcred}"

POSTGRES_HOST="${POSTGRES_HOST:-}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-avnadmin}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_SSLMODE="${POSTGRES_SSLMODE:-require}"
POSTGRES_IDENTITY_URL="${POSTGRES_IDENTITY_URL:-}"
POSTGRES_FLEET_URL="${POSTGRES_FLEET_URL:-}"
POSTGRES_WALLET_URL="${POSTGRES_WALLET_URL:-}"
POSTGRES_CONTRACT_URL="${POSTGRES_CONTRACT_URL:-}"

if [[ -n "$POSTGRES_HOST" && "$POSTGRES_HOST" != CHANGE_ME_* ]]; then
  POSTGRES_IDENTITY_URL="${POSTGRES_IDENTITY_URL:-jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/backhaulbid_identity?sslmode=${POSTGRES_SSLMODE}}"
  POSTGRES_FLEET_URL="${POSTGRES_FLEET_URL:-jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/backhaulbid_fleet?sslmode=${POSTGRES_SSLMODE}}"
  POSTGRES_WALLET_URL="${POSTGRES_WALLET_URL:-jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/backhaulbid_wallet?sslmode=${POSTGRES_SSLMODE}}"
  POSTGRES_CONTRACT_URL="${POSTGRES_CONTRACT_URL:-jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/backhaulbid_contract?sslmode=${POSTGRES_SSLMODE}}"
fi

MONGO_BIDDING_URI="${MONGO_BIDDING_URI:-}"
MONGO_NOTIFICATION_URI="${MONGO_NOTIFICATION_URI:-}"
REDIS_URL="${REDIS_URL:-}"
RABBITMQ_URL="${RABBITMQ_URL:-}"

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
EKYC_AUTO_ACCEPT="${EKYC_AUTO_ACCEPT:-COMPLETED_ONLY}"
BUSINESS_LOOKUP_CLIENT_ID="${BUSINESS_LOOKUP_CLIENT_ID:-}"
BUSINESS_LOOKUP_API_KEY="${BUSINESS_LOOKUP_API_KEY:-}"
DRIVER_REPLAY_KEY="${DRIVER_REPLAY_KEY:-}"
ROUTING_BASE_URL="${ROUTING_BASE_URL:-https://router.project-osrm.org}"

# ------------------------------------------------------------------------------
# Helper tach URI thanh 6 dong: scheme, user, pass, host, port, vhost
# ------------------------------------------------------------------------------
url_decode() {
  local s="${1//\\/\\\\}"
  printf '%b' "${s//%/\\x}"
}

parse_uri() {
  local uri="$1"
  local default_port="$2"
  if command -v python3 >/dev/null 2>&1 && python3 -c "import urllib.parse" >/dev/null 2>&1; then
    python3 - "$uri" "$default_port" <<'PY'
import sys
from urllib.parse import urlparse, unquote

u = urlparse(sys.argv[1])
def_port = sys.argv[2]
scheme = (u.scheme or "").lower()
user = unquote(u.username) if u.username is not None else ""
pw = unquote(u.password) if u.password is not None else ""
host = u.hostname or ""
port = str(u.port) if u.port else def_port
raw_path = u.path[1:] if u.path.startswith("/") else u.path
vhost = unquote(raw_path) if raw_path else "/"
for item in (scheme, user, pw, host, port, vhost):
    print(item)
PY
    return
  fi

  if [[ "$uri" =~ ^([a-zA-Z0-9+.-]+)://(([^:@/?#]*)(:([^@/?#]*))?@)?(\[[^]]+\]|[^:/?#]+)(:([0-9]+))?(/[^?#]*)?([?].*)?$ ]]; then
    local scheme="${BASH_REMATCH[1],,}"
    local user
    local pw
    user="$(url_decode "${BASH_REMATCH[3]}")"
    pw="$(url_decode "${BASH_REMATCH[5]}")"
    local host="${BASH_REMATCH[6]}"
    local port="${BASH_REMATCH[8]:-$default_port}"
    local path="${BASH_REMATCH[9]}"
    local vhost
    vhost="$(url_decode "${path#/}")"
    [[ -z "$vhost" ]] && vhost="/"
    printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$scheme" "$user" "$pw" "$host" "$port" "$vhost"
  else
    printf '\n\n\n\n\n\n'
  fi
}

# ------------------------------------------------------------------------------
# Validate bien bat buoc
# ------------------------------------------------------------------------------
REQUIRED_VARS=(
  PUBLIC_BASE_URL
  POSTGRES_USER
  POSTGRES_PASSWORD
  POSTGRES_IDENTITY_URL
  POSTGRES_FLEET_URL
  POSTGRES_WALLET_URL
  POSTGRES_CONTRACT_URL
  MONGO_BIDDING_URI
  MONGO_NOTIFICATION_URI
  REDIS_URL
  RABBITMQ_URL
  JWT_SECRET
  INTERNAL_SERVICE_TOKEN
  INTERNAL_WALLET_TOKEN
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
)

VALIDATION_FAILED=false
for var_name in "${REQUIRED_VARS[@]}"; do
  val="${!var_name:-}"
  if [[ -z "$val" || "$val" == CHANGE_ME_* || "$val" == *"<EC2_PUBLIC_IP>"* || "$val" == *"<user>"* || "$val" == *"<pass>"* || "$val" == *"<host>"* ]]; then
    echo "ERROR: Bien bat buoc '$var_name' chua duoc dien hoac van con gia tri mau trong $ENV_FILE" >&2
    VALIDATION_FAILED=true
  fi
done

for pg_var in POSTGRES_IDENTITY_URL POSTGRES_FLEET_URL POSTGRES_WALLET_URL POSTGRES_CONTRACT_URL; do
  pg_val="${!pg_var:-}"
  if [[ -n "$pg_val" && "$pg_val" != jdbc:postgresql://* ]]; then
    echo "ERROR: $pg_var phai bat dau bang 'jdbc:postgresql://' (hien tai: $pg_val)." >&2
    VALIDATION_FAILED=true
  fi
done

for mongo_var in MONGO_BIDDING_URI MONGO_NOTIFICATION_URI; do
  mongo_val="${!mongo_var:-}"
  if [[ -n "$mongo_val" && "$mongo_val" != mongodb://* && "$mongo_val" != mongodb+srv://* ]]; then
    echo "ERROR: $mongo_var phai bat dau bang 'mongodb://' hoac 'mongodb+srv://'." >&2
    VALIDATION_FAILED=true
  fi
done

if [[ -n "$REDIS_URL" && "$REDIS_URL" != redis://* && "$REDIS_URL" != rediss://* ]]; then
  echo "ERROR: REDIS_URL phai bat dau bang 'redis://' hoac 'rediss://' (Aiven Valkey dung rediss://)." >&2
  VALIDATION_FAILED=true
fi

if [[ -n "$RABBITMQ_URL" && "$RABBITMQ_URL" != amqp://* && "$RABBITMQ_URL" != amqps://* ]]; then
  echo "ERROR: RABBITMQ_URL phai bat dau bang 'amqp://' hoac 'amqps://' (CloudAMQP dung amqps://)." >&2
  VALIDATION_FAILED=true
fi

for int_var in APP_REPLICAS DB_POOL_MAX_SIZE DB_POOL_LIGHT_MAX_SIZE DB_POOL_MIN_IDLE; do
  int_val="${!int_var:-}"
  if ! [[ "$int_val" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: $int_var phai la so nguyen duong >= 1 (hien tai: '$int_val')." >&2
    VALIDATION_FAILED=true
  fi
done

if [[ "$DB_POOL_MAX_SIZE" =~ ^[1-9][0-9]*$ && "$DB_POOL_MAX_SIZE" -lt 2 ]]; then
  echo "ERROR: DB_POOL_MAX_SIZE phai >= 2 de tranh deadlock khi PostgresAdvisoryLock giu ket noi chay @Scheduled (identity/contract)." >&2
  VALIDATION_FAILED=true
fi

if [[ "$DB_POOL_LIGHT_MAX_SIZE" =~ ^[1-9][0-9]*$ && "$DB_POOL_LIGHT_MAX_SIZE" -lt 2 ]]; then
  echo "ERROR: DB_POOL_LIGHT_MAX_SIZE phai >= 2 de tranh deadlock khi Flyway migration giu lock PostgreSQL (fleet/wallet)." >&2
  VALIDATION_FAILED=true
fi

if [[ "$DB_POOL_MAX_SIZE" =~ ^[1-9][0-9]*$ && "$DB_POOL_MIN_IDLE" =~ ^[1-9][0-9]*$ && "$DB_POOL_MIN_IDLE" -gt "$DB_POOL_MAX_SIZE" ]]; then
  echo "ERROR: DB_POOL_MIN_IDLE ($DB_POOL_MIN_IDLE) khong duoc lon hon DB_POOL_MAX_SIZE ($DB_POOL_MAX_SIZE)." >&2
  VALIDATION_FAILED=true
fi

if [[ "$DB_POOL_LIGHT_MAX_SIZE" =~ ^[1-9][0-9]*$ && "$DB_POOL_MIN_IDLE" =~ ^[1-9][0-9]*$ && "$DB_POOL_MIN_IDLE" -gt "$DB_POOL_LIGHT_MAX_SIZE" ]]; then
  echo "ERROR: DB_POOL_MIN_IDLE ($DB_POOL_MIN_IDLE) khong duoc lon hon DB_POOL_LIGHT_MAX_SIZE ($DB_POOL_LIGHT_MAX_SIZE)." >&2
  VALIDATION_FAILED=true
fi

if [[ "$APP_REPLICAS" =~ ^[1-9][0-9]*$ && "$DB_POOL_MAX_SIZE" =~ ^[1-9][0-9]*$ && "$DB_POOL_LIGHT_MAX_SIZE" =~ ^[1-9][0-9]*$ ]]; then
  EST_MAX_PG_CONNS=$(( APP_REPLICAS * (2 * DB_POOL_MAX_SIZE + 2 * DB_POOL_LIGHT_MAX_SIZE) ))
  if [[ "$EST_MAX_PG_CONNS" -gt 15 ]]; then
    echo "WARNING: Tong max connections PostgreSQL uoc tinh = ${EST_MAX_PG_CONNS} (> 15 connection limit cua Aiven Free)." >&2
  fi
fi

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

# Tach REDIS_URL -> cac truong cho api-gateway
{
  IFS= read -r REDIS_SCHEME || true
  IFS= read -r REDIS_USERNAME || true
  IFS= read -r REDIS_PASSWORD || true
  IFS= read -r REDIS_HOST || true
  IFS= read -r REDIS_PORT || true
  IFS= read -r _ || true
} < <(parse_uri "$REDIS_URL" "6379")

if [[ -z "$REDIS_HOST" ]]; then
  echo "ERROR: Khong doc duoc host tu REDIS_URL." >&2
  exit 1
fi
REDIS_SSL_ENABLED="false"
[[ "$REDIS_SCHEME" == "rediss" ]] && REDIS_SSL_ENABLED="true"

# Tach RABBITMQ_URL -> cac truong cho contract-service
RABBIT_DEFAULT_PORT="5672"
[[ "$RABBITMQ_URL" == amqps://* ]] && RABBIT_DEFAULT_PORT="5671"
{
  IFS= read -r RABBITMQ_SCHEME || true
  IFS= read -r RABBITMQ_USER || true
  IFS= read -r RABBITMQ_PASSWORD || true
  IFS= read -r RABBITMQ_HOST || true
  IFS= read -r RABBITMQ_PORT || true
  IFS= read -r RABBITMQ_VHOST || true
} < <(parse_uri "$RABBITMQ_URL" "$RABBIT_DEFAULT_PORT")

if [[ -z "$RABBITMQ_HOST" ]]; then
  echo "ERROR: Khong doc duoc host tu RABBITMQ_URL." >&2
  exit 1
fi
RABBITMQ_SSL_ENABLED="false"
[[ "$RABBITMQ_SCHEME" == "amqps" ]] && RABBITMQ_SSL_ENABLED="true"

# Canh bao an toan cho cookie HTTP vs HTTPS
if [[ "$PUBLIC_BASE_URL" == http://* && "$COOKIE_SECURE" == "true" ]]; then
  echo "WARNING: PUBLIC_BASE_URL dung HTTP nhung COOKIE_SECURE=true -> trinh duyet se tu choi luu cookie dang nhap!" >&2
  echo "         Hay dat COOKIE_SECURE=false khi dung HTTP, hoac chuyen sang HTTPS domain." >&2
fi
if [[ "$PUBLIC_BASE_URL" == https://* && "$COOKIE_SECURE" != "true" ]]; then
  echo "WARNING: PUBLIC_BASE_URL dung HTTPS nhung COOKIE_SECURE=$COOKIE_SECURE -> khuyen nghi dat COOKIE_SECURE=true." >&2
fi

echo "==> [1/5] Tao Namespace '$NAMESPACE'..."
kubectl apply -f "$K3S_DIR/base/00-namespace.yaml"

echo "==> [2/5] Cap nhat Secret 'backhaulbid-secrets'..."
SECRETS_YAML="$(kubectl -n "$NAMESPACE" create secret generic backhaulbid-secrets \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=MONGO_BIDDING_URI="$MONGO_BIDDING_URI" \
  --from-literal=MONGO_NOTIFICATION_URI="$MONGO_NOTIFICATION_URI" \
  --from-literal=REDIS_URL="$REDIS_URL" \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --from-literal=RABBITMQ_URL="$RABBITMQ_URL" \
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
  --dry-run=client -o yaml)"
printf '%s\n' "$SECRETS_YAML" | kubectl apply -f -

USE_PULL_SECRET=false
if [[ -n "$DOCKERHUB_USERNAME" && -n "$DOCKERHUB_TOKEN" ]]; then
  echo "    Cap nhat Registry pull secret '${IMAGE_PULL_SECRET_NAME}' (${DOCKERHUB_SERVER})..."
  kubectl -n "$NAMESPACE" create secret docker-registry "$IMAGE_PULL_SECRET_NAME" \
    --docker-server="$DOCKERHUB_SERVER" \
    --docker-username="$DOCKERHUB_USERNAME" \
    --docker-password="$DOCKERHUB_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  USE_PULL_SECRET=true
elif kubectl -n "$NAMESPACE" get secret "$IMAGE_PULL_SECRET_NAME" >/dev/null 2>&1; then
  echo "    Phat hien pull secret '${IMAGE_PULL_SECRET_NAME}' da co san trong cluster -> tu dong gan vao cac Deployment."
  USE_PULL_SECRET=true
fi

echo "==> [3/5] Cap nhat ConfigMap 'backhaulbid-config' (External DB + K8s Service DNS)..."
CONFIG_YAML="$(kubectl -n "$NAMESPACE" create configmap backhaulbid-config \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_IDENTITY_URL="$POSTGRES_IDENTITY_URL" \
  --from-literal=POSTGRES_FLEET_URL="$POSTGRES_FLEET_URL" \
  --from-literal=POSTGRES_WALLET_URL="$POSTGRES_WALLET_URL" \
  --from-literal=POSTGRES_CONTRACT_URL="$POSTGRES_CONTRACT_URL" \
  --from-literal=DB_POOL_MAX_SIZE="$DB_POOL_MAX_SIZE" \
  --from-literal=DB_POOL_LIGHT_MAX_SIZE="$DB_POOL_LIGHT_MAX_SIZE" \
  --from-literal=DB_POOL_MIN_IDLE="$DB_POOL_MIN_IDLE" \
  --from-literal=REDIS_HOST="$REDIS_HOST" \
  --from-literal=REDIS_PORT="$REDIS_PORT" \
  --from-literal=REDIS_USERNAME="$REDIS_USERNAME" \
  --from-literal=REDIS_SSL_ENABLED="$REDIS_SSL_ENABLED" \
  --from-literal=RABBITMQ_USER="$RABBITMQ_USER" \
  --from-literal=RABBITMQ_HOST="$RABBITMQ_HOST" \
  --from-literal=RABBITMQ_PORT="$RABBITMQ_PORT" \
  --from-literal=RABBITMQ_VHOST="$RABBITMQ_VHOST" \
  --from-literal=RABBITMQ_SSL_ENABLED="$RABBITMQ_SSL_ENABLED" \
  --from-literal=EUREKA_ENABLED="false" \
  --from-literal=IDENTITY_GATEWAY_URI="http://identity-service:8080" \
  --from-literal=FLEET_GATEWAY_URI="http://fleet-service:8080" \
  --from-literal=WALLET_GATEWAY_URI="http://wallet-service:8080" \
  --from-literal=CONTRACT_GATEWAY_URI="http://contract-service:8080" \
  --from-literal=MEDIA_GATEWAY_URI="http://media-service:8080" \
  --from-literal=BIDDING_GATEWAY_URI="http://bidding-service:3001" \
  --from-literal=NOTIFICATION_GATEWAY_URI="http://notification-service:3002" \
  --from-literal=WEB_PORTAL_URI="http://web-portal:3000" \
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
  --dry-run=client -o yaml)"
printf '%s\n' "$CONFIG_YAML" | kubectl apply -f -

if command -v sha256sum >/dev/null 2>&1; then
  CONFIG_CHECKSUM="$(printf '%s\n%s' "$SECRETS_YAML" "$CONFIG_YAML" | sha256sum | cut -c1-16)"
elif command -v shasum >/dev/null 2>&1; then
  CONFIG_CHECKSUM="$(printf '%s\n%s' "$SECRETS_YAML" "$CONFIG_YAML" | shasum -a 256 | cut -c1-16)"
else
  CONFIG_CHECKSUM="$(printf '%s\n%s' "$SECRETS_YAML" "$CONFIG_YAML" | cksum | awk '{print $1}')"
fi

# Don eureka-server cu neu cluster tung deploy theo mo hinh cu
kubectl -n "$NAMESPACE" delete deploy/eureka-server svc/eureka-server --ignore-not-found >/dev/null 2>&1 || true

# Nhac neu con StatefulSet DB cu trong cluster (khong tu xoa de bao ve du lieu)
if kubectl -n "$NAMESPACE" get statefulset postgres mongodb redis rabbitmq >/dev/null 2>&1; then
  echo "INFO: Phat hien StatefulSet DB cu trong namespace '$NAMESPACE'. Khi da chuyen du lieu sang DB ngoai, co the xoa thu cong de giai phong RAM." >&2
fi

# Tao Kustomize overlay tam thoi trong /tmp de override registry/prefix/tag/pullPolicy/secrets
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp -r "$K3S_DIR/base" "$TMP_DIR/base"
cp -r "$K3S_DIR/overlays" "$TMP_DIR/overlays"

OVERLAY_MODE="http"
if [[ -f "$TMP_DIR/overlays/tls/kustomization.yaml" && -f "$TMP_DIR/overlays/tls/ingress-tls.yaml" ]]; then
  OVERLAY_MODE="tls"
  echo "    Phat hien k3s/overlays/tls -> su dung overlay HTTPS TLS..."
fi

cat > "$TMP_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - overlays/${OVERLAY_MODE}
images:
EOF

for svc in "${ALL_SERVICES[@]}"; do
  svc_name="${IMAGE_REGISTRY}/${IMAGE_PREFIX}${svc}"
  svc_tag="${IMAGE_TAG}"
  if [[ "$PARTIAL_DEPLOY" == "true" && ",${TARGET_SERVICES_CSV}," != *",${svc},"* ]]; then
    cur_img="$(kubectl -n "$NAMESPACE" get deploy "$svc" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    if [[ -z "$cur_img" ]]; then
      echo "ERROR: Khong tim thay Deployment '$svc' trong namespace '$NAMESPACE' khi deploy mot phan (--services ${TARGET_SERVICES_CSV}). Lan deploy dau tien hay dung '--services all'." >&2
      exit 1
    fi
    if [[ "$cur_img" == *:* && "${cur_img##*:}" != */* ]]; then
      svc_name="${cur_img%:*}"
      svc_tag="${cur_img##*:}"
    else
      svc_name="$cur_img"
      svc_tag=""
    fi
  fi
  cat >> "$TMP_DIR/kustomization.yaml" <<EOF
  - name: backhaulbid/${svc}
    newName: ${svc_name}
EOF
  if [[ -n "$svc_tag" ]]; then
    cat >> "$TMP_DIR/kustomization.yaml" <<EOF
    newTag: "${svc_tag}"
EOF
  fi
done

HAS_PATCHES=false
append_patches_header() {
  if [[ "$HAS_PATCHES" == "false" ]]; then
    echo "patches:" >> "$TMP_DIR/kustomization.yaml"
    HAS_PATCHES=true
  fi
}

append_patches_header
cat >> "$TMP_DIR/kustomization.yaml" <<EOF
  - target:
      kind: Deployment
    patch: |-
      - op: add
        path: /spec/template/metadata/annotations
        value:
          backhaulbid.vn/config-checksum: "${CONFIG_CHECKSUM}"
EOF

if [[ "$IMAGE_PULL_POLICY" != "IfNotPresent" ]]; then
  append_patches_header
  cat >> "$TMP_DIR/kustomization.yaml" <<EOF
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/imagePullPolicy
        value: ${IMAGE_PULL_POLICY}
EOF
fi

if [[ "$APP_REPLICAS" != "2" ]]; then
  append_patches_header
  cat >> "$TMP_DIR/kustomization.yaml" <<EOF
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/replicas
        value: ${APP_REPLICAS}
EOF
fi

if [[ "$USE_PULL_SECRET" == "true" ]]; then
  append_patches_header
  cat >> "$TMP_DIR/kustomization.yaml" <<EOF
  - target:
      kind: Deployment
    patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value:
          - name: ${IMAGE_PULL_SECRET_NAME}
EOF
fi

if [[ "$OVERLAY_MODE" == "http" && -n "$INGRESS_HOST" ]]; then
  append_patches_header
  cat >> "$TMP_DIR/kustomization.yaml" <<EOF
  - target:
      kind: Ingress
      name: backhaulbid-ingress
    patch: |-
      - op: add
        path: /spec/rules/0/host
        value: "${INGRESS_HOST}"
EOF
fi

echo "==> [4/5] Trien khai Kustomize overlay '${OVERLAY_MODE}' (${IMAGE_REGISTRY}/${IMAGE_PREFIX}*:${IMAGE_TAG}, pullPolicy=${IMAGE_PULL_POLICY})..."
kubectl apply -k "$TMP_DIR"

echo "==> [5/5] Dang cho 9 stateless Deployment san sang (co the mat 1-3 phut)..."
for deploy in identity-service fleet-service wallet-service contract-service media-service bidding-service notification-service web-portal api-gateway; do
  kubectl -n "$NAMESPACE" rollout status "deploy/${deploy}" --timeout=300s
done

echo ""
echo "=============================================================================="
echo "TRIEN KHAI BACKHAULBID LEN K3S THANH CONG!"
echo "  Dia chi truy cap: ${PUBLIC_BASE_URL}"
echo "  Image tag       : ${IMAGE_REGISTRY}/${IMAGE_PREFIX}*:${IMAGE_TAG}"
echo "  Replicas        : ${APP_REPLICAS} (DB pool lock=${DB_POOL_MAX_SIZE}/pod, light=${DB_POOL_LIGHT_MAX_SIZE}/pod, min-idle=${DB_POOL_MIN_IDLE}/pod)"
echo "  Postgres host   : ${POSTGRES_HOST:-custom-urls} (ssl=${POSTGRES_SSLMODE})"
echo "  Valkey/Redis    : ${REDIS_HOST}:${REDIS_PORT} (tls=${REDIS_SSL_ENABLED})"
echo "  RabbitMQ        : ${RABBITMQ_HOST}:${RABBITMQ_PORT}/${RABBITMQ_VHOST} (tls=${RABBITMQ_SSL_ENABLED})"
echo "  Kiem tra Pods   : kubectl -n ${NAMESPACE} get pods -o wide"
echo "  Kiem tra Ingress: kubectl -n ${NAMESPACE} get ingress"
echo "=============================================================================="
kubectl -n "$NAMESPACE" get pods
