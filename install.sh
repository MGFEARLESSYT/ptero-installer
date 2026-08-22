#!/usr/bin/env bash

# ============================================================
# MG PTERO INSTALLER
# Pterodactyl Deployment Manager
# ============================================================

set -o pipefail

VERSION="3.0.0"
PANEL_DIR="/var/www/pterodactyl"
LOG_FILE="/var/log/mg-ptero-installer.log"
PANEL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

pause() {
    echo
    read -r -p "Press Enter to continue..."
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

info() {
    echo -e "${CYAN}[→]${NC} $1"
}

die() {
    error "$1"
    echo
    echo "Log: $LOG_FILE"
    exit 1
}

step() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

ask_yes_no() {
    local question="$1"
    local default="$2"
    local answer

    if [[ "$default" == "Y" ]]; then
        read -r -p "$question [Y/n]: " answer
        answer="${answer:-Y}"
    else
        read -r -p "$question [y/N]: " answer
        answer="${answer:-N}"
    fi

    case "$answer" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this installer as root."
    echo
    echo "Example:"
    echo "sudo bash install.sh"
    exit 1
fi

# ------------------------------------------------------------
# Banner
# ------------------------------------------------------------

banner() {
    clear

    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                                                      ║"
    echo "║              MG PTERO INSTALLER v${VERSION}              ║"
    echo "║          Pterodactyl Deployment Manager              ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${GRAY}Official Pterodactyl release installer${NC}"
    echo -e "${GRAY}Log: ${LOG_FILE}${NC}"
    echo
}

# ------------------------------------------------------------
# OS Detection
# ------------------------------------------------------------

detect_os() {
    step "System Check"

    if [[ ! -f /etc/os-release ]]; then
        die "Unable to detect operating system."
    fi

    . /etc/os-release

    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"

    case "$OS_ID" in
        ubuntu)
            case "$OS_VERSION" in
                22.04|24.04)
                    success "Ubuntu $OS_VERSION supported."
                    ;;
                *)
                    die "Unsupported Ubuntu version: $OS_VERSION"
                    ;;
            esac
            ;;

        debian)
            case "$OS_VERSION" in
                12|13)
                    success "Debian $OS_VERSION supported."
                    ;;
                *)
                    die "Unsupported Debian version: $OS_VERSION"
                    ;;
            esac
            ;;

        *)
            die "Unsupported operating system: $OS_ID $OS_VERSION"
            ;;
    esac

    ARCH="$(dpkg --print-architecture)"

    case "$ARCH" in
        amd64|arm64)
            success "Architecture: $ARCH"
            ;;
        *)
            die "Unsupported architecture: $ARCH"
            ;;
    esac
}

# ------------------------------------------------------------
# Internet check
# ------------------------------------------------------------

check_internet() {
    step "Internet Check"

    if curl -fsSL --connect-timeout 8 https://github.com >/dev/null 2>&1; then
        success "Internet connection available."
    else
        die "Unable to reach GitHub."
    fi
}

# ------------------------------------------------------------
# APT
# ------------------------------------------------------------

apt_update() {
    step "Updating Package Lists"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq || die "apt update failed."

    success "Package lists updated."
}

apt_install() {
    info "Installing required packages..."

    export DEBIAN_FRONTEND=noninteractive

    if apt-get install -y \
        -o Dpkg::Use-Pty=0 \
        "$@" >>"$LOG_FILE" 2>&1; then

        success "Packages installed."
    else
        error "Package installation failed."
        echo "Check: $LOG_FILE"
        return 1
    fi
}

# ------------------------------------------------------------
# Base dependencies
# ------------------------------------------------------------

install_dependencies() {
    step "Installing Dependencies"

    apt_install \
        curl \
        wget \
        ca-certificates \
        gnupg \
        git \
        unzip \
        tar \
        zip \
        cron \
        nginx \
        mariadb-server \
        redis-server \
        software-properties-common \
        lsb-release \
        apt-transport-https

    # PHP repository on Ubuntu
    if [[ "$OS_ID" == "ubuntu" ]]; then
        if ! grep -Rqs "ondrej/php" /etc/apt/sources.list.d 2>/dev/null; then
            info "Adding PHP repository..."

            add-apt-repository -y ppa:ondrej/php \
                >>"$LOG_FILE" 2>&1 || die "Unable to add PHP repository."
        fi
    fi

    apt-get update -qq || die "apt update failed."

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
        php8.3-zip

    systemctl enable --now nginx
    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now php8.3-fpm

    success "Dependencies installed."
}

# ------------------------------------------------------------
# Composer
# ------------------------------------------------------------

install_composer() {
    step "Installing Composer"

    if command_exists composer; then
        success "Composer already installed."
        composer self-update --2 >/dev/null 2>&1 || true
        return
    fi

    php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"

    php /tmp/composer-setup.php \
        --install-dir=/usr/local/bin \
        --filename=composer \
        >>"$LOG_FILE" 2>&1 || die "Composer installation failed."

    rm -f /tmp/composer-setup.php

    chmod +x /usr/local/bin/composer

    success "Composer installed."
}

# ------------------------------------------------------------
# Domain setup
# ------------------------------------------------------------

configure_domain() {
    step "Panel Domain"

    echo
    echo "Enter your panel domain."
    echo
    echo "Examples:"
    echo "  panel.example.com"
    echo "  ptero.example.com"
    echo
    echo "Leave blank to use the server IP."
    echo

    read -r -p "Panel domain: " PANEL_DOMAIN

    PANEL_DOMAIN="${PANEL_DOMAIN// /}"

    if [[ -z "$PANEL_DOMAIN" ]]; then
        PANEL_DOMAIN=""
        warn "No domain supplied."
        warn "Panel will be configured for HTTP/IP access."
        return
    fi

    if [[ ! "$PANEL_DOMAIN" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        warn "Domain format looks invalid."
        warn "Continuing without domain."
        PANEL_DOMAIN=""
        return
    fi

    success "Domain: $PANEL_DOMAIN"
}

# ------------------------------------------------------------
# DNS verification
# ------------------------------------------------------------

check_dns() {
    [[ -z "$PANEL_DOMAIN" ]] && return 1

    step "DNS Verification"

    local server_ip
    local dns_ips

    server_ip="$(curl -4 -fsSL --max-time 10 https://api.ipify.org 2>/dev/null || true)"

    dns_ips="$(getent ahostsv4 "$PANEL_DOMAIN" 2>/dev/null \
        | awk '{print $1}' \
        | sort -u)"

    if [[ -z "$dns_ips" ]]; then
        error "$PANEL_DOMAIN does not resolve."
        return 1
    fi

    echo
    echo "DNS records:"
    echo "$dns_ips"

    echo

    if [[ -n "$server_ip" ]] && echo "$dns_ips" | grep -qx "$server_ip"; then
        success "DNS points to this server."
        return 0
    fi

    warn "Domain resolves, but it does not appear to point to this server."

    if [[ -n "$server_ip" ]]; then
        echo "Server IP: $server_ip"
    fi

    return 1
}

# ------------------------------------------------------------
# Database
# ------------------------------------------------------------

generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

setup_database() {
    step "Database Configuration"

    if ! ask_yes_no "Configure MariaDB automatically?" "Y"; then
        warn "Automatic database setup skipped."
        return
    fi

    DB_NAME="panel"
    DB_USER="pterodactyl"
    DB_PASSWORD="$(generate_password)"

    echo
    read -r -p "Database name [panel]: " input
    [[ -n "$input" ]] && DB_NAME="$input"

    read -r -p "Database username [pterodactyl]: " input
    [[ -n "$input" ]] && DB_USER="$input"

    echo
    echo "Database password:"
    echo "$DB_PASSWORD"
    echo

    if ask_yes_no "Use this generated password?" "Y"; then
        :
    else
        read -r -s -p "Enter database password: " DB_PASSWORD
        echo
    fi

    mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1'
IDENTIFIED BY '${DB_PASSWORD}';

ALTER USER '${DB_USER}'@'127.0.0.1'
IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.*
TO '${DB_USER}'@'127.0.0.1';

FLUSH PRIVILEGES;
SQL

    if [[ $? -ne 0 ]]; then
        die "Database setup failed."
    fi

    success "Database configured."

    echo
    echo "Database:"
    echo "  Name:     $DB_NAME"
    echo "  User:     $DB_USER"
    echo "  Password: $DB_PASSWORD"
}

# ------------------------------------------------------------
# Firewall
# ------------------------------------------------------------

setup_firewall() {
    step "Firewall"

    if ! ask_yes_no "Configure UFW automatically?" "Y"; then
        warn "Firewall configuration skipped."
        return
    fi

    apt_install ufw

    ufw allow 22/tcp >/dev/null
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null

    if ask_yes_no "Enable UFW now?" "Y"; then
        ufw --force enable >/dev/null
        success "UFW enabled."
    else
        warn "UFW installed but not enabled."
    fi
}

# ------------------------------------------------------------
# Download Panel
# ------------------------------------------------------------

download_panel() {
    step "Downloading Pterodactyl"

    mkdir -p "$PANEL_DIR"

    cd "$PANEL_DIR" || die "Unable to enter $PANEL_DIR"

    if [[ -f artisan ]]; then
        warn "Existing Pterodactyl installation detected."
        return
    fi

    info "Downloading latest Pterodactyl release..."

    curl -fL \
        "$PANEL_URL" \
        -o panel.tar.gz \
        || die "Unable to download Pterodactyl."

    tar -xzf panel.tar.gz \
        || die "Unable to extract Pterodactyl."

    rm -f panel.tar.gz

    chmod -R 755 storage bootstrap/cache

    success "Pterodactyl downloaded."
}

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

configure_environment() {
    step "Configuring Panel"

    cd "$PANEL_DIR" || die "Unable to enter panel directory."

    cp -n .env.example .env

    php artisan key:generate --force \
        >>"$LOG_FILE" 2>&1 || die "Unable to generate application key."

    if [[ -n "$PANEL_DOMAIN" ]]; then
        APP_URL="https://$PANEL_DOMAIN"
    else
        SERVER_IP="$(hostname -I | awk '{print $1}')"
        APP_URL="http://$SERVER_IP"
    fi

    if [[ -z "$DB_NAME" ]]; then
        DB_NAME="panel"
    fi

    if [[ -z "$DB_USER" ]]; then
        DB_USER="pterodactyl"
    fi

    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=""
    fi

    php artisan p:environment:setup \
        --author="admin@example.com" \
        --url="$APP_URL" \
        --timezone="UTC" \
        --cache="redis" \
        --session="database" \
        --queue="redis" \
        --redis-host="127.0.0.1" \
        --redis-pass="" \
        --redis-port="6379" \
        --no-interaction \
        >>"$LOG_FILE" 2>&1 || true

    php artisan p:environment:database \
        --host="127.0.0.1" \
        --port="3306" \
        --database="$DB_NAME" \
        --username="$DB_USER" \
        --password="$DB_PASSWORD" \
        --no-interaction \
        >>"$LOG_FILE" 2>&1 || true

    # Make sure important values exist.
    sed -i "s|^APP_URL=.*|APP_URL=$APP_URL|" .env

    sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
    sed -i "s|^DB_PORT=.*|DB_PORT=3306|" .env
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env

    if grep -q "^DB_PASSWORD=" .env; then
        sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" .env
    else
        echo "DB_PASSWORD=$DB_PASSWORD" >> .env
    fi

    success "Panel environment configured."
}

# ------------------------------------------------------------
# Composer dependencies
# ------------------------------------------------------------

install_panel_dependencies() {
    step "Installing Panel Dependencies"

    cd "$PANEL_DIR" || die "Unable to enter panel directory."

    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction \
        >>"$LOG_FILE" 2>&1 \
        || die "Composer installation failed."

    success "Panel dependencies installed."
}

# ------------------------------------------------------------
# Database migrations
# ------------------------------------------------------------

migrate_database() {
    step "Migrating Database"

    cd "$PANEL_DIR" || die "Unable to enter panel directory."

    php artisan migrate --seed --force \
        >>"$LOG_FILE" 2>&1 \
        || die "Database migration failed."

    success "Database migration completed."
}

# ------------------------------------------------------------
# Admin user
# ------------------------------------------------------------

create_admin() {
    step "Administrator Account"

    echo
    echo "You can create the first administrator now."
    echo "You may also skip this and run:"
    echo
    echo "  cd $PANEL_DIR"
    echo "  php artisan p:user:make"
    echo

    if ask_yes_no "Create administrator now?" "Y"; then
        cd "$PANEL_DIR" || return

        php artisan p:user:make
    else
        warn "Administrator creation skipped."
    fi
}

# ------------------------------------------------------------
# Nginx
# ------------------------------------------------------------

configure_nginx() {
    step "Configuring Nginx"

    rm -f /etc/nginx/sites-enabled/default

    if [[ -n "$PANEL_DOMAIN" ]]; then
        SERVER_NAME="$PANEL_DOMAIN"
    else
        SERVER_NAME="_"
    fi

    PHP_SOCKET="/run/php/php8.3-fpm.sock"

    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $SERVER_NAME;

    root $PANEL_DIR/public;

    index index.php;

    client_max_body_size 100m;

    access_log /var/log/nginx/pterodactyl_access.log;
    error_log /var/log/nginx/pterodactyl_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCKET;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -sfn \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf

    nginx -t || die "Nginx configuration test failed."

    systemctl enable nginx
    systemctl restart nginx

    if ! systemctl is-active --quiet nginx; then
        die "Nginx failed to start."
    fi

    success "Nginx configured."
}

# ------------------------------------------------------------
# Queue worker
# ------------------------------------------------------------

configure_queue() {
    step "Configuring Queue Worker"

    cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Requires=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $PANEL_DIR/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq

    if systemctl is-active --quiet pteroq; then
        success "Queue worker running."
    else
        warn "Queue worker failed to start."
    fi
}

# ------------------------------------------------------------
# Cron
# ------------------------------------------------------------

configure_cron() {
    step "Configuring Scheduler"

    cat > /etc/cron.d/pterodactyl <<EOF
* * * * * www-data php $PANEL_DIR/artisan schedule:run >> /dev/null 2>&1
EOF

    chmod 644 /etc/cron.d/pterodactyl

    systemctl restart cron 2>/dev/null || true

    success "Cron configured."
}

# ------------------------------------------------------------
# Permissions
# ------------------------------------------------------------

fix_permissions() {
    step "Setting Permissions"

    chown -R www-data:www-data "$PANEL_DIR"

    chmod -R 755 "$PANEL_DIR/storage"
    chmod -R 755 "$PANEL_DIR/bootstrap/cache"

    success "Permissions fixed."
}

# ------------------------------------------------------------
# SSL
# ------------------------------------------------------------

install_ssl() {
    step "SSL / Certbot"

    if [[ -z "$PANEL_DOMAIN" ]]; then
        warn "No domain configured."
        warn "SSL skipped."
        return
    fi

    if ! check_dns; then
        warn "DNS check failed."
        warn "Certbot will NOT be executed."
        return
    fi

    if ! ask_yes_no "Install Let's Encrypt SSL automatically?" "Y"; then
        warn "SSL installation skipped."
        return
    fi

    apt_install certbot python3-certbot-nginx

    if ! command_exists certbot; then
        error "Certbot is not installed."
        return
    fi

    echo
    read -r -p "Let's Encrypt email: " CERTBOT_EMAIL

    if [[ -z "$CERTBOT_EMAIL" ]]; then
        warn "No email supplied."
        warn "SSL skipped."
        return
    fi

    info "Requesting certificate..."

    if certbot --nginx \
        -d "$PANEL_DOMAIN" \
        --email "$CERTBOT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --redirect \
        --non-interactive; then

        success "SSL certificate installed."
        success "HTTPS enabled."
    else
        error "Certbot failed."
        echo
        echo "Useful commands:"
        echo "  certbot certificates"
        echo "  tail -100 /var/log/letsencrypt/letsencrypt.log"
        echo
    fi
}

# ------------------------------------------------------------
# Full Panel installation
# ------------------------------------------------------------

install_panel() {
    banner

    detect_os
    check_internet
    apt_update

    configure_domain

    install_dependencies
    install_composer

    setup_database
    setup_firewall

    download_panel
    configure_environment
    install_panel_dependencies
    migrate_database

    create_admin

    fix_permissions
    configure_nginx
    configure_queue
    configure_cron

    install_ssl

    success "Pterodactyl Panel installation finished."

    echo
    echo -e "${WHITE}Panel:${NC}"

    if [[ -n "$PANEL_DOMAIN" ]]; then
        echo "https://$PANEL_DOMAIN"
    else
        echo "http://$(hostname -I | awk '{print $1}')"
    fi

    echo
    echo -e "${WHITE}Log:${NC}"
    echo "$LOG_FILE"

    pause
}

# ------------------------------------------------------------
# Wings
# ------------------------------------------------------------

install_wings() {
    banner

    step "Installing Pterodactyl Wings"

    detect_os
    check_internet

    if ! command_exists docker; then
        info "Installing Docker..."

        curl -fsSL https://get.docker.com | sh \
            >>"$LOG_FILE" 2>&1 \
            || die "Docker installation failed."
    fi

    systemctl enable --now docker

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
            die "Unsupported CPU architecture."
            ;;
    esac

    info "Downloading Wings..."

    curl -fL \
        "${WINGS_URL}_${WINGS_ARCH}" \
        -o /usr/local/bin/wings \
        || die "Wings download failed."

    chmod +x /usr/local/bin/wings

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
    echo "Wings configuration is generated from your Panel."
    echo
    echo "Panel → Admin → Nodes → Create Node"
    echo "Then open the node → Configuration."
    echo
    echo "Paste the generated configuration into:"
    echo
    echo "/etc/pterodactyl/config.yml"
    echo

    if [[ -f /etc/pterodactyl/config.yml ]]; then
        systemctl enable --now wings

        if systemctl is-active --quiet wings; then
            success "Wings started."
        else
            warn "Wings configuration exists but Wings did not start."
        fi
    else
        warn "Wings has NOT been started because config.yml does not exist."
    fi

    pause
}

# ------------------------------------------------------------
# Panel + Wings
# ------------------------------------------------------------

install_both() {
    install_panel
    install_wings
}

# ------------------------------------------------------------
# Update Panel
# ------------------------------------------------------------

update_panel() {
    banner

    step "Update Pterodactyl Panel"

    if [[ ! -f "$PANEL_DIR/artisan" ]]; then
        error "Pterodactyl is not installed."
        pause
        return
    fi

    cd "$PANEL_DIR" || return

    php artisan down || true

    cp .env "/root/pterodactyl-env-backup-$(date +%Y%m%d-%H%M%S)" \
        2>/dev/null || true

    info "Downloading latest Panel..."

    curl -fL \
        "$PANEL_URL" \
        -o panel.tar.gz \
        || {
            php artisan up || true
            error "Panel download failed."
            pause
            return
        }

    tar -xzf panel.tar.gz
    rm -f panel.tar.gz

    chmod -R 755 storage bootstrap/cache

    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction \
        >>"$LOG_FILE" 2>&1 \
        || warn "Composer update reported an error."

    php artisan migrate --seed --force \
        >>"$LOG_FILE" 2>&1 \
        || warn "Database migration reported an error."

    php artisan view:clear >>"$LOG_FILE" 2>&1 || true
    php artisan config:clear >>"$LOG_FILE" 2>&1 || true
    php artisan cache:clear >>"$LOG_FILE" 2>&1 || true

    chown -R www-data:www-data "$PANEL_DIR"

    systemctl restart php8.3-fpm
    systemctl restart nginx
    systemctl restart pteroq

    php artisan up || true

    success "Panel update completed."

    pause
}

# ------------------------------------------------------------
# Update Wings
# ------------------------------------------------------------

update_wings() {
    banner

    step "Update Wings"

    if [[ ! -f /usr/local/bin/wings ]]; then
        error "Wings is not installed."
        pause
        return
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
            error "Unsupported architecture."
            pause
            return
            ;;
    esac

    curl -fL \
        "${WINGS_URL}_${WINGS_ARCH}" \
        -o /usr/local/bin/wings \
        || {
            error "Wings download failed."
            systemctl start wings 2>/dev/null || true
            pause
            return
        }

    chmod +x /usr/local/bin/wings

    systemctl daemon-reload
    systemctl enable --now wings

    if systemctl is-active --quiet wings; then
        success "Wings updated."
    else
        warn "Wings is not running."
    fi

    pause
}

# ------------------------------------------------------------
# Backup
# ------------------------------------------------------------

backup_panel() {
    banner

    step "Panel Backup"

    BACKUP_DIR="/root/pterodactyl-backups/$(date +%Y-%m-%d_%H-%M-%S)"

    mkdir -p "$BACKUP_DIR"

    info "Backing up .env..."

    cp "$PANEL_DIR/.env" "$BACKUP_DIR/.env"

    info "Backing up database..."

    DB_NAME="$(grep '^DB_DATABASE=' "$PANEL_DIR/.env" | cut -d= -f2-)"
    DB_USER="$(grep '^DB_USERNAME=' "$PANEL_DIR/.env" | cut -d= -f2-)"
    DB_PASSWORD="$(grep '^DB_PASSWORD=' "$PANEL_DIR/.env" | cut -d= -f2-)"

    if [[ -n "$DB_NAME" ]]; then
        MYSQL_PWD="$DB_PASSWORD" mysqldump \
            -u"$DB_USER" \
            -h127.0.0.1 \
            "$DB_NAME" \
            > "$BACKUP_DIR/database.sql" \
            2>>"$LOG_FILE" \
            || warn "Database backup failed."
    fi

    info "Backing up Panel files..."

    tar -czf "$BACKUP_DIR/panel-files.tar.gz" \
        -C /var/www pterodactyl \
        2>>"$LOG_FILE" \
        || warn "Panel file backup failed."

    success "Backup created:"
    echo "$BACKUP_DIR"

    pause
}

# ------------------------------------------------------------
# Repair
# ------------------------------------------------------------

repair_panel() {
    banner

    step "Repairing Pterodactyl"

    if [[ ! -f "$PANEL_DIR/artisan" ]]; then
        error "Pterodactyl is not installed."
        pause
        return
    fi

    cd "$PANEL_DIR" || return

    info "Fixing permissions..."
    chown -R www-data:www-data "$PANEL_DIR"

    chmod -R 755 storage bootstrap/cache

    info "Installing dependencies..."

    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction \
        >>"$LOG_FILE" 2>&1 \
        || warn "Composer reported an error."

    info "Clearing cache..."

    php artisan optimize:clear \
        >>"$LOG_FILE" 2>&1 \
        || true

    info "Restarting services..."

    systemctl restart php8.3-fpm
    systemctl restart nginx
    systemctl restart redis-server
    systemctl restart pteroq 2>/dev/null || true

    nginx -t \
        && success "Nginx configuration valid." \
        || error "Nginx configuration invalid."

    success "Repair completed."

    pause
}

# ------------------------------------------------------------
# SSL Manager
# ------------------------------------------------------------

ssl_manager() {
    banner

    step "SSL Manager"

    if ! command_exists certbot; then
        info "Installing Certbot..."
        apt_install certbot python3-certbot-nginx
    fi

    echo
    echo "1) Install SSL"
    echo "2) Renew SSL"
    echo "3) List certificates"
    echo "4) Remove certificate"
    echo "5) Back"
    echo

    read -r -p "Select: " ssl_choice

    case "$ssl_choice" in
        1)
            read -r -p "Domain: " domain
            read -r -p "Email: " email

            if [[ -z "$domain" || -z "$email" ]]; then
                error "Domain and email are required."
                pause
                return
            fi

            PANEL_DOMAIN="$domain"

            if check_dns; then
                certbot --nginx \
                    -d "$domain" \
                    --email "$email" \
                    --agree-tos \
                    --no-eff-email \
                    --redirect \
                    --non-interactive
            else
                error "DNS does not point to this server."
            fi
            ;;

        2)
            certbot renew
            ;;

        3)
            certbot certificates
            ;;

        4)
            certbot certificates
            echo
            read -r -p "Certificate name/domain to remove: " domain

            if [[ -n "$domain" ]]; then
                certbot delete --cert-name "$domain"
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

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

service_status() {
    banner

    step "Service Status"

    services=(
        nginx
        mariadb
        redis-server
        php8.3-fpm
        pteroq
        docker
        wings
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
            if systemctl is-active --quiet "$service"; then
                echo -e "${GREEN}[ONLINE]${NC} $service"
            else
                echo -e "${RED}[OFFLINE]${NC} $service"
            fi
        fi
    done

    echo

    if [[ -f "$PANEL_DIR/artisan" ]]; then
        success "Pterodactyl Panel files detected."
    else
        warn "Pterodactyl Panel not detected."
    fi

    if [[ -f /usr/local/bin/wings ]]; then
        success "Wings binary detected."
    else
        warn "Wings binary not detected."
    fi

    pause
}

# ------------------------------------------------------------
# Logs
# ------------------------------------------------------------

view_logs() {
    banner

    step "Logs"

    echo
    echo "1) Installer log"
    echo "2) Queue worker"
    echo "3) Wings"
    echo "4) Nginx error"
    echo "5) Laravel log"
    echo "6) Back"
    echo

    read -r -p "Select: " log_choice

    case "$log_choice" in
        1)
            less "$LOG_FILE"
            ;;

        2)
            journalctl -u pteroq -n 100 --no-pager
            ;;

        3)
            journalctl -u wings -n 100 --no-pager
            ;;

        4)
            tail -100 /var/log/nginx/pterodactyl_error.log 2>/dev/null \
                || echo "Nginx log not found."
            ;;

        5)
            if [[ -f "$PANEL_DIR/storage/logs/laravel.log" ]]; then
                tail -100 "$PANEL_DIR/storage/logs/laravel.log"
            else
                echo "Laravel log not found."
            fi
            ;;

        6)
            return
            ;;

        *)
            error "Invalid option."
            ;;
    esac

    pause
}

# ------------------------------------------------------------
# Uninstall
# ------------------------------------------------------------

uninstall_ptero() {
    banner

    step "Uninstall / Remove"

    echo
    echo -e "${RED}WARNING${NC}"
    echo "This can remove Pterodactyl files, services and configuration."
    echo
    echo "It will NOT automatically delete Docker containers/data."
    echo

    if ! ask_yes_no "Continue with uninstall?" "N"; then
        return
    fi

    systemctl disable --now pteroq 2>/dev/null || true
    systemctl disable --now wings 2>/dev/null || true

    rm -f /etc/systemd/system/pteroq.service
    rm -f /etc/systemd/system/wings.service

    systemctl daemon-reload

    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf

    rm -f /etc/cron.d/pterodactyl

    nginx -t >/dev/null 2>&1 && systemctl restart nginx || true

    if ask_yes_no "Remove /var/www/pterodactyl?" "N"; then
        rm -rf "$PANEL_DIR"
    fi

    if ask_yes_no "Remove Pterodactyl database?" "N"; then
        read -r -p "Database name: " db_name

        if [[ -n "$db_name" ]]; then
            mysql -e "DROP DATABASE IF EXISTS \`$db_name\`;"
        fi
    fi

    success "Pterodactyl removal completed."

    pause
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------

main_menu() {
    while true; do

        banner

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

        read -r -p "Select an option [1-12]: " choice

        case "$choice" in

            1)
                install_panel
                ;;

            2)
                install_wings
                ;;

            3)
                install_both
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
                uninstall_ptero
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

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

main_menu
