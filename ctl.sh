#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BizFlow NH — Control Script
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect mode
COMPOSE_CMD="docker compose -f docker-compose.yml"
if grep -q 'ENABLE_MONITORING=true' .env 2>/dev/null; then
    COMPOSE_CMD="$COMPOSE_CMD -f monitoring/docker-compose.monitoring.yml"
fi
if [ "$(cat .mode 2>/dev/null)" = "prod" ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.prod.yml"
fi

# Auto-unseal OpenBao after start
unseal_openbao() {
    local UNSEAL_KEY
    UNSEAL_KEY=$(grep '^OPENBAO_UNSEAL_KEY=' .env 2>/dev/null | cut -d= -f2 || true)
    if [ -z "$UNSEAL_KEY" ]; then
        return
    fi

    local BAO_CONTAINER
    BAO_CONTAINER=$($COMPOSE_CMD ps --format '{{.Name}}' 2>/dev/null | grep openbao || true)
    if [ -z "$BAO_CONTAINER" ]; then
        return
    fi

    # Wait for container to be ready
    for i in $(seq 1 10); do
        if docker exec "$BAO_CONTAINER" bao status -address=http://127.0.0.1:8200 >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    local BAO_SEALED
    BAO_SEALED=$(docker exec "$BAO_CONTAINER" bao status -address=http://127.0.0.1:8200 -format=json 2>/dev/null | grep -o '"sealed":[a-z]*' | cut -d: -f2 || echo "unknown")

    if [ "$BAO_SEALED" = "true" ]; then
        docker exec "$BAO_CONTAINER" bao operator unseal -address=http://127.0.0.1:8200 "$UNSEAL_KEY" >/dev/null 2>&1
        echo "OpenBao unsealed."
    fi
}

case "${1:-help}" in
    start)
        echo "Starting BizFlow NH..."
        $COMPOSE_CMD up -d
        unseal_openbao
        ;;
    stop)
        echo "Stopping BizFlow NH..."
        $COMPOSE_CMD down
        ;;
    restart)
        echo "Restarting BizFlow NH..."
        $COMPOSE_CMD down
        $COMPOSE_CMD up -d
        unseal_openbao
        ;;
    status)
        $COMPOSE_CMD ps
        ;;
    logs)
        shift
        $COMPOSE_CMD logs -f "${@:---tail=100}"
        ;;
    update)
        echo "Pulling latest images..."
        source .env
        echo "$ACR_PASSWORD" | docker login bizcode.azurecr.io -u "$ACR_USERNAME" --password-stdin >/dev/null 2>&1
        $COMPOSE_CMD pull
        echo "Recreating containers..."
        $COMPOSE_CMD up -d --remove-orphans
        unseal_openbao
        echo "Update complete."
        ;;
    backup)
        BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        echo "Backing up database..."
        $COMPOSE_CMD exec -T db pg_dump -U bizflownh bizflownh | gzip > "$BACKUP_DIR/bizflownh.sql.gz"
        echo "Backup saved: $BACKUP_DIR/bizflownh.sql.gz"
        ;;
    restore)
        if [ -z "${2:-}" ]; then
            echo "Usage: ./ctl.sh restore <backup-file.sql.gz>"
            exit 1
        fi
        echo "Restoring database from $2..."
        gunzip -c "$2" | $COMPOSE_CMD exec -T db psql -U bizflownh -d bizflownh
        echo "Restore complete."
        ;;
    help|*)
        echo "BizFlow NH — Control Script"
        echo ""
        echo "Usage: ./ctl.sh <command>"
        echo ""
        echo "Commands:"
        echo "  start    Start all services"
        echo "  stop     Stop all services"
        echo "  restart  Restart all services"
        echo "  status   Show service status"
        echo "  logs     Show logs (optionally: ./ctl.sh logs api)"
        echo "  update   Pull latest images and recreate containers"
        echo "  backup   Backup PostgreSQL database"
        echo "  restore  Restore from backup (./ctl.sh restore backups/.../bizflownh.sql.gz)"
        ;;
esac
