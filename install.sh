#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BizFlow NH — Interactive Installer
# ============================================================

BOLD="\033[1m"
BLUE="\033[0;34m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
GRAY="\033[0;90m"
NC="\033[0m"

VERBOSE=false
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=true

header() { echo -e "\n${BLUE}${BOLD}$1${NC}"; }
info()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
debug()  { $VERBOSE && echo -e "${GRAY}     $1${NC}" || true; }

ask() {
    local var=$1 prompt=$2 default=$3
    if [ -n "$default" ]; then
        read -rp "$(echo -e "${BOLD}$prompt${NC} [$default]: ")" input
        eval "$var=\"${input:-$default}\""
    else
        while true; do
            read -rp "$(echo -e "${BOLD}$prompt${NC}: ")" input
            [ -n "$input" ] && break
            echo -e "${RED}  This field is required.${NC}"
        done
        eval "$var=\"$input\""
    fi
}

ask_password() {
    local var=$1 prompt=$2 default=$3
    read -rsp "$(echo -e "${BOLD}$prompt${NC} [$default]: ")" input
    echo
    eval "$var=\"${input:-$default}\""
}

# ── Banner ──
echo -e "${BLUE}${BOLD}"
cat << 'BANNER'

  ____  _     _____ _               _   _ _   _
 | __ )(_)___|  ___| | _____      _| \ | | | | |
 |  _ \| |_  / |_  | |/ _ \ \ /\ / /  \| | |_| |
 | |_) | |/ /|  _| | | (_) \ V  V /| |\  |  _  |
 |____/|_/___|_|   |_|\___/ \_/\_/ |_| \_|_| |_|

  KSeF Integration Platform Installer

BANNER
echo -e "${NC}"

# ── Install Docker if missing ──
install_docker() {
    header "Installing Docker..."

    # Detect distro
    if [ ! -f /etc/os-release ]; then
        error "Cannot detect OS. Only Ubuntu and Debian are supported."
    fi
    . /etc/os-release
    case "$ID" in
        ubuntu|debian) ;;
        *) error "Unsupported distro: $ID. Only Ubuntu and Debian are supported." ;;
    esac
    info "Detected: $PRETTY_NAME"

    # Check root/sudo
    if [ "$(id -u)" -ne 0 ]; then
        SUDO="sudo"
        command -v sudo >/dev/null 2>&1 || error "sudo is required to install Docker. Run as root or install sudo."
    else
        SUDO=""
    fi

    # Install prerequisites
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq ca-certificates curl gnupg >/dev/null

    # Add Docker GPG key
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} \
      ${VERSION_CODENAME} stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
    info "Docker installed"

    # Post-install: enable and start
    $SUDO systemctl enable docker.service >/dev/null 2>&1
    $SUDO systemctl enable containerd.service >/dev/null 2>&1
    $SUDO systemctl start docker.service
    info "Docker service enabled and started"

    # Post-install: non-root user
    if [ -n "${SUDO_USER:-}" ]; then
        DOCKER_USER="$SUDO_USER"
    elif [ "$(id -u)" -ne 0 ]; then
        DOCKER_USER="$(whoami)"
    else
        DOCKER_USER=""
    fi
    if [ -n "$DOCKER_USER" ]; then
        $SUDO groupadd -f docker
        $SUDO usermod -aG docker "$DOCKER_USER"
        info "User '$DOCKER_USER' added to docker group (re-login required for non-sudo usage)"
    fi

    # Post-install: log rotation
    if [ ! -f /etc/docker/daemon.json ]; then
        $SUDO mkdir -p /etc/docker
        $SUDO tee /etc/docker/daemon.json > /dev/null << 'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON
        $SUDO systemctl restart docker.service
        info "Log rotation configured (json-file, 10m x 3)"
    else
        warn "/etc/docker/daemon.json already exists — skipping log config"
    fi
}

# ── Prerequisites ──
header "Checking prerequisites..."
if ! command -v docker >/dev/null 2>&1; then
    warn "Docker is not installed."
    ask INSTALL_DOCKER "Install Docker automatically? (y/n)" "y"
    case "$INSTALL_DOCKER" in
        y|Y|yes) install_docker ;;
        *) error "Docker is required. Install manually: https://docs.docker.com/engine/install/" ;;
    esac
fi
docker compose version >/dev/null 2>&1 || error "Docker Compose v2 is not available. Reinstall Docker with compose plugin."

DOCKER_VERSION=$(docker --version | sed -n 's/.*version \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')
info "Docker ${DOCKER_VERSION:-unknown}"
info "Docker Compose $(docker compose version --short 2>/dev/null)"

# ── Deployment mode ──
header "Deployment mode"
echo "  1) dev  — direct port access, no SSL, for development/testing"
echo "  2) prod — Nginx Proxy Manager with SSL, domain-based routing"
echo ""
ask MODE "Choose mode (1=dev, 2=prod)" "1"
case "$MODE" in
    1|dev)  MODE="dev" ;;
    2|prod) MODE="prod" ;;
    *) error "Invalid mode" ;;
esac
info "Mode: $MODE"

# ── Monitoring ──
header "Monitoring stack (Grafana + Prometheus + Tempo + Dozzle)"
ask ENABLE_MONITORING "Enable monitoring? (y/n)" "y"
case "$ENABLE_MONITORING" in
    y|Y|yes) ENABLE_MONITORING="true" ;;
    *) ENABLE_MONITORING="false" ;;
esac
info "Monitoring: $ENABLE_MONITORING"

# ── ACR Credentials ──
header "Azure Container Registry credentials"
echo "  These are provided by BizCode with your license."
ask ACR_USERNAME "ACR Username" ""
ask_password ACR_PASSWORD "ACR Password" ""

echo ""
echo -e "  Logging in to ACR..."
echo "$ACR_PASSWORD" | docker login bizcode.azurecr.io -u "$ACR_USERNAME" --password-stdin >/dev/null 2>&1 \
    || error "ACR login failed. Please check your credentials."
info "ACR login successful"

# ── URLs ──
header "Application URLs"
if [ "$MODE" = "prod" ]; then
    ask DASHBOARD_DOMAIN "Dashboard domain (e.g. bizflow.klient.pl)" ""
    ask API_DOMAIN "API domain" "api.${DASHBOARD_DOMAIN}"
    ask LETSENCRYPT_EMAIL "Email for Let's Encrypt" ""
    DASHBOARD_URL="https://${DASHBOARD_DOMAIN}"
    API_URL="https://${API_DOMAIN}"
    info "Dashboard: $DASHBOARD_URL"
    info "API:       $API_URL"
else
    DASHBOARD_DOMAIN=""
    API_DOMAIN=""
    LETSENCRYPT_EMAIL=""
    DASHBOARD_URL="http://localhost:4322"
    API_URL="http://localhost:5001"
fi

# ── Generate secrets ──
header "Generating secrets..."
POSTGRES_PASSWORD="bizflownh-pg-$(openssl rand -hex 8)"
RABBITMQ_PASSWORD="bizflownh-rmq-$(openssl rand -hex 8)"
REDIS_PASSWORD="bizflownh-redis-$(openssl rand -hex 8)"
JWT_KEY="$(openssl rand -base64 48)"
OPENBAO_TOKEN="bao-$(openssl rand -hex 16)"
MINIO_ACCESS_KEY="bizflownh-$(openssl rand -hex 6)"
MINIO_SECRET_KEY="$(openssl rand -base64 32)"
GRAFANA_PASSWORD="bizflownh-gf-$(openssl rand -hex 8)"
DOZZLE_PASSWORD="bizflownh-dz-$(openssl rand -hex 8)"

info "PostgreSQL password generated"
info "RabbitMQ password generated"
info "Redis password generated"
info "JWT key generated"
info "OpenBao token generated"
info "MinIO credentials generated"
info "Grafana password generated"
info "Dozzle password generated"

# ── Generate .env ──
header "Generating configuration..."

cat > .env << ENVFILE
# Generated by install.sh on $(date -Iseconds)
# BizFlow NH — KSeF Integration Platform

# ── ACR ──
ACR_USERNAME=${ACR_USERNAME}
ACR_PASSWORD=${ACR_PASSWORD}

# ── PostgreSQL ──
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# ── RabbitMQ ──
RABBITMQ_USER=bizflownh
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}

# ── Redis ──
REDIS_PASSWORD=${REDIS_PASSWORD}

# ── JWT ──
JWT_KEY=${JWT_KEY}

# ── KSeF (default: test — change in dashboard per SAP company) ──
KSEF_BASE_URL=https://ksef-test.mf.gov.pl

# ── OpenBao ──
OPENBAO_TOKEN=${OPENBAO_TOKEN}

# ── MinIO (Object Storage) ──
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY}

# ── Mode ──
MODE=${MODE}
DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN}
API_DOMAIN=${API_DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}

# ── URLs ──
DASHBOARD_URL=${DASHBOARD_URL}
API_URL=${API_URL}

# ── Ports (dev mode only — prod uses NPM) ──
API_PORT=5001
DASHBOARD_PORT=4322

# ── Auto-update (seconds, 0=disabled) ──
WATCHTOWER_INTERVAL=300

# ── Monitoring ──
ENABLE_MONITORING=${ENABLE_MONITORING}
GRAFANA_PORT=3001
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
DOZZLE_PORT=3002
DOZZLE_PASSWORD=${DOZZLE_PASSWORD}
ENVFILE

chmod 600 .env
chmod 600 "${HOME}/.docker/config.json" 2>/dev/null || true
info ".env generated (permissions: owner-only)"

# ── Generate Dozzle users file with random password ──
if [ "$ENABLE_MONITORING" = "true" ]; then
    DOZZLE_HASH=$(docker run --rm httpd:2-alpine htpasswd -nbBC 11 "" "$DOZZLE_PASSWORD" 2>/dev/null | cut -d: -f2 || true)
    if [ -n "$DOZZLE_HASH" ]; then
        cat > monitoring/dozzle-users.yml << EOF
users:
  admin:
    name: "Admin"
    password: "${DOZZLE_HASH}"
EOF
        info "Dozzle users file generated"
    else
        warn "Could not generate Dozzle bcrypt hash — using default password 'admin'"
    fi
fi

# ── Compose command ──
COMPOSE_CMD="docker compose"
if [ "$ENABLE_MONITORING" = "true" ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml"
else
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.yml"
fi
if [ "$MODE" = "prod" ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.prod.yml"
fi

# Save for ctl.sh
echo "$MODE" > .mode

# ── Pull images ──
header "Pulling images..."
$COMPOSE_CMD pull 2>&1 | tail -5
info "Images pulled"

# ── Start ──
header "Starting BizFlow NH..."
$COMPOSE_CMD up -d 2>&1 || true

# ── Initialize OpenBao (must happen before retry so healthcheck passes) ──
header "Initializing OpenBao vault..."

# Wait for OpenBao container to accept connections
# Note: bao status returns exit code 2 when sealed (not 0), so we check output instead
BAO_CONTAINER=""
for i in $(seq 1 20); do
    BAO_CONTAINER=$($COMPOSE_CMD ps --format '{{.Name}}' 2>/dev/null | grep openbao || true)
    debug "loop ${i}: BAO_CONTAINER=${BAO_CONTAINER:-empty}"
    if [ -n "$BAO_CONTAINER" ]; then
        BAO_PROBE=$(docker exec "$BAO_CONTAINER" bao status -address=http://127.0.0.1:8200 -format=json < /dev/null 2>&1 || true)
        debug "bao status output (first 80 chars): ${BAO_PROBE:0:80}"
        if echo "$BAO_PROBE" | grep -q '"storage_type"'; then
            debug "storage_type found — OpenBao is listening"
            break
        fi
    fi
    echo -ne "\r  Waiting for OpenBao... ${i}/20 "
    sleep 3
done
echo ""
if [ -n "$BAO_CONTAINER" ]; then
    BAO_STATUS=$(docker exec "$BAO_CONTAINER" bao status -address=http://127.0.0.1:8200 -format=json < /dev/null 2>&1 || true)
    debug "BAO_STATUS (first 200 chars): ${BAO_STATUS:0:200}"
    BAO_INITIALIZED=$(echo "$BAO_STATUS" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('initialized','unknown')).lower())" 2>/dev/null || echo "unknown")
    debug "BAO_INITIALIZED=${BAO_INITIALIZED}"

    if [ "$BAO_INITIALIZED" = "false" ]; then
        debug "Running bao operator init..."
        INIT_OUTPUT=$(docker exec "$BAO_CONTAINER" bao operator init \
            -address=http://127.0.0.1:8200 \
            -key-shares=1 -key-threshold=1 -format=json < /dev/null 2>&1 || echo '')
        debug "INIT_OUTPUT (first 200 chars): ${INIT_OUTPUT:0:200}"

        if [ -n "$INIT_OUTPUT" ]; then
            UNSEAL_KEY=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][0])" 2>/dev/null || true)
            ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['root_token'])" 2>/dev/null || true)
            debug "UNSEAL_KEY=${UNSEAL_KEY:+present} ROOT_TOKEN=${ROOT_TOKEN:+present}"

            if [ -n "$UNSEAL_KEY" ] && [ -n "$ROOT_TOKEN" ]; then
                # Unseal
                docker exec "$BAO_CONTAINER" bao operator unseal -address=http://127.0.0.1:8200 "$UNSEAL_KEY" < /dev/null >/dev/null 2>&1

                # Enable KV secrets engine
                docker exec -e BAO_TOKEN="$ROOT_TOKEN" "$BAO_CONTAINER" \
                    bao secrets enable -address=http://127.0.0.1:8200 -path=kv -version=2 kv < /dev/null >/dev/null 2>&1 || true

                # Save to .env
                sed -i "s|^OPENBAO_TOKEN=.*|OPENBAO_TOKEN=${ROOT_TOKEN}|" .env
                echo "" >> .env
                echo "# ── OpenBao Unseal (KEEP SECRET) ──" >> .env
                echo "OPENBAO_UNSEAL_KEY=${UNSEAL_KEY}" >> .env

                # Update token in running API container
                OPENBAO_TOKEN="$ROOT_TOKEN"

                info "OpenBao initialized and unsealed"
                info "Root token and unseal key saved to .env"
            else
                warn "OpenBao init returned unexpected output — check manually"
            fi
        else
            warn "OpenBao init failed — check: docker logs $BAO_CONTAINER"
        fi
    elif [ "$BAO_INITIALIZED" = "true" ]; then
        # Already initialized — try to unseal if sealed
        BAO_SEALED=$(echo "$BAO_STATUS" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('sealed',True)).lower())" 2>/dev/null || echo "true")
        if [ "$BAO_SEALED" = "true" ]; then
            UNSEAL_KEY=$(grep '^OPENBAO_UNSEAL_KEY=' .env 2>/dev/null | cut -d= -f2 || true)
            if [ -n "$UNSEAL_KEY" ]; then
                docker exec "$BAO_CONTAINER" bao operator unseal -address=http://127.0.0.1:8200 "$UNSEAL_KEY" < /dev/null >/dev/null 2>&1
                info "OpenBao unsealed"
            else
                warn "OpenBao is sealed but no unseal key found in .env"
            fi
        else
            info "OpenBao already initialized and unsealed"
        fi
    else
        warn "Could not determine OpenBao state — check: docker logs $BAO_CONTAINER"
    fi
fi

# ── Retry — now that OpenBao is unsealed, API and dependents can start ──
header "Starting remaining services..."
$COMPOSE_CMD up -d 2>&1 || true

echo -e "\n  Waiting for all services..."
for i in $(seq 1 12); do
    UNHEALTHY=$($COMPOSE_CMD ps --format '{{.State}}' 2>/dev/null | grep -cv "running" || true)
    if [ "$UNHEALTHY" -eq 0 ]; then
        break
    fi
    echo -ne "\r  Waiting... ${i}/12 ($UNHEALTHY not ready) "
    sleep 5
done
echo ""

# ── Verify ──
header "Verifying services..."
sleep 3
FAILED=0
RUNNING=0
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    state=$(echo "$line" | awk '{print $2}')
    if [ "$state" = "running" ]; then
        info "$name"
        RUNNING=$((RUNNING + 1))
    else
        warn "$name — $state"
        FAILED=$((FAILED + 1))
    fi
done < <($COMPOSE_CMD ps --format '{{.Name}} {{.State}}' 2>/dev/null)

echo ""
if [ "$FAILED" -gt 0 ]; then
    warn "$RUNNING running, $FAILED failed. Check: ./ctl.sh logs <service>"
else
    info "All $RUNNING services running"
fi

# ── Wait for API to be ready ──
header "Waiting for API..."
API_HEALTH_URL="http://localhost:${API_PORT:-5001}/health"
if [ "$MODE" = "prod" ]; then
    # In prod, API port is not on host — resolve container IP via Docker network
    API_IP=$(docker inspect "$($COMPOSE_CMD ps -q api 2>/dev/null)" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || true)
    if [ -n "$API_IP" ]; then
        API_HEALTH_URL="http://${API_IP}:8080/health"
    fi
    debug "API health URL: $API_HEALTH_URL"
fi
for i in $(seq 1 30); do
    if curl -sf "$API_HEALTH_URL" >/dev/null 2>&1; then
        info "API is ready"
        break
    fi
    echo -ne "\r  Waiting for API... ${i}/30 "
    sleep 2
done
echo ""

# ── Summary ──
header "Installation complete!"
echo ""
echo -e "${BOLD}Application:${NC}"
if [ "$MODE" = "prod" ]; then
    echo -e "  Dashboard:  ${GREEN}${DASHBOARD_URL}${NC}"
    echo -e "  API:        ${GREEN}${API_URL}${NC}"
else
    echo -e "  Dashboard:  ${GREEN}http://localhost:${DASHBOARD_PORT:-4322}${NC}"
    echo -e "  API:        ${GREEN}http://localhost:${API_PORT:-5001}${NC}"
fi
echo ""
echo -e "${BOLD}Default login:${NC}"
echo -e "  Email:    ${GREEN}admin@bizflownh.dev${NC}"
echo -e "  Password: ${GREEN}Admin123!${NC}"
echo -e "  ${YELLOW}Change the password after first login!${NC}"

if [ "$MODE" = "prod" ]; then
    echo ""
    echo -e "${BOLD}Nginx Proxy Manager (admin panel):${NC}"
    NPM_SERVER_IP=$(curl -sf --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "server")
    SSH_USER=$(whoami)
    echo -e "  ${GREEN}ssh -L 8181:127.0.0.1:81 ${SSH_USER}@${NPM_SERVER_IP}${NC}"
    echo -e "  Then open ${GREEN}http://localhost:8181${NC} in your browser"
    echo -e "  First login: admin@example.com / changeme"
    echo ""
    echo -e "  ${YELLOW}Configure these proxy hosts:${NC}"
    echo -e "    ${BOLD}${DASHBOARD_DOMAIN}${NC}  →  dashboard:4322  (+ SSL)"
    echo -e "    ${BOLD}${API_DOMAIN}${NC}  →  api:8080  (+ SSL + Websockets)"
fi

if [ "$ENABLE_MONITORING" = "true" ]; then
    echo ""
    echo -e "${BOLD}Monitoring (localhost only):${NC}"
    echo -e "  Grafana:  admin / ${GREEN}${GRAFANA_PASSWORD}${NC}"
    echo -e "  Dozzle:   admin / ${GREEN}${DOZZLE_PASSWORD}${NC}"
    if [ "$MODE" = "prod" ]; then
        echo ""
        SERVER_IP=$(curl -sf --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "server")
        MON_SSH_USER=$(whoami)
        echo -e "  ${YELLOW}Access via SSH tunnel:${NC}"
        echo -e "  ${GREEN}ssh -L 3001:127.0.0.1:${GRAFANA_PORT:-3001} -L 3002:127.0.0.1:${DOZZLE_PORT:-3002} ${MON_SSH_USER}@${SERVER_IP}${NC}"
        echo -e "  Then: Grafana ${GREEN}http://localhost:3001${NC}  Dozzle ${GREEN}http://localhost:3002${NC}"
    else
        echo -e "  Grafana:  ${GREEN}http://localhost:${GRAFANA_PORT:-3001}${NC}"
        echo -e "  Dozzle:   ${GREEN}http://localhost:${DOZZLE_PORT:-3002}${NC}"
    fi
fi

echo ""
echo -e "${BOLD}Management:${NC}"
echo "  ./ctl.sh start    — Start all services"
echo "  ./ctl.sh stop     — Stop all services"
echo "  ./ctl.sh status   — Show status"
echo "  ./ctl.sh logs     — View logs"
echo "  ./ctl.sh update   — Pull latest images and restart"
echo "  ./ctl.sh backup   — Backup database"
echo ""
echo -e "${BOLD}Credentials saved in:${NC} .env"
echo -e "${YELLOW}Keep this file safe — it contains all passwords.${NC}"
echo ""
echo -e "${GREEN}${BOLD}BizFlow NH is ready!${NC}"
