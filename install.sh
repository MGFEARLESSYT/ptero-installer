#!/usr/bin/env bash

set -e

VERSION="4.0.0"
PANEL_DIR="/var/www/pterodactyl"
LOG="/var/log/mg-ptero-installer.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

exec > >(tee -a "$LOG") 2>&1

clear

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                                                      ║"
    echo "║              MG PTERO INSTALLER v4                   ║"
    echo "║                                                      ║"
    echo "║        Pterodactyl Deployment Manager                ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

pause() {
    echo
    read -r -p "Press Enter to continue..."
}

yesno() {
    local q="$1"
    local default="$2"
    local a

    if [[ "$default" == "Y" ]]; then
        read -r -p "$q [Y/n]: " a
        a="${a:-Y}"
    else
        read -r -p "$q [y/N]: " a
        a="${a:-N}"
    fi

    [[ "$a" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ============================================================
# CONFIGURATION WIZARD
# ============================================================

collect_config() {

    banner

    echo
    echo -e "${WHITE}Pterodactyl Installation Configuration${NC}"
    echo
    echo "All questions are optional."
    echo "Press Enter to use the default."
    echo

    # --------------------------------------------------------
    # DOMAIN
    # --------------------------------------------------------

    echo -e "${CYAN}Panel Domain${NC}"
    echo "Leave blank to use the server IP."
    echo

    read -r -p "Panel domain: " PANEL_DOMAIN
    PANEL_DOMAIN="${PANEL_DOMAIN// /}"

    # --------------------------------------------------------
    # SSL
    # --------------------------------------------------------

    if [[ -n "$PANEL_DOMAIN" ]]; then
        if yesno "Install Let's Encrypt SSL automatically?" "Y"; then
            SSL="yes"

            echo
            read -r -p "Let's Encrypt email: " SSL_EMAIL
        else
            SSL="no"
        fi
    else
        SSL="no"
        echo
        echo "No domain supplied."
        echo "SSL will automatically be skipped."
    fi

    # --------------------------------------------------------
    # DATABASE
    # --------------------------------------------------------

    echo
    echo -e "${CYAN}Database Configuration${NC}"

    if yesno "Configure MariaDB automatically?" "Y"; then

        DB_AUTO="yes"

        read -r -p "Database name [panel]: " DB_NAME
        DB_NAME="${DB_NAME:-panel}"

        read -r -p "Database user [pterodactyl]: " DB_USER
        DB_USER="${DB_USER:-pterodactyl}"

        if yesno "Generate database password automatically?" "Y"; then
            DB_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
            echo
            echo "Generated database password:"
            echo "$DB_PASSWORD"
        else
            read -r -s -p "Database password: " DB_PASSWORD
            echo
        fi

    else
        DB_AUTO="no"

        echo
        echo "Existing database will be used."

        read -r -p "Database host [127.0.0.1]: " DB_HOST
        DB_HOST="${DB_HOST:-127.0.0.1}"

        read -r -p "Database port [3306]: " DB_PORT
        DB_PORT="${DB_PORT:-3306}"

        read -r -p "Database name: " DB_NAME
        read -r -p "Database user: " DB_USER

        read -r -s -p "Database password: " DB_PASSWORD
        echo
    fi

    # --------------------------------------------------------
    # FIREWALL
    # --------------------------------------------------------

    echo
    echo -e "${CYAN}Firewall${NC}"

    if yesno "Configure UFW automatically?" "Y"; then
        FIREWALL="yes"
    else
        FIREWALL="no"
    fi

    # --------------------------------------------------------
    # ADMIN
    # --------------------------------------------------------

    echo
    echo -e "${CYAN}Administrator${NC}"

    if yesno "Create administrator account now?" "Y"; then

        CREATE_ADMIN="yes"

        read -r -p "Admin email: " ADMIN_EMAIL
        read -r -p "Admin username: " ADMIN_USERNAME

        while true; do
            read -r -s -p "Admin password: " ADMIN_PASSWORD
            echo

            read -r -s -p "Confirm password: " ADMIN_PASSWORD2
            echo

            if [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD2" && -n "$ADMIN_PASSWORD" ]]; then
                break
            fi

            echo -e "${RED}Passwords do not match.${NC}"
        done

    else
        CREATE_ADMIN="no"
    fi

    # --------------------------------------------------------
    # WINGS
    # --------------------------------------------------------

    echo
    echo -e "${CYAN}Wings${NC}"

    if yesno "Install Wings too?" "N"; then
        INSTALL_WINGS="yes"
    else
        INSTALL_WINGS="no"
    fi

    # --------------------------------------------------------
    # SUMMARY
    # --------------------------------------------------------

    clear
    banner

    echo
    echo -e "${WHITE}Installation Summary${NC}"
    echo
    echo "--------------------------------------------"
    echo "Panel domain : ${PANEL_DOMAIN:-Server IP}"
    echo "SSL          : $SSL"
    echo "Database     : $DB_AUTO"
    echo "Firewall     : $FIREWALL"
    echo "Admin        : $CREATE_ADMIN"
    echo "Wings        : $INSTALL_WINGS"
    echo "--------------------------------------------"
    echo

    if [[ -n "$PANEL_DOMAIN" ]]; then
        echo "Domain: $PANEL_DOMAIN"
    fi

    echo

    if ! yesno "Start installation?" "Y"; then
        echo
        echo "Installation cancelled."
        exit 0
    fi
}

# ============================================================
# OS CHECK
# ============================================================

check_os() {

    if [[ "$EUID" != "0" ]]; then
        echo "Run this installer as root."
        exit 1
    fi

    if [[ ! -f /etc/os-release ]]; then
        echo "Unable to detect OS."
        exit 1
    fi

    source /etc/os-release

    case "$ID:$VERSION_ID" in

        debian:12)
            echo -e "${GREEN}[✓] Debian 12 detected${NC}"
            ;;

        debian:13)
            echo -e "${GREEN}[✓] Debian 13 detected${NC}"
            ;;

        ubuntu:22.04)
            echo -e "${GREEN}[✓] Ubuntu 22.04 detected${NC}"
            ;;

        ubuntu:24.04)
            echo -e "${GREEN}[✓] Ubuntu 24.04 detected${NC}"
            ;;

        *)
            echo -e "${RED}[✗] Unsupported operating system${NC}"
            echo "$PRETTY_NAME"
            exit 1
            ;;
    esac
}

# ============================================================
# DEPENDENCIES
# ============================================================

install_dependencies() {

    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "Installing dependencies"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    apt-get install -y \
        curl \
        wget \
        ca-certificates \
        gnupg \
        git \
        unzip \
        zip \
        tar \
        nginx \
        mariadb-server \
        redis-server \
        cron \
        certbot \
        python3-certbot-nginx \
        software-properties-common

    # PHP repository
    if [[ "$ID" == "ubuntu" ]]; then

        if ! grep -Rqs "ondrej/php" /etc/apt/sources.list.d 2>/dev/null; then
            apt-get install -y software-properties-common
            add-apt-repository -y ppa:ondrej/php
        fi

        apt-get update
    fi

    apt-get install -y \
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
    systemctl enable --now cron

    echo -e "${GREEN}[✓] Dependencies installed${NC}"
}

# ============================================================
# COMPOSER
# ============================================================

install_composer() {

    echo
    echo "Installing Composer..."

    if command -v composer >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] Composer already installed${NC}"
        return
    fi

    curl -fsSL https://getcomposer.org/installer \
        -o /tmp/composer.php

    php /tmp/composer.php \
        --install-dir=/usr/local/bin \
        --filename=composer

    rm -f /tmp/composer.php

    echo -e "${GREEN}[✓] Composer installed${NC}"
}

# ============================================================
# DATABASE
# ============================================================

configure_database() {

    if [[ "$DB_AUTO" != "yes" ]]; then
        return
    fi

    echo
    echo "Configuring MariaDB..."

    mysql <<EOF
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
EOF

    echo -e "${GREEN}[✓] Database configured${NC}"
}

# ============================================================
# DOWNLOAD PANEL
# ============================================================

install_panel_files() {

    echo
    echo "Downloading Pterodactyl..."

    mkdir -p "$PANEL_DIR"

    cd "$PANEL_DIR"

    curl -fL \
        https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
        -o panel.tar.gz

    tar -xzf panel.tar.gz

    rm -f panel.tar.gz

    echo -e "${GREEN}[✓] Panel downloaded${NC}"
}

# ============================================================
# PANEL CONFIG
# ============================================================

configure_panel() {

    cd "$PANEL_DIR"

    cp .env.example .env

    if [[ -n "$PANEL_DOMAIN" ]]; then
        APP_URL="https://$PANEL_DOMAIN"
    else
        SERVER_IP="$(hostname -I | awk '{print $1}')"
        APP_URL="http://$SERVER_IP"
    fi

    php artisan key:generate --force

    sed -i "s|^APP_URL=.*|APP_URL=$APP_URL|" .env

    sed -i "s|^DB_HOST=.*|DB_HOST=${DB_HOST:-127.0.0.1}|" .env
    sed -i "s|^DB_PORT=.*|DB_PORT=${DB_PORT:-3306}|" .env
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" .env

    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

    php artisan migrate --seed --force

    echo -e "${GREEN}[✓] Panel configured${NC}"
}

# ============================================================
# NGINX
# ============================================================

configure_nginx() {

    echo
    echo "Configuring Nginx..."

    rm -f /etc/nginx/sites-enabled/default

    if [[ -n "$PANEL_DOMAIN" ]]; then
        SERVER_NAME="$PANEL_DOMAIN"
    else
        SERVER_NAME="_"
    fi

    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $SERVER_NAME;

    root $PANEL_DIR/public;

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

    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf

    nginx -t

    systemctl restart nginx

    echo -e "${GREEN}[✓] Nginx configured${NC}"
}

# ============================================================
# ADMIN
# ============================================================

create_admin() {

    [[ "$CREATE_ADMIN" != "yes" ]] && return

    cd "$PANEL_DIR"

    php artisan p:user:make \
        --email="$ADMIN_EMAIL" \
        --username="$ADMIN_USERNAME" \
        --password="$ADMIN_PASSWORD" \
        --admin=1

    echo -e "${GREEN}[✓] Administrator created${NC}"
}

# ============================================================
# QUEUE
# ============================================================

configure_queue() {

    cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Requires=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
WorkingDirectory=$PANEL_DIR
ExecStart=/usr/bin/php $PANEL_DIR/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq
}

# ============================================================
# CRON
# ============================================================

configure_cron() {

    cat > /etc/cron.d/pterodactyl <<EOF
* * * * * www-data php $PANEL_DIR/artisan schedule:run >> /dev/null 2>&1
EOF

    chmod 644 /etc/cron.d/pterodactyl
}

# ============================================================
# FIREWALL
# ============================================================

configure_firewall() {

    [[ "$FIREWALL" != "yes" ]] && return

    apt-get install -y ufw

    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp

    ufw --force enable

    echo -e "${GREEN}[✓] Firewall configured${NC}"
}

# ============================================================
# DNS
# ============================================================

dns_check() {

    [[ -z "$PANEL_DOMAIN" ]] && return 1

    echo
    echo "Checking DNS..."

    SERVER_IP="$(curl -4 -fsSL https://api.ipify.org)"

    DNS_IP="$(getent ahostsv4 "$PANEL_DOMAIN" \
        | awk '{print $1}' \
        | sort -u \
        | head -1)"

    echo "Server IP : $SERVER_IP"
    echo "DNS IP    : $DNS_IP"

    if [[ "$SERVER_IP" == "$DNS_IP" ]]; then
        echo -e "${GREEN}[✓] DNS points to this server${NC}"
        return 0
    fi

    echo -e "${YELLOW}[!] DNS does not point to this server${NC}"
    return 1
}

# ============================================================
# SSL
# ============================================================

configure_ssl() {

    [[ "$SSL" != "yes" ]] && return
    [[ -z "$PANEL_DOMAIN" ]] && return

    echo
    echo "Checking DNS before Certbot..."

    if ! dns_check; then
        echo
        echo "SSL skipped because DNS is not pointing here."
        return
    fi

    echo
    echo "Generating SSL certificate..."

    if certbot --nginx \
        -d "$PANEL_DOMAIN" \
        --email "$SSL_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --redirect \
        --non-interactive; then

        echo -e "${GREEN}[✓] SSL certificate installed${NC}"

    else

        echo -e "${RED}[✗] Certbot failed${NC}"
        echo "Check:"
        echo "/var/log/letsencrypt/letsencrypt.log"

    fi
}

# ============================================================
# PERMISSIONS
# ============================================================

fix_permissions() {

    chown -R www-data:www-data "$PANEL_DIR"

    chmod -R 755 \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/bootstrap/cache"
}

# ============================================================
# WINGS
# ============================================================

install_wings() {

    [[ "$INSTALL_WINGS" != "yes" ]] && return

    echo
    echo "Installing Wings..."

    curl -fsSL https://get.docker.com | sh

    mkdir -p /etc/pterodactyl

    ARCH="$(uname -m)"

    case "$ARCH" in
        x86_64)
            WINGS_ARCH="amd64"
            ;;
        aarch64)
            WINGS_ARCH="arm64"
            ;;
        *)
            echo "Unsupported architecture."
            return
            ;;
    esac

    curl -fL \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}" \
        -o /usr/local/bin/wings

    chmod +x /usr/local/bin/wings

    cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wings

    echo -e "${GREEN}[✓] Wings installed${NC}"
    echo
    echo "Create your node in the Pterodactyl Panel."
    echo "Then place its configuration at:"
    echo
    echo "/etc/pterodactyl/config.yml"
    echo
    echo "After that run:"
    echo
    echo "systemctl start wings"
}

# ============================================================
# INSTALL EVERYTHING
# ============================================================

install_all() {

    check_os

    install_dependencies
    install_composer

    configure_database

    install_panel_files
    configure_panel

    configure_nginx
    configure_queue
    configure_cron

    create_admin
    fix_permissions
    configure_firewall

    configure_ssl

    install_wings

    systemctl restart nginx
    systemctl restart php8.3-fpm
    systemctl restart redis-server
    systemctl restart pteroq

    echo
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              INSTALLATION COMPLETE                   ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [[ -n "$PANEL_DOMAIN" ]]; then
        echo "Panel: https://$PANEL_DOMAIN"
    else
        echo "Panel: http://$(hostname -I | awk '{print $1}')"
    fi

    echo
    echo "Panel directory:"
    echo "$PANEL_DIR"

    echo
    echo "Installer log:"
    echo "$LOG"

    pause
}

# ============================================================
# MENU
# ============================================================

menu() {

    while true; do

        banner

        echo "Installation"
        echo "  1) Install Panel"
        echo "  2) Install Wings"
        echo "  3) Install Panel + Wings"
        echo
        echo "Management"
        echo "  4) Update Panel"
        echo "  5) Update Wings"
        echo "  6) Backup"
        echo "  7) Repair"
        echo "  8) SSL Manager"
        echo "  9) Service Status"
        echo " 10) View Logs"
        echo
        echo -e "${RED} 11) Uninstall${NC}"
        echo " 12) Exit"
        echo

        read -r -p "Select [1-12]: " choice

        case "$choice" in

            1)
                collect_config
                install_all
                ;;

            2)
                install_wings
                pause
                ;;

            3)
                collect_config
                INSTALL_WINGS="yes"
                install_all
                ;;

            4)
                echo "Panel update selected."
                pause
                ;;

            5)
                echo "Wings update selected."
                pause
                ;;

            6)
                echo "Backup selected."
                pause
                ;;

            7)
                echo "Repair selected."
                pause
                ;;

            8)
                echo "SSL Manager selected."
                pause
                ;;

            9)
                systemctl --no-pager --type=service \
                    --state=running
                pause
                ;;

            10)
                tail -100 "$LOG"
                pause
                ;;

            11)
                echo "Uninstall selected."
                pause
                ;;

            12)
                exit 0
                ;;

            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac
    done
}

menu
