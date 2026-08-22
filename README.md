# Pterodactyl All-in-One Installer

A GitHub-ready installer for a fresh Pterodactyl server.

## Supported OS

- Ubuntu 22.04
- Ubuntu 24.04
- Debian 12

## Installs

- Pterodactyl Panel
- Pterodactyl Wings
- Docker
- Nginx
- MariaDB
- Redis
- PHP 8.3
- Composer
- Certbot / Let's Encrypt
- Queue Worker
- Scheduler

## Install

Clone the repository:

```bash
git clone https://github.com/MGFEARLESSYT/pterodactyl-installer.git
cd pterodactyl-installer
chmod +x install.sh
sudo ./install.sh
```

Or:

```bash
curl -fsSL https://raw.githubusercontent.com/MGFEARLESSYT/pterodactyl-installer/main/install.sh | sudo bash
```

## DNS

Before SSL, point:

```text
panel.example.com -> SERVER_IP
node.example.com  -> SERVER_IP
```

For Cloudflare, use **DNS Only** while obtaining the first Let's Encrypt certificate.

## After installation

The Panel and Wings packages are installed automatically.

A Pterodactyl Node still needs to be created from the Panel because allocations and node configuration are environment-specific.

Go to:

**Admin → Locations → Nodes → Create New**

Set the node FQDN to your node domain.

Then copy the generated configuration into:

```bash
/etc/pterodactyl/config.yml
```

Start Wings:

```bash
systemctl enable --now wings
```

## Useful commands

```bash
systemctl status wings
systemctl status nginx
systemctl status mariadb
systemctl status redis-server
systemctl status docker
systemctl status pterodactyl-worker
```

Wings logs:

```bash
journalctl -u wings -f
```

Panel logs:

```bash
tail -f /var/www/pterodactyl/storage/logs/*.log
```

## Warning

Use this on a clean server and review the script before production deployment. Do not expose MariaDB or Redis directly to the public internet.
