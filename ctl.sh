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

case "${1:-help}" in
    start)
        echo "Starting BizFlow NH..."
        $COMPOSE_CMD up -d
        ;;
    stop)
        echo "Stopping BizFlow NH..."
        $COMPOSE_CMD down
        ;;
    restart)
        echo "Restarting BizFlow NH..."
        $COMPOSE_CMD down
        $COMPOSE_CMD up -d
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
