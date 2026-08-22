#!/usr/bin/env bash

# ============================================================
# MG PTERO INSTALLER
# Pterodactyl Panel + Wings All-In-One Installer
# ============================================================

set -Eeuo pipefail

VERSION="3.0.0"
PANEL_DIR="/var/www/pterodactyl"
BACKUP_DIR="/var/backups/mg-ptero"
LOG_FILE="/var/log/mg-ptero-installer.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# BASIC FUNCTIONS
# ============================================================

msg() {
    echo -e "${CYAN}[MG]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

die() {
    error "$1"
    exit 1
}

step() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pause() {
    echo
    read -r -p "Press Enter to continue..." _
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# ROOT CHECK
# ============================================================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        die "Run this installer as root."
    fi
}

# ============================================================
# OS CHECK
# ============================================================

check_os() {

    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect operating system."
    fi

    source /etc/os-release

    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"

    case "$OS_ID" in

        ubuntu)
            case "$OS_VERSION" in
                22.04|24.04)
                    success "Supported OS: Ubuntu $OS_VERSION"
                    ;;
                *)
                    die "Unsupported Ubuntu version: $OS_VERSION"
                    ;;
            esac
            ;;

        debian)
            case "$OS_VERSION" in
                12|13)
                    success "Supported OS: Debian $OS_VERSION"
                    ;;
                *)
                    die "Unsupported Debian version: $OS_VERSION"
                    ;;
            esac
            ;;

        *)
            die "Unsupported operating system: $OS_ID"
            ;;

    esac
}

# ============================================================
# INTERNET CHECK
# ============================================================

check_internet() {

    step "Checking Internet Connectivity"

    if ! curl -4fsSL --connect-timeout 10 --max-time 20 \
        https://www.google.com >/dev/null; then

        die "Internet connection unavailable."
    fi

    success "Internet connection OK"
}

# ============================================================
# PUBLIC IP
# ============================================================

get_public_ip() {

    PUBLIC_IP=""

    PUBLIC_IP="$(curl -4fsSL \
        --connect-timeout 10 \
        --max-time 20 \
        https://api.ipify.org 2>/dev/null || true)"

    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP="$(curl -4fsSL \
            --connect-timeout 10 \
            --max-time 20 \
            https://ifconfig.me 2>/dev/null || true)"
    fi

    if [[ -z "$PUBLIC_IP" ]]; then
        die "Unable to detect public IPv4 address."
    fi
}

# ============================================================
# DOMAIN VALIDATION
# ============================================================

validate_domain_format() {

    local domain="$1"

    if [[ ! "$domain" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi

    return 0
}

check_domain_dns() {

    local domain="$1"

    step "Checking Panel Domain"

    if ! validate_domain_format "$domain"; then
        error "Invalid domain format."
        echo
        echo "Example:"
        echo "panel.example.com"
        return 1
    fi

    success "Domain format valid"

    msg "Resolving $domain..."

    local resolved_ips

    resolved_ips="$(getent ahostsv4 "$domain" 2>/dev/null \
        | awk '{print $1}' \
        | sort -u)"

    if [[ -z "$resolved_ips" ]]; then

        error "DNS resolution failed."
        echo
        echo "Create an A record:"
        echo
        echo "    $domain -> $PUBLIC_IP"
        echo

        return 1
    fi

    success "DNS record found"

    echo
    echo "Resolved IP addresses:"
    echo "$resolved_ips" | sed 's/^/    /'

    if echo "$resolved_ips" | grep -qx "$PUBLIC_IP"; then

        success "$domain points to this server ($PUBLIC_IP)"
        return 0

    fi

    echo
    warn "The domain resolves, but does NOT point directly to this server."
    echo
    echo "Server IP:"
    echo "    $PUBLIC_IP"
    echo
    echo "Domain IP:"
    echo "$resolved_ips" | sed 's/^/    /'
    echo
    echo "If you are using Cloudflare proxying, this can be expected."
    echo

    read -r -p "Continue anyway? [y/N]: " answer

    case "$answer" in
        y|Y|yes|YES)
            success "Continuing with resolved domain."
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================
# PORT CHECK
# ============================================================

check_ports() {

    step "Checking Required Ports"

    for port in 80 443; do

        if ss -lnt 2>/dev/null | awk '{print $4}' \
            | grep -Eq "(:|\\])${port}$"; then

            warn "Port $port is currently in use."

        else

            success "Port $port is available"

        fi

    done
}

# ============================================================
# PACKAGE INSTALL
# ============================================================

apt_install() {

    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# ============================================================
# PHP REPOSITORY
# ============================================================

setup_php_repository() {

    step "Configuring PHP Repository"

    apt_install \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    if [[ "$OS_ID" == "ubuntu" ]]; then

        if [[ "$OS_VERSION" == "22.04" ]]; then

            add-apt-repository -y ppa:ondrej/php
            apt-get update -y

        else

            apt-get update -y

        fi

    elif [[ "$OS_ID" == "debian" ]]; then

        apt_install \
            apt-transport-https \
            ca-certificates

        install -d -m 0755 /etc/apt/keyrings

        curl -fsSL \
            https://packages.sury.org/php/apt.gpg \
            | gpg --dearmor \
            -o /etc/apt/keyrings/sury-php.gpg

        echo \
            "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
            > /etc/apt/sources.list.d/php.list

        apt-get update -y

    fi

    success "PHP repository configured"
}

# ============================================================
# DEPENDENCIES
# ============================================================

install_dependencies() {

    step "Installing Pterodactyl Dependencies"

    setup_php_repository

    apt_install \
        php8.3 \
        php8.3-cli \
        php8.3-common \
        php8.3-gd \
        php8.3-mysql \
        php8.3-mbstring \
        php8.3-bcmath \
        php8.3-xml \
        php8.3-fpm \
        php8.3-curl \
        php8.3-zip \
        mariadb-server \
        nginx \
        tar \
        unzip \
        git \
        redis-server \
        ca-certificates \
        curl \
        gnupg \
        cron \
        certbot \
        python3-certbot-nginx

    success "Dependencies installed"
}

# ============================================================
# COMPOSER
# ============================================================

install_composer() {

    step "Installing Composer"

    if command_exists composer; then

        composer self-update --2 >/dev/null 2>&1 || true
        success "Composer already installed"

    else

        curl -fsSL https://getcomposer.org/installer \
            -o /tmp/composer-setup.php

        php /tmp/composer-setup.php \
            --install-dir=/usr/local/bin \
            --filename=composer

        rm -f /tmp/composer-setup.php

        success "Composer installed"

    fi
}

# ============================================================
# MARIADB
# ============================================================

setup_database() {

    step "Configuring MariaDB"

    systemctl enable --now mariadb

    DB_NAME="panel"
    DB_USER="pterodactyl"

    DB_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"

    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

    success "MariaDB configured"
}

# ============================================================
# REDIS
# ============================================================

setup_redis() {

    step "Configuring Redis"

    systemctl enable --now redis-server

    if systemctl is-active --quiet redis-server; then
        success "Redis is running"
    else
        die "Redis failed to start."
    fi
}

# ============================================================
# DOCKER
# ============================================================

install_docker() {

    step "Installing Docker"

    if command_exists docker; then

        success "Docker already installed"

    else

        curl -fsSL https://get.docker.com \
            | sh

        success "Docker installed"

    fi

    systemctl enable --now docker

    if ! systemctl is-active --quiet docker; then
        die "Docker failed to start."
    fi

    success "Docker is running"
}

# ============================================================
# PANEL DOWNLOAD
# ============================================================

download_panel() {

    step "Downloading Pterodactyl Panel"

    mkdir -p "$PANEL_DIR"

    cd "$PANEL_DIR"

    if [[ -f .env ]]; then

        cp .env /tmp/pterodactyl-env-backup

    fi

    rm -f panel.tar.gz

    curl -fL \
        --connect-timeout 10 \
        --max-time 300 \
        -o panel.tar.gz \
        https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz

    tar -xzf panel.tar.gz

    rm -f panel.tar.gz

    chmod -R 755 storage bootstrap/cache

    success "Pterodactyl Panel downloaded"
}

# ============================================================
# PANEL ENV
# ============================================================

configure_panel_env() {

    step "Configuring Pterodactyl"

    cd "$PANEL_DIR"

    cp .env.example .env

    APP_URL="https://${PANEL_DOMAIN}"

    php artisan key:generate --force

    sed -i \
        "s|^APP_URL=.*|APP_URL=${APP_URL}|" \
        .env

    sed -i \
        "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" \
        .env

    sed -i \
        "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" \
        .env

    sed -i \
        "s|^DB_PORT=.*|DB_PORT=3306|" \
        .env

    sed -i \
        "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" \
        .env

    sed -i \
        "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" \
        .env

    sed -i \
        "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" \
        .env

    sed -i \
        "s|^CACHE_STORE=.*|CACHE_STORE=redis|" \
        .env || true

    sed -i \
        "s|^SESSION_DRIVER=.*|SESSION_DRIVER=redis|" \
        .env

    sed -i \
        "s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|" \
        .env

    sed -i \
        "s|^REDIS_HOST=.*|REDIS_HOST=127.0.0.1|" \
        .env

    sed -i \
        "s|^REDIS_PORT=.*|REDIS_PORT=6379|" \
        .env

    sed -i \
        "s|^MAIL_MAILER=.*|MAIL_MAILER=log|" \
        .env

    success "Panel environment configured"
}

# ============================================================
# COMPOSER PANEL
# ============================================================

install_panel_dependencies() {

    step "Installing Panel Composer Dependencies"

    cd "$PANEL_DIR"

    COMPOSER_ALLOW_SUPERUSER=1 \
        composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

    success "Panel dependencies installed"
}

# ============================================================
# MIGRATION
# ============================================================

migrate_database() {

    step "Creating Pterodactyl Database Tables"

    cd "$PANEL_DIR"

    php artisan migrate \
        --seed \
        --force

    success "Database migration completed"
}

# ============================================================
# ADMIN USER
# ============================================================

create_admin() {

    step "Create Pterodactyl Administrator"

    cd "$PANEL_DIR"

    echo
    echo "The official Pterodactyl administrator wizard will now open."
    echo "Enter the administrator details when prompted."
    echo

    php artisan p:user:make

    success "Administrator creation completed"
}

# ============================================================
# PERMISSIONS
# ============================================================

set_panel_permissions() {

    step "Setting Panel Permissions"

    chown -R www-data:www-data "$PANEL_DIR"

    chmod -R 755 \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/bootstrap/cache"

    success "Panel permissions configured"
}

# ============================================================
# NGINX
# ============================================================

configure_nginx() {

    step "Configuring Nginx"

    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${PANEL_DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl_access.log;
    error_log /var/log/nginx/pterodactyl_error.log;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;

        fastcgi_pass unix:/run/php/php8.3-fpm.sock;

        fastcgi_index index.php;
        include fastcgi_params;

        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_param HTTP_AUTHORIZATION \$http_authorization;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf

    rm -f /etc/nginx/sites-enabled/default

    nginx -t

    systemctl enable --now nginx
    systemctl reload nginx

    success "Nginx configured"
}

# ============================================================
# QUEUE WORKER
# ============================================================

configure_queue_worker() {

    step "Configuring Pterodactyl Queue Worker"

    cat > /etc/systemd/system/pterodactyl-worker.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Requires=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pterodactyl-worker

    success "Queue worker configured"
}

# ============================================================
# CRON
# ============================================================

configure_cron() {

    step "Configuring Pterodactyl Scheduler"

    local CRON_LINE="* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"

    crontab -u www-data -l 2>/dev/null \
        | grep -Fv "${PANEL_DIR}/artisan schedule:run" \
        > /tmp/ptero-cron 2>/dev/null || true

    echo "$CRON_LINE" >> /tmp/ptero-cron

    crontab -u www-data /tmp/ptero-cron

    rm -f /tmp/ptero-cron

    systemctl enable --now cron

    success "Scheduler configured"
}

# ============================================================
# SSL
# ============================================================

install_ssl() {

    step "Installing SSL Certificate"

    if ! command_exists certbot; then

        apt_install certbot python3-certbot-nginx

    fi

    echo
    echo "Requesting Let's Encrypt certificate for:"
    echo "https://${PANEL_DOMAIN}"
    echo

    certbot --nginx \
        -d "$PANEL_DOMAIN" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --redirect

    systemctl reload nginx

    success "SSL configured"
}

# ============================================================
# FULL PANEL INSTALL
# ============================================================

install_panel() {

    clear

    check_os
    check_internet
    get_public_ip

    step "Panel Domain Setup"

    echo
    read -r -p "Enter Panel Domain: " PANEL_DOMAIN

    if [[ -z "$PANEL_DOMAIN" ]]; then
        die "Panel domain cannot be empty."
    fi

    if ! check_domain_dns "$PANEL_DOMAIN"; then
        die "Domain verification failed. Installation stopped."
    fi

    check_ports

    echo
    read -r -p "Continue with Pterodactyl Panel installation? [y/N]: " confirm

    case "$confirm" in
        y|Y|yes|YES)
            ;;
        *)
            echo "Installation cancelled."
            return
            ;;
    esac

    install_dependencies
    install_composer
    setup_database
    setup_redis
    download_panel
    configure_panel_env
    install_panel_dependencies
    migrate_database
    create_admin
    set_panel_permissions
    configure_nginx
    configure_queue_worker
    configure_cron

    echo
    read -r -p "Install Let's Encrypt SSL now? [Y/n]: " ssl_answer

    case "$ssl_answer" in
        n|N|no|NO)
            warn "SSL skipped."
            ;;
        *)
            install_ssl
            ;;
    esac

    success "Pterodactyl Panel installation completed."

    echo
    echo "Panel:"
    echo "https://${PANEL_DOMAIN}"
    echo
    echo "Panel directory:"
    echo "$PANEL_DIR"
    echo
    echo "Installer log:"
    echo "$LOG_FILE"

    pause
}

# ============================================================
# WINGS
# ============================================================

install_wings() {

    clear

    check_os
    check_internet

    step "Installing Pterodactyl Wings"

    install_docker

    mkdir -p /etc/pterodactyl

    ARCH="$(uname -m)"

    case "$ARCH" in
        x86_64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            die "Unsupported CPU architecture: $ARCH"
            ;;
    esac

    msg "Downloading Wings for ${WINGS_ARCH}..."

    curl -fL \
        --connect-timeout 10 \
        --max-time 300 \
        -o /usr/local/bin/wings \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

    chmod u+x /usr/local/bin/wings

    cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    success "Wings installed."

    echo
    echo "IMPORTANT:"
    echo
    echo "Create your Node in Pterodactyl Panel."
    echo
    echo "Then copy the generated configuration to:"
    echo
    echo "/etc/pterodactyl/config.yml"
    echo
    echo "After that run:"
    echo
    echo "systemctl enable --now wings"
    echo

    if [[ -f /etc/pterodactyl/config.yml ]]; then

        systemctl enable --now wings

        if systemctl is-active --quiet wings; then
            success "Wings started successfully."
        else
            warn "Wings did not start. Check: journalctl -u wings -n 100"
        fi

    else

        warn "No Wings config found yet. Wings was installed but not started."

    fi

    pause
}

# ============================================================
# UPDATE PANEL
# ============================================================

update_panel() {

    clear

    if [[ ! -d "$PANEL_DIR" ]]; then
        die "Pterodactyl Panel is not installed."
    fi

    step "Backing Up Before Panel Update"

    mkdir -p "$BACKUP_DIR"

    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

    tar -czf \
        "$BACKUP_DIR/panel-before-update-${TIMESTAMP}.tar.gz" \
        "$PANEL_DIR/.env" \
        "$PANEL_DIR/storage" \
        2>/dev/null || true

    if command_exists mariadb-dump; then

        mariadb-dump \
            --single-transaction \
            panel \
            > "$BACKUP_DIR/database-before-update-${TIMESTAMP}.sql"

    fi

    success "Backup created"

    step "Updating Pterodactyl Panel"

    cd "$PANEL_DIR"

    cp .env /tmp/pterodactyl-env-update

    curl -fL \
        --connect-timeout 10 \
        --max-time 300 \
        -o /tmp/panel.tar.gz \
        https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz

    rm -rf /tmp/pterodactyl-panel-update

    mkdir -p /tmp/pterodactyl-panel-update

    tar -xzf \
        /tmp/panel.tar.gz \
        -C /tmp/pterodactyl-panel-update

    cp -a \
        /tmp/pterodactyl-panel-update/. \
        "$PANEL_DIR/"

    cp \
        /tmp/pterodactyl-env-update \
        "$PANEL_DIR/.env"

    rm -rf \
        /tmp/panel.tar.gz \
        /tmp/pterodactyl-panel-update \
        /tmp/pterodactyl-env-update

    cd "$PANEL_DIR"

    COMPOSER_ALLOW_SUPERUSER=1 \
        composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

    php artisan migrate --seed --force

    php artisan optimize:clear

    set_panel_permissions

    systemctl restart pterodactyl-worker
    systemctl reload nginx

    success "Panel updated successfully."

    pause
}

# ============================================================
# UPDATE WINGS
# ============================================================

update_wings() {

    clear

    step "Updating Wings"

    if [[ ! -f /usr/local/bin/wings ]]; then
        die "Wings is not installed."
    fi

    systemctl stop wings 2>/dev/null || true

    ARCH="$(uname -m)"

    case "$ARCH" in
        x86_64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            die "Unsupported CPU architecture."
            ;;
    esac

    curl -fL \
        --connect-timeout 10 \
        --max-time 300 \
        -o /usr/local/bin/wings.new \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

    chmod u+x /usr/local/bin/wings.new

    mv \
        /usr/local/bin/wings.new \
        /usr/local/bin/wings

    systemctl daemon-reload
    systemctl start wings

    success "Wings updated."

    pause
}

# ============================================================
# BACKUP
# ============================================================

backup_panel() {

    clear

    step "Creating Panel Backup"

    if [[ ! -d "$PANEL_DIR" ]]; then
        die "Pterodactyl Panel is not installed."
    fi

    mkdir -p "$BACKUP_DIR"

    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

    tar -czf \
        "$BACKUP_DIR/panel-${TIMESTAMP}.tar.gz" \
        "$PANEL_DIR/.env" \
        "$PANEL_DIR/storage"

    if command_exists mariadb-dump; then

        mariadb-dump \
            --single-transaction \
            panel \
            > "$BACKUP_DIR/database-${TIMESTAMP}.sql"

    fi

    success "Backup completed."

    echo
    echo "Backup directory:"
    echo "$BACKUP_DIR"

    pause
}

# ============================================================
# REPAIR
# ============================================================

repair_panel() {

    clear

    step "Repairing Pterodactyl Panel"

    if [[ ! -d "$PANEL_DIR" ]]; then
        die "Panel is not installed."
    fi

    cd "$PANEL_DIR"

    php artisan optimize:clear

    chmod -R 755 \
        storage \
        bootstrap/cache

    chown -R www-data:www-data "$PANEL_DIR"

    systemctl restart redis-server
    systemctl restart pterodactyl-worker
    systemctl reload nginx

    success "Panel repair completed."

    pause
}

# ============================================================
# SSL MANAGER
# ============================================================

ssl_manager() {

    clear

    step "SSL Manager"

    read -r -p "Enter domain: " SSL_DOMAIN

    if ! validate_domain_format "$SSL_DOMAIN"; then
        die "Invalid domain."
    fi

    get_public_ip

    if ! check_domain_dns "$SSL_DOMAIN"; then
        die "Domain verification failed."
    fi

    apt_install certbot python3-certbot-nginx

    certbot --nginx \
        -d "$SSL_DOMAIN" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --redirect

    systemctl reload nginx

    success "SSL certificate configured."

    pause
}

# ============================================================
# SERVICE STATUS
# ============================================================

service_status() {

    clear

    step "Pterodactyl Service Status"

    services=(
        nginx
        mariadb
        redis-server
        docker
        pterodactyl-worker
        wings
    )

    for service in "${services[@]}"; do

        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}[RUNNING]${NC} $service"
        else
            echo -e "${RED}[STOPPED]${NC} $service"
        fi

    done

    pause
}

# ============================================================
# LOGS
# ============================================================

view_logs() {

    clear

    step "View Logs"

    echo
    echo "1) Installer Log"
    echo "2) Wings Log"
    echo "3) Panel Worker Log"
    echo "4) Panel Application Logs"
    echo "5) Back"
    echo

    read -r -p "Select [1-5]: " log_choice

    case "$log_choice" in

        1)
            less "$LOG_FILE"
            ;;

        2)
            journalctl -u wings -n 150 --no-pager
            ;;

        3)
            journalctl -u pterodactyl-worker -n 150 --no-pager
            ;;

        4)
            if [[ -d "$PANEL_DIR/storage/logs" ]]; then
                ls -lah "$PANEL_DIR/storage/logs"
                echo
                tail -n 150 "$PANEL_DIR"/storage/logs/*.log 2>/dev/null || true
            else
                warn "Panel logs not found."
            fi
            ;;

        5)
            return
            ;;

        *)
            error "Invalid option."
            ;;

    esac

    pause
}

# ============================================================
# UNINSTALL
# ============================================================

uninstall_pterodactyl() {

    clear

    step "Uninstall / Remove"

    echo -e "${RED}WARNING${NC}"
    echo
    echo "This can remove Pterodactyl Panel and/or Wings."
    echo
    echo "Create a backup before continuing."
    echo

    read -r -p "Type REMOVE to continue: " confirm

    if [[ "$confirm" != "REMOVE" ]]; then
        echo "Cancelled."
        return
    fi

    echo
    echo "1) Remove Panel"
    echo "2) Remove Wings"
    echo "3) Remove Panel + Wings"
    echo "4) Cancel"
    echo

    read -r -p "Select [1-4]: " choice

    case "$choice" in

        1)

            systemctl disable --now pterodactyl-worker 2>/dev/null || true

            rm -f \
                /etc/systemd/system/pterodactyl-worker.service

            rm -f \
                /etc/nginx/sites-enabled/pterodactyl.conf \
                /etc/nginx/sites-available/pterodactyl.conf

            rm -rf "$PANEL_DIR"

            systemctl daemon-reload
            nginx -t && systemctl reload nginx || true

            success "Panel removed."

            ;;

        2)

            systemctl disable --now wings 2>/dev/null || true

            rm -f \
                /etc/systemd/system/wings.service \
                /usr/local/bin/wings

            systemctl daemon-reload

            success "Wings removed."

            ;;

        3)

            systemctl disable --now pterodactyl-worker 2>/dev/null || true
            systemctl disable --now wings 2>/dev/null || true

            rm -f \
                /etc/systemd/system/pterodactyl-worker.service \
                /etc/systemd/system/wings.service

            rm -f \
                /etc/nginx/sites-enabled/pterodactyl.conf \
                /etc/nginx/sites-available/pterodactyl.conf

            rm -f /usr/local/bin/wings

            rm -rf "$PANEL_DIR"

            systemctl daemon-reload

            nginx -t && systemctl reload nginx || true

            success "Panel and Wings removed."

            ;;

        4)
            return
            ;;

        *)
            error "Invalid option."
            ;;

    esac

    pause
}

# ============================================================
# MENU
# ============================================================

show_menu() {

    clear

    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                 MG PTERO INSTALLER                        ║"
    echo "║             Pterodactyl Deployment Manager                ║"
    echo "║                    Version ${VERSION}                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo
    echo -e "${WHITE}Installation${NC}"
    echo "  1) Install Panel"
    echo "  2) Install Wings"
    echo "  3) Install Panel + Wings"
    echo
    echo -e "${WHITE}Management${NC}"
    echo "  4) Update Panel"
    echo "  5) Update Wings"
    echo "  6) Backup Panel + Database"
    echo "  7) Repair Panel"
    echo "  8) SSL Manager"
    echo "  9) Service Status"
    echo " 10) View Logs"
    echo
    echo -e "${RED} 11) Uninstall / Remove${NC}"
    echo " 12) Exit"
    echo
}

# ============================================================
# COMBINED INSTALL
# ============================================================

install_panel_wings() {

    install_panel

    echo
    read -r -p "Install Wings on this server now? [Y/n]: " answer

    case "$answer" in
        n|N|no|NO)
            return
            ;;
        *)
            install_wings
            ;;
    esac
}

# ============================================================
# MAIN
# ============================================================

main() {

    check_root

    while true; do

        show_menu

        read -r -p "Select [1-12]: " choice

        case "$choice" in

            1)
                install_panel
                ;;

            2)
                install_wings
                ;;

            3)
                install_panel_wings
                ;;

            4)
                update_panel
                ;;

            5)
                update_wings
                ;;

            6)
                backup_panel
                ;;

            7)
                repair_panel
                ;;

            8)
                ssl_manager
                ;;

            9)
                service_status
                ;;

            10)
                view_logs
                ;;

            11)
                uninstall_pterodactyl
                ;;

            12)
                echo
                success "Goodbye."
                exit 0
                ;;

            *)
                error "Invalid option. Choose 1-12."
                sleep 1
                ;;

        esac

    done
}

main "$@"
