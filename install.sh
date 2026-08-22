#!/usr/bin/env bash
set -Eeuo pipefail

# Pterodactyl All-in-One Installer
# Fresh Ubuntu 22.04/24.04 or Debian 12
# Installs Panel + Wings + Docker + MariaDB + Redis + Nginx + PHP + SSL

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash install.sh"; exit 1; }

source /etc/os-release
case "${ID}:${VERSION_ID}" in
  ubuntu:22.04|ubuntu:24.04|debian:12) ;;
  *) echo "Supported OS: Ubuntu 22.04/24.04 or Debian 12"; exit 1 ;;
esac

log(){ echo -e "\n\033[1;36m[MG PTERODACTYL] $*\033[0m"; }
trap 'echo "Installer failed at line $LINENO"; exit 1' ERR

export DEBIAN_FRONTEND=noninteractive

read -rp "Panel domain [panel.example.com]: " PANEL_DOMAIN
read -rp "Node domain [node.example.com]: " NODE_DOMAIN
read -rp "Admin email: " ADMIN_EMAIL
read -rsp "Database password: " DB_PASS; echo
read -rsp "Panel admin password: " ADMIN_PASS; echo

[[ -n "$PANEL_DOMAIN" && -n "$NODE_DOMAIN" && -n "$ADMIN_EMAIL" && -n "$DB_PASS" && -n "$ADMIN_PASS" ]] || {
  echo "All fields are required."; exit 1;
}

log "Updating system"
apt-get update
apt-get upgrade -y

log "Installing base packages"
apt-get install -y \
  curl wget git unzip tar sudo ca-certificates gnupg2 lsb-release \
  software-properties-common apt-transport-https \
  nginx mariadb-server redis-server \
  certbot python3-certbot-nginx

if [[ "$ID" == "ubuntu" ]]; then
  add-apt-repository -y ppa:ondrej/php
  apt-get update
fi

log "Installing PHP and Composer"
apt-get install -y \
  php8.3 php8.3-cli php8.3-fpm php8.3-common php8.3-mysql \
  php8.3-gd php8.3-mbstring php8.3-bcmath php8.3-xml \
  php8.3-curl php8.3-zip php8.3-intl php8.3-redis composer

log "Installing Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

log "Creating Pterodactyl user"
id pterodactyl >/dev/null 2>&1 || \
  useradd -m -d /var/www/pterodactyl -s /bin/bash pterodactyl
mkdir -p /var/www/pterodactyl /etc/pterodactyl
chown -R pterodactyl:pterodactyl /var/www/pterodactyl

log "Downloading Pterodactyl Panel"
if [[ ! -f /var/www/pterodactyl/artisan ]]; then
  curl -fL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
    -o /tmp/pterodactyl-panel.tar.gz
  tar -xzf /tmp/pterodactyl-panel.tar.gz -C /var/www/pterodactyl
  chown -R pterodactyl:pterodactyl /var/www/pterodactyl
fi

cd /var/www/pterodactyl

log "Installing PHP dependencies"
sudo -u pterodactyl composer install --no-dev --optimize-autoloader --no-interaction

log "Starting database services"
systemctl enable --now mariadb redis-server

log "Creating database"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS//\'/\'\'}';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS//\'/\'\'}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

log "Configuring environment"
sudo -u pterodactyl cp -n .env.example .env || true

sudo -u pterodactyl php artisan key:generate --force

sudo -u pterodactyl php artisan p:environment:setup \
  --author="$ADMIN_EMAIL" \
  --url="https://$PANEL_DOMAIN" \
  --timezone="Asia/Kolkata" \
  --cache="redis" \
  --session="redis" \
  --queue="redis" \
  --redis-host="127.0.0.1" \
  --redis-port="6379" \
  --redis-pass="null"

sudo -u pterodactyl php artisan p:environment:database \
  --host="127.0.0.1" \
  --port="3306" \
  --database="panel" \
  --username="pterodactyl" \
  --password="$DB_PASS"

sudo -u pterodactyl php artisan migrate --seed --force

log "Creating administrator"
sudo -u pterodactyl php artisan p:user:make \
  --email="$ADMIN_EMAIL" \
  --username="admin" \
  --name-first="Admin" \
  --name-last="User" \
  --password="$ADMIN_PASS" \
  --admin=1 || true

log "Fixing permissions"
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

log "Configuring Nginx"
cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $PANEL_DOMAIN;

    root /var/www/pterodactyl/public;
    index index.php;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf \
  /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable --now nginx
systemctl reload nginx

log "Installing Wings"
curl -fL https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 \
  -o /usr/local/bin/wings
chmod +x /usr/local/bin/wings

cat >/etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wings

log "Installing queue worker"
cat >/etc/systemd/system/pterodactyl-worker.service <<'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Requires=redis-server.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/pterodactyl
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

log "Installing scheduler"
cat >/etc/systemd/system/pterodactyl-schedule.service <<'EOF'
[Unit]
Description=Pterodactyl Scheduler

[Service]
Type=oneshot
User=www-data
Group=www-data
WorkingDirectory=/var/www/pterodactyl
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan schedule:run
EOF

cat >/etc/systemd/system/pterodactyl-schedule.timer <<'EOF'
[Unit]
Description=Run Pterodactyl Scheduler Every Minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=pterodactyl-schedule.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now pterodactyl-worker.service
systemctl enable --now pterodactyl-schedule.timer

log "Trying automatic SSL"
if certbot --nginx --non-interactive --agree-tos \
  -m "$ADMIN_EMAIL" -d "$PANEL_DOMAIN" --redirect; then
  echo "Panel SSL installed."
else
  echo "Automatic SSL failed."
  echo "Make sure DNS points $PANEL_DOMAIN to this server, then run:"
  echo "certbot --nginx -d $PANEL_DOMAIN"
fi

echo
echo "======================================================"
echo "        PTERODACTYL ALL-IN-ONE INSTALL COMPLETE"
echo "======================================================"
echo "Panel : https://$PANEL_DOMAIN"
echo "Node  : $NODE_DOMAIN"
echo
echo "Next:"
echo "1. Login to the Panel."
echo "2. Admin -> Locations -> create location."
echo "3. Admin -> Nodes -> Create Node."
echo "4. Set FQDN to: $NODE_DOMAIN"
echo "5. Copy the generated Wings config to:"
echo "   /etc/pterodactyl/config.yml"
echo "6. Start Wings:"
echo "   systemctl restart wings"
echo
echo "Status:"
systemctl is-active --quiet nginx && echo "✓ Nginx"
systemctl is-active --quiet mariadb && echo "✓ MariaDB"
systemctl is-active --quiet redis-server && echo "✓ Redis"
systemctl is-active --quiet docker && echo "✓ Docker"
systemctl is-active --quiet pterodactyl-worker && echo "✓ Queue Worker"
echo "======================================================"
