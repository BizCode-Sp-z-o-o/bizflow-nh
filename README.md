# BizFlow NH

KSeF integration platform for SAP Business One — automatic invoice submission to Poland's National e-Invoice System.

> [!IMPORTANT]
> **This is an installer only, not open-source software.**
> The container images are proprietary and require a commercial license from BizCode.
> This repository contains only the deployment scripts (Docker Compose, installer, control script).
>
> **Interested?** Contact us at **info@bizcode.pl** to discuss licensing and pricing.
>
> [www.bizcode.pl](https://www.bizcode.pl)

## Quick Start

```bash
git clone https://github.com/BizCode-Sp-z-o-o/bizflow-nh.git
cd bizflow-nh
chmod +x install.sh ctl.sh
./install.sh
```

The installer will guide you through configuration and start all services.
You will need ACR credentials provided by BizCode with your license.

## Architecture

| Service | Description | Port |
|---------|-------------|------|
| API (.NET 9) | Backend — KSeF submission, SAP integration, mapping engine | 5001 |
| Dashboard (React) | Web UI — invoice management, profiles, monitoring | 4322 |
| PDF Sidecar (Node.js) | Invoice & UPO PDF generation | internal |
| PostgreSQL 16 | Application database | internal |
| Redis 7 | Cache | internal |
| RabbitMQ 4 | Message queue | 15672 (mgmt) |
| OpenBao | Secrets & certificate management | internal |
| Watchtower | Auto-update from ACR | — |
| DB Backup | Automatic PostgreSQL backups (every 6h) | — |

## Management

```bash
./ctl.sh start    # Start all services
./ctl.sh stop     # Stop all services
./ctl.sh status   # Show status
./ctl.sh logs     # View logs (or: ./ctl.sh logs api)
./ctl.sh update   # Pull latest images and restart
./ctl.sh backup   # Backup database
./ctl.sh restore backups/.../bizflownh.sql.gz  # Restore from backup
```

## Requirements

- Docker Engine 24+
- Docker Compose v2
- ACR credentials (provided by BizCode)
- Network access to SAP Business One Service Layer

## After Installation

1. Open Dashboard at `http://localhost:4322`
2. Login with `admin@bizflownh.dev` / `Admin123!`
3. **Change the default password**
4. Add SAP company (Settings → Companies)
5. Run SAP Installer (Service Panel → SAP Setup)
6. Configure mapping profiles
7. Enable automatic sending (AutoSendToKSeF)

## License

Proprietary — BizCode Sp. z o.o. All rights reserved.

This software is not open-source. Unauthorized use, copying, or distribution is prohibited.
Contact **info@bizcode.pl** for licensing.
