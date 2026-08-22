#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# MG PTERO INSTALLER v2
# GitHub: https://github.com/MGFEARLESSYT/ptero-installer
# ============================================================

export DEBIAN_FRONTEND=noninteractive
LOG="/var/log/mg-ptero-installer.log"
BACKUP_DIR="/var/backups/mg-ptero"
mkdir -p "$(dirname "$LOG")" "$BACKUP_DIR"
touch "$LOG"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; }
ok(){ echo -e "${GREEN}✔${RESET} $*"; log "$*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; log "WARNING: $*"; }
fail(){ echo -e "${RED}✖${RESET} $*"; log "ERROR: $*"; }
pause(){ echo; read -rp "Press Enter to continue..." _; }

title(){
  clear
  echo -e "${CYAN}${BOLD}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║                 MG PTERO INSTALLER v2                     ║"
  echo "║              Pterodactyl Deployment Manager               ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

require_root(){
  [[ $EUID -eq 0 ]] || { fail "Run this installer as root."; exit 1; }
}

detect_os(){
  source /etc/os-release
  case "${ID}:${VERSION_ID}" in
    ubuntu:22.04|ubuntu:24.04|debian:12) ;;
    *) fail "Supported OS: Ubuntu 22.04, Ubuntu 24.04, Debian 12."; exit 1 ;;
  esac
}

service_state(){
  local svc="$1"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "${GREEN}RUNNING${RESET}"
  elif systemctl list-unit-files "$svc.service" 2>/dev/null | grep -q "$svc.service"; then
    echo -e "${RED}STOPPED${RESET}"
  else
    echo -e "${YELLOW}NOT INSTALLED${RESET}"
  fi
}

install_dependencies(){
  ok "Updating package lists..."
  apt-get update >>"$LOG" 2>&1

  apt-get install -y curl wget git unzip tar sudo ca-certificates gnupg2 \
    lsb-release software-properties-common apt-transport-https \
    nginx mariadb-server redis-server certbot python3-certbot-nginx \
    rsync >>"$LOG" 2>&1

  if [[ "$ID" == "ubuntu" ]]; then
    add-apt-repository -y ppa:ondrej/php >>"$LOG" 2>&1 || true
    apt-get update >>"$LOG" 2>&1
  fi

  apt-get install -y php8.3 php8.3-cli php8.3-fpm php8.3-common \
    php8.3-mysql php8.3-gd php8.3-mbstring php8.3-bcmath \
    php8.3-xml php8.3-curl php8.3-zip php8.3-intl php8.3-redis \
    composer >>"$LOG" 2>&1

  if ! command -v docker >/dev/null 2>&1; then
    ok "Installing Docker..."
    curl -fsSL https://get.docker.com | sh >>"$LOG" 2>&1
  fi
  systemctl enable --now docker >>"$LOG" 2>&1
}

install_panel(){
  title
  echo -e "${BOLD}Pterodactyl Panel Installation${RESET}\n"

  read -rp "Panel domain: " PANEL_DOMAIN
  read -rp "Admin email: " ADMIN_EMAIL
  read -rsp "Database password: " DB_PASS; echo
  read -rsp "Admin password: " ADMIN_PASS; echo

  [[ -n "$PANEL_DOMAIN" && -n "$ADMIN_EMAIL" && -n "$DB_PASS" && -n "$ADMIN_PASS" ]] || {
    warn "All fields are required."; pause; return
  }

  install_dependencies

  id pterodactyl >/dev/null 2>&1 || \
    useradd -m -d /var/www/pterodactyl -s /bin/bash pterodactyl

  mkdir -p /var/www/pterodactyl /etc/pterodactyl
  chown -R pterodactyl:pterodactyl /var/www/pterodactyl

  if [[ ! -f /var/www/pterodactyl/artisan ]]; then
    ok "Downloading Pterodactyl Panel..."
    curl -fL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
      -o /tmp/pterodactyl-panel.tar.gz >>"$LOG" 2>&1
    tar -xzf /tmp/pterodactyl-panel.tar.gz -C /var/www/pterodactyl
    chown -R pterodactyl:pterodactyl /var/www/pterodactyl
  fi

  cd /var/www/pterodactyl
  ok "Installing Composer dependencies..."
  sudo -u pterodactyl composer install --no-dev --optimize-autoloader --no-interaction >>"$LOG" 2>&1

  systemctl enable --now mariadb redis-server >>"$LOG" 2>&1

  mysql <<SQL
CREATE DATABASE IF NOT EXISTS panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS//\'/\'\'}';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS//\'/\'\'}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

  sudo -u pterodactyl cp -n .env.example .env || true
  sudo -u pterodactyl php artisan key:generate --force >>"$LOG" 2>&1
  sudo -u pterodactyl php artisan p:environment:setup \
    --author="$ADMIN_EMAIL" --url="https://$PANEL_DOMAIN" \
    --timezone="Asia/Kolkata" --cache="redis" --session="redis" --queue="redis" \
    --redis-host="127.0.0.1" --redis-port="6379" --redis-pass="null" >>"$LOG" 2>&1
  sudo -u pterodactyl php artisan p:environment:database \
    --host="127.0.0.1" --port="3306" --database="panel" \
    --username="pterodactyl" --password="$DB_PASS" >>"$LOG" 2>&1
  sudo -u pterodactyl php artisan migrate --seed --force >>"$LOG" 2>&1
  sudo -u pterodactyl php artisan p:user:make \
    --email="$ADMIN_EMAIL" --username="admin" --name-first="Admin" \
    --name-last="User" --password="$ADMIN_PASS" --admin=1 >>"$LOG" 2>&1 || true

  configure_panel_services "$PANEL_DOMAIN"

  echo
  ok "Panel installation completed."
  echo "URL: https://$PANEL_DOMAIN"
  echo "Installer log: $LOG"
  pause
}

configure_panel_services(){
  local domain="$1"

  chown -R www-data:www-data /var/www/pterodactyl
  chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

  cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
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

  ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >>"$LOG" 2>&1
  systemctl enable --now nginx >>"$LOG" 2>&1
  systemctl reload nginx >>"$LOG" 2>&1

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
Description=Pterodactyl Scheduler Every Minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=pterodactyl-schedule.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload >>"$LOG" 2>&1
  systemctl enable --now pterodactyl-worker.service pterodactyl-schedule.timer >>"$LOG" 2>&1
}

install_wings(){
  title
  echo -e "${BOLD}Wings Installation${RESET}\n"

  install_dependencies
  mkdir -p /etc/pterodactyl

  ok "Downloading latest Wings..."
  curl -fL https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 \
    -o /usr/local/bin/wings >>"$LOG" 2>&1
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

  systemctl daemon-reload >>"$LOG" 2>&1
  systemctl enable wings >>"$LOG" 2>&1

  echo
  ok "Wings installed."
  echo "Create your Node in the Panel and put its generated config at:"
  echo "/etc/pterodactyl/config.yml"
  pause
}

update_panel(){
  title
  [[ -f /var/www/pterodactyl/artisan ]] || {
    warn "Pterodactyl Panel is not installed."; pause; return
  }

  local stamp backup tmp
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$BACKUP_DIR/panel-$stamp"
  tmp="/tmp/ptero-panel-$stamp"

  mkdir -p "$backup" "$tmp"

  ok "Backing up .env and storage..."
  cp -a /var/www/pterodactyl/.env "$backup/.env" 2>/dev/null || true
  cp -a /var/www/pterodactyl/storage "$backup/storage" 2>/dev/null || true

  ok "Downloading latest Panel release..."
  curl -fL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
    -o "$tmp/panel.tar.gz" >>"$LOG" 2>&1
  tar -xzf "$tmp/panel.tar.gz" -C "$tmp"

  ok "Updating application files..."
  rsync -a --delete \
    --exclude=".env" \
    --exclude="storage/" \
    "$tmp/" /var/www/pterodactyl/ >>"$LOG" 2>&1

  cd /var/www/pterodactyl
  ok "Updating Composer dependencies..."
  sudo -u pterodactyl composer install --no-dev --optimize-autoloader --no-interaction >>"$LOG" 2>&1

  ok "Running database migrations..."
  sudo -u pterodactyl php artisan migrate --seed --force >>"$LOG" 2>&1

  chown -R www-data:www-data /var/www/pterodactyl
  chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

  systemctl restart php8.3-fpm nginx pterodactyl-worker >>"$LOG" 2>&1 || true

  rm -rf "$tmp"
  echo
  ok "Panel updated successfully."
  echo "Backup: $backup"
  pause
}

update_wings(){
  title
  ok "Downloading latest Wings..."
  mkdir -p /etc/pterodactyl
  curl -fL https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 \
    -o /usr/local/bin/wings.new >>"$LOG" 2>&1
  chmod +x /usr/local/bin/wings.new
  mv /usr/local/bin/wings.new /usr/local/bin/wings
  systemctl daemon-reload >>"$LOG" 2>&1
  systemctl restart wings >>"$LOG" 2>&1 || true
  ok "Wings updated."
  pause
}

backup_panel(){
  title
  [[ -d /var/www/pterodactyl ]] || { warn "Panel not installed."; pause; return; }

  local stamp dest
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="$BACKUP_DIR/manual-$stamp"
  mkdir -p "$dest"

  ok "Backing up Panel files..."
  tar -czf "$dest/pterodactyl-files.tar.gz" \
    -C /var/www/pterodactyl .env storage >>"$LOG" 2>&1 || true

  ok "Backing up database..."
  mysqldump --single-transaction --routines --triggers panel \
    >"$dest/panel.sql" 2>>"$LOG"

  echo
  ok "Backup complete: $dest"
  pause
}

repair(){
  title
  ok "Repairing Pterodactyl..."
  [[ -d /var/www/pterodactyl ]] || { warn "Panel not installed."; pause; return; }

  cd /var/www/pterodactyl
  chown -R www-data:www-data .
  chmod -R 755 storage bootstrap/cache
  sudo -u www-data php artisan optimize:clear >>"$LOG" 2>&1 || true
  sudo -u www-data php artisan config:cache >>"$LOG" 2>&1 || true
  sudo -u www-data php artisan route:cache >>"$LOG" 2>&1 || true
  sudo -u www-data php artisan view:cache >>"$LOG" 2>&1 || true

  nginx -t >>"$LOG" 2>&1 && systemctl reload nginx >>"$LOG" 2>&1
  systemctl restart redis-server pterodactyl-worker >>"$LOG" 2>&1 || true
  systemctl restart wings >>"$LOG" 2>&1 || true

  ok "Repair completed."
  pause
}

ssl(){
  title
  echo -e "${BOLD}SSL Manager${RESET}\n"
  read -rp "Panel domain: " DOMAIN
  [[ -n "$DOMAIN" ]] || { warn "Domain required."; pause; return; }

  if certbot --nginx --non-interactive --agree-tos \
      -d "$DOMAIN" --redirect >>"$LOG" 2>&1; then
    ok "SSL certificate installed/renewed for $DOMAIN."
  else
    warn "Certbot failed. Check DNS, ports 80/443 and $LOG."
  fi
  pause
}

status(){
  title
  echo -e "${BOLD}Service Status${RESET}\n"
  printf "%-28s %b\n" "Nginx" "$(service_state nginx)"
  printf "%-28s %b\n" "MariaDB" "$(service_state mariadb)"
  printf "%-28s %b\n" "Redis" "$(service_state redis-server)"
  printf "%-28s %b\n" "Docker" "$(service_state docker)"
  printf "%-28s %b\n" "Panel Worker" "$(service_state pterodactyl-worker)"
  printf "%-28s %b\n" "Wings" "$(service_state wings)"
  echo
  if [[ -f /var/www/pterodactyl/artisan ]]; then
    echo "Panel: INSTALLED"
  else
    echo "Panel: NOT INSTALLED"
  fi
  [[ -x /usr/local/bin/wings ]] && echo "Wings binary: INSTALLED" || echo "Wings binary: NOT INSTALLED"
  pause
}

logs(){
  title
  echo -e "${BOLD}Logs${RESET}\n"
  echo "1) Installer log"
  echo "2) Wings log"
  echo "3) Panel worker log"
  echo "4) Panel application log"
  echo "5) Back"
  echo
  read -rp "Select [1-5]: " c
  case "$c" in
    1) tail -n 80 "$LOG"; pause ;;
    2) journalctl -u wings -n 80 --no-pager; pause ;;
    3) journalctl -u pterodactyl-worker -n 80 --no-pager; pause ;;
    4) ls -1t /var/www/pterodactyl/storage/logs/*.log 2>/dev/null | head -1 | xargs -r tail -n 80; pause ;;
  esac
}

uninstall_menu(){
  title
  echo -e "${RED}${BOLD}DANGER ZONE${RESET}\n"
  echo "This removes the Panel application and/or Wings."
  echo
  echo "1) Remove Panel only"
  echo "2) Remove Wings only"
  echo "3) Cancel"
  echo
  read -rp "Select [1-3]: " c

  case "$c" in
    1)
      read -rp "Type REMOVE-PANEL to confirm: " confirm
      [[ "$confirm" == "REMOVE-PANEL" ]] || { warn "Cancelled."; pause; return; }
      systemctl disable --now pterodactyl-worker pterodactyl-schedule.timer 2>/dev/null || true
      rm -f /etc/systemd/system/pterodactyl-worker.service \
        /etc/systemd/system/pterodactyl-schedule.service \
        /etc/systemd/system/pterodactyl-schedule.timer
      systemctl daemon-reload
      rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
      systemctl reload nginx 2>/dev/null || true
      mv /var/www/pterodactyl "$BACKUP_DIR/removed-panel-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
      ok "Panel application removed/moved to backup directory."
      pause
      ;;
    2)
      read -rp "Type REMOVE-WINGS to confirm: " confirm
      [[ "$confirm" == "REMOVE-WINGS" ]] || { warn "Cancelled."; pause; return; }
      systemctl disable --now wings 2>/dev/null || true
      rm -f /etc/systemd/system/wings.service /usr/local/bin/wings
      systemctl daemon-reload
      ok "Wings removed."
      pause
      ;;
  esac
}

main_menu(){
  while true; do
    title
    echo -e "${BOLD}Installation${RESET}"
    echo "  1) Install Panel"
    echo "  2) Install Wings"
    echo "  3) Install Panel + Wings"
    echo
    echo -e "${BOLD}Management${RESET}"
    echo "  4) Update Panel"
    echo "  5) Update Wings"
    echo "  6) Backup Panel + Database"
    echo "  7) Repair Panel"
    echo "  8) SSL Manager"
    echo "  9) Service Status"
    echo " 10) View Logs"
    echo
    echo -e "${RED}11) Uninstall / Remove${RESET}"
    echo " 12) Exit"
    echo
    read -rp "Select [1-12]: " choice

    case "$choice" in
      1) install_panel ;;
      2) install_wings ;;
      3) install_panel; install_wings ;;
      4) update_panel ;;
      5) update_wings ;;
      6) backup_panel ;;
      7) repair ;;
      8) ssl ;;
      9) status ;;
      10) logs ;;
      11) uninstall_menu ;;
      12) clear; echo "MG Ptero Installer closed."; exit 0 ;;
      *) warn "Invalid option."; sleep 1 ;;
    esac
  done
}

require_root
detect_os
main_menu
