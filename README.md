

````markdown
# 🚀 MG Ptero Installer

A powerful, interactive **Pterodactyl Panel & Wings installer and management tool** for Linux servers.

Built for easy deployment, updates, backups, repairs, SSL management, and service monitoring.

---

## ✨ Features

### 📦 Installation

- Install Pterodactyl Panel
- Install Pterodactyl Wings
- Install Panel + Wings
- Automatic dependency installation
- Docker installation
- MariaDB setup
- Redis setup
- PHP 8.3 setup
- Nginx configuration
- Composer setup
- Queue Worker
- Scheduler

### 🛠️ Management

- Update Pterodactyl Panel
- Update Wings
- Backup Panel files
- Backup Panel database
- Repair Panel
- Clear Laravel caches
- Restart required services
- SSL Manager
- Service Status
- View Panel/Wings logs

### 🔐 SSL

Automatic Let's Encrypt SSL configuration using Certbot.

The installer can configure:

```text
https://panel.example.com
````

Make sure your DNS record points to your server before requesting SSL.

---

## 💻 Supported Operating Systems

Currently supported:

* Ubuntu 22.04
* Ubuntu 24.04
* Debian 12

Other distributions are not officially supported.

---

## 📥 Installation

### Recommended Method

Download the installer first and then execute it:

```bash
curl -fsSL https://raw.githubusercontent.com/MGFEARLESSYT/ptero-installer/main/install.sh \
-o /tmp/mg-ptero-installer.sh && \
chmod +x /tmp/mg-ptero-installer.sh && \
bash /tmp/mg-ptero-installer.sh
```

### Why download first?

The installer uses an interactive terminal menu.

Downloading the script first ensures that terminal input works correctly.

---

## 🖥️ Installer Menu

After launching the installer you'll see:

```text
╔════════════════════════════════════════════════════════════╗
║                 MG PTERO INSTALLER                         ║
║              Pterodactyl Deployment Manager               ║
╚════════════════════════════════════════════════════════════╝

Installation
  1) Install Panel
  2) Install Wings
  3) Install Panel + Wings

Management
  4) Update Panel
  5) Update Wings
  6) Backup Panel + Database
  7) Repair Panel
  8) SSL Manager
  9) Service Status
 10) View Logs

11) Uninstall / Remove
12) Exit

Select [1-12]:
```

---

## 🌐 DNS Setup

Before installing SSL, create DNS records pointing to your server.

Example:

```text
panel.example.com → SERVER_IP
node.example.com  → SERVER_IP
```

For the Panel:

```text
panel.example.com
```

For Wings:

```text
node.example.com
```

Make sure the domains resolve correctly before using the SSL Manager.

---

## 🪽 Wings Setup

Install Wings using:

```text
2) Install Wings
```

or install everything:

```text
3) Install Panel + Wings
```

After creating your Node inside Pterodactyl:

1. Open your Pterodactyl Panel
2. Go to **Admin → Nodes**
3. Create your Node
4. Open the Node configuration
5. Copy the generated Wings configuration
6. Put it on the server at:

```text
/etc/pterodactyl/config.yml
```

Then restart Wings:

```bash
systemctl restart wings
```

Check Wings:

```bash
systemctl status wings
```

---

## 🔄 Updating

### Update Panel

From the installer:

```text
4) Update Panel
```

The installer creates a backup before updating.

### Update Wings

From the installer:

```text
5) Update Wings
```

---

## 💾 Backups

Use:

```text
6) Backup Panel + Database
```

Backups are stored in:

```text
/var/backups/mg-ptero/
```

The backup includes:

* Panel `.env`
* Panel storage
* MariaDB database

Always keep an additional backup outside the server.

---

## 🔧 Repair

If the Panel has problems, use:

```text
7) Repair Panel
```

The repair process can:

* Clear Laravel cache
* Rebuild configuration cache
* Rebuild route cache
* Rebuild view cache
* Fix Panel permissions
* Reload Nginx
* Restart Redis
* Restart the queue worker
* Restart Wings

---

## 🔒 SSL Manager

Use:

```text
8) SSL Manager
```

Enter your Panel domain.

The installer uses Certbot to request/renew Let's Encrypt certificates.

Required ports:

```text
80/tcp
443/tcp
```

---

## 📊 Service Status

Use:

```text
9) Service Status
```

The installer checks:

```text
Nginx
MariaDB
Redis
Docker
Pterodactyl Worker
Wings
```

---

## 📜 Logs

Use:

```text
10) View Logs
```

Installer log:

```text
/var/log/mg-ptero-installer.log
```

Wings logs:

```bash
journalctl -u wings -n 100 --no-pager
```

Panel worker logs:

```bash
journalctl -u pterodactyl-worker -n 100 --no-pager
```

Panel application logs:

```text
/var/www/pterodactyl/storage/logs/
```

---

## 🗑️ Uninstall

The installer includes:

```text
11) Uninstall / Remove
```

Removal requires an explicit confirmation phrase to prevent accidental deletion.

Always create a backup before uninstalling.

---

## ⚠️ Requirements

* Root access
* Fresh or properly prepared server
* Supported operating system
* Working internet connection
* DNS configured for SSL
* Ports `80` and `443` available for the Panel
* Docker-compatible environment for Wings

---

## 📁 Important Paths

### Pterodactyl Panel

```text
/var/www/pterodactyl
```

### Wings

```text
/usr/local/bin/wings
```

### Wings configuration

```text
/etc/pterodactyl/config.yml
```

### Installer log

```text
/var/log/mg-ptero-installer.log
```

### Backups

```text
/var/backups/mg-ptero/
```

### Nginx configuration

```text
/etc/nginx/sites-available/pterodactyl.conf
```

---

## 🧰 Useful Commands

### Check Panel Worker

```bash
systemctl status pterodactyl-worker
```

### Restart Panel Worker

```bash
systemctl restart pterodactyl-worker
```

### Check Wings

```bash
systemctl status wings
```

### Restart Wings

```bash
systemctl restart wings
```

### Check Nginx

```bash
nginx -t
systemctl status nginx
```

### Restart Nginx

```bash
systemctl restart nginx
```

### Check Docker

```bash
systemctl status docker
```

---

## 🔗 Repository

**MG Ptero Installer**

[https://github.com/MGFEARLESSYT/ptero-installer](https://github.com/MGFEARLESSYT/ptero-installer)

---

## ⚠️ Disclaimer

This project is provided as-is.

Always maintain independent backups before:

* Major Panel updates
* Database changes
* Uninstall operations
* Server migrations

Test the installer on a non-production server before deploying it to production infrastructure.

---

## 📄 License

MIT License

Copyright © 2026 MGFEARLESSYT

```
```
