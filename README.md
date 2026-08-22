# MG Ptero Installer

All-in-one Pterodactyl Panel and Wings installer and management script.

## Supported Systems

* Ubuntu 22.04
* Ubuntu 24.04
* Debian 12

## Requirements

* Root access
* Fresh Linux server recommended
* Internet connection
* `curl`
* Supported operating system

## Installer

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/MGFEARLESSYT/ptero-installer/main/install.sh -o /tmp/mg-ptero-installer.sh && chmod +x /tmp/mg-ptero-installer.sh && bash /tmp/mg-ptero-installer.sh
```

## Features

```text
1) Install Panel
2) Install Wings
3) Install Panel + Wings

4) Update Panel
5) Update Wings
6) Backup Panel + Database
7) Repair Panel
8) SSL Manager
9) Service Status
10) View Logs
11) Uninstall / Remove
12) Exit
```

## Useful Commands

Check Panel:

```bash
systemctl status nginx
```

Check Wings:

```bash
systemctl status wings
```

Restart Wings:

```bash
systemctl restart wings
```

Check Panel Worker:

```bash
systemctl status pterodactyl-worker
```

Restart Panel Worker:

```bash
systemctl restart pterodactyl-worker
```

Check Docker:

```bash
systemctl status docker
```

Check MariaDB:

```bash
systemctl status mariadb
```

Check Redis:

```bash
systemctl status redis-server
```

Check Nginx:

```bash
nginx -t
systemctl status nginx
```

## Logs

Installer:

```bash
cat /var/log/mg-ptero-installer.log
```

Wings:

```bash
journalctl -u wings -n 100 --no-pager
```

Panel Worker:

```bash
journalctl -u pterodactyl-worker -n 100 --no-pager
```

## Pterodactyl Paths

Panel:

```text
/var/www/pterodactyl
```

Wings:

```text
/usr/local/bin/wings
```

Wings configuration:

```text
/etc/pterodactyl/config.yml
```

## Repository

[https://github.com/MGFEARLESSYT/ptero-installer](https://github.com/MGFEARLESSYT/ptero-installer)
