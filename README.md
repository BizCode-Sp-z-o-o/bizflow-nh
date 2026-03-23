# BizFlow NH

KSeF integration platform for SAP Business One — automatic invoice submission to Poland's National e-Invoice System.

> [!IMPORTANT]
> **This is an installer only, not open-source software.**
> The container images are proprietary and require a commercial license from BizCode.
> This repository contains only the deployment scripts.
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
On Ubuntu/Debian, Docker will be installed automatically if not present.
You will need ACR credentials provided by BizCode with your license.

## Requirements

- **Linux** (Ubuntu 22.04+ or Debian 12+ recommended) — the installer will auto-install Docker if missing
- Docker Engine 24+ and Docker Compose v2 (installed automatically on Ubuntu/Debian)
- ACR credentials (provided by BizCode)
- Network access to SAP Business One Service Layer

## Management

```bash
./ctl.sh start    # Start all services
./ctl.sh stop     # Stop all services
./ctl.sh status   # Show status
./ctl.sh logs     # View logs
./ctl.sh update   # Pull latest images and restart
./ctl.sh backup   # Backup database
./ctl.sh restore  # Restore from backup
```

## License

Proprietary — BizCode Sp. z o.o. All rights reserved.

This software is not open-source. Unauthorized use, copying, or distribution is prohibited.
Contact **info@bizcode.pl** for licensing.
