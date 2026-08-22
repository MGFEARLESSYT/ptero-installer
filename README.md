# MG Ptero Installer v2

A GitHub-ready interactive Bash deployment and management panel for Pterodactyl.

## Supported OS

- Ubuntu 22.04
- Ubuntu 24.04
- Debian 12

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/MGFEARLESSYT/ptero-installer/main/install.sh | bash
```

## Menu

### Installation
- Install Panel
- Install Wings
- Install Panel + Wings

### Management
- Update Panel
- Update Wings
- Backup Panel + Database
- Repair Panel
- SSL Manager
- Service Status
- View Logs
- Uninstall / Remove

## Components

- Pterodactyl Panel
- Pterodactyl Wings
- Docker
- MariaDB
- Redis
- Nginx
- PHP 8.3
- Composer
- Let's Encrypt / Certbot
- Queue Worker
- Scheduler

## Backup

Backups are stored under:

```text
/var/backups/mg-ptero/
```

Installer log:

```text
/var/log/mg-ptero-installer.log
```

## DNS

Before requesting SSL:

```text
panel.example.com -> SERVER_IP
node.example.com  -> SERVER_IP
```

For Cloudflare, DNS must resolve correctly to the server. Do not proxy Wings through Cloudflare unless your specific Wings networking setup supports it.

## Important

The installer is intended for a clean server. Always keep an independent backup before performing major upgrades or uninstall operations.

After creating a Node in Pterodactyl, put its generated Wings configuration at:

```text
/etc/pterodactyl/config.yml
```

Then:

```bash
systemctl restart wings
```


The installer keeps menu input attached to `/dev/tty`, so the interactive menu works when launched with `curl | bash`.
