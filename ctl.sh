#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BizFlow NH — Control Script
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

case "${1:-help}" in
    start)
        echo "Starting BizFlow NH..."
        docker compose up -d
        ;;
    stop)
        echo "Stopping BizFlow NH..."
        docker compose down
        ;;
    restart)
        echo "Restarting BizFlow NH..."
        docker compose down
        docker compose up -d
        ;;
    status)
        docker compose ps
        ;;
    logs)
        shift
        docker compose logs -f "${@:---tail=100}"
        ;;
    update)
        echo "Pulling latest images..."
        source .env
        echo "$ACR_PASSWORD" | docker login bizcode.azurecr.io -u "$ACR_USERNAME" --password-stdin >/dev/null 2>&1
        docker compose pull
        echo "Recreating containers..."
        docker compose up -d --remove-orphans
        echo "Update complete."
        ;;
    backup)
        BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        echo "Backing up database..."
        docker compose exec -T db pg_dump -U bizflownh bizflownh | gzip > "$BACKUP_DIR/bizflownh.sql.gz"
        echo "Backup saved: $BACKUP_DIR/bizflownh.sql.gz"
        ;;
    restore)
        if [ -z "${2:-}" ]; then
            echo "Usage: ./ctl.sh restore <backup-file.sql.gz>"
            exit 1
        fi
        echo "Restoring database from $2..."
        gunzip -c "$2" | docker compose exec -T db psql -U bizflownh -d bizflownh
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
