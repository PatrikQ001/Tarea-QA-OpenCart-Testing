#!/bin/sh
set -e

PORT="${PORT:-8080}"

# --- Apache: listen on the port Railway injects -------------------------------
sed -ri "s/^Listen 80$/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/:80>/:${PORT}>/" /etc/apache2/sites-available/000-default.conf

cd /var/www/html

# --- Resolve configuration from environment -----------------------------------
# Railway MySQL plugin exposes MYSQL* vars; fall back to generic DB_* names.
DB_HOST="${MYSQLHOST:-${DB_HOSTNAME:-mysql}}"
DB_PORT="${MYSQLPORT:-${DB_PORT:-3306}}"
DB_USER="${MYSQLUSER:-${DB_USERNAME:-root}}"
DB_PASS="${MYSQLPASSWORD:-${DB_PASSWORD:-}}"
DB_NAME="${MYSQLDATABASE:-${DB_DATABASE:-railway}}"

if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    HTTP_SERVER="https://${RAILWAY_PUBLIC_DOMAIN}/"
else
    HTTP_SERVER="${HTTP_SERVER:-http://localhost:${PORT}/}"
fi

ADMIN_USER="${OC_ADMIN_USER:-admin}"
ADMIN_EMAIL="${OC_ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${OC_ADMIN_PASSWORD:-admin123}"

# --- Write config files every boot (Railway filesystem is ephemeral) ----------
# These must exist and contain valid DB creds for the store to run; the CLI
# installer below only seeds the database, it does not survive restarts.
write_config() {
    cat > /var/www/html/config.php <<EOF
<?php
// APPLICATION
define('APPLICATION', 'Catalog');

// HTTP
define('HTTP_SERVER', '${HTTP_SERVER}');

// DIR
define('DIR_OPENCART', '/var/www/html/');
define('DIR_APPLICATION', DIR_OPENCART . 'catalog/');
define('DIR_SYSTEM', DIR_OPENCART . 'system/');
define('DIR_EXTENSION', DIR_OPENCART . 'extension/');
define('DIR_IMAGE', DIR_OPENCART . 'image/');
define('DIR_STORAGE', DIR_SYSTEM . 'storage/');
define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');
define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');
define('DIR_CONFIG', DIR_SYSTEM . 'config/');
define('DIR_CACHE', DIR_STORAGE . 'cache/');
define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');
define('DIR_LOGS', DIR_STORAGE . 'logs/');
define('DIR_SESSION', DIR_STORAGE . 'session/');
define('DIR_UPLOAD', DIR_STORAGE . 'upload/');

// DB
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '${DB_HOST}');
define('DB_USERNAME', '${DB_USER}');
define('DB_PASSWORD', '${DB_PASS}');
define('DB_DATABASE', '${DB_NAME}');
define('DB_PREFIX', 'oc_');
define('DB_PORT', '${DB_PORT}');

// Cache
define('CACHE_ENGINE', 'file');
EOF

    cat > /var/www/html/admin/config.php <<EOF
<?php
// APPLICATION
define('APPLICATION', 'Admin');

// HTTP
define('HTTP_SERVER', '${HTTP_SERVER}admin/');
define('HTTP_CATALOG', '${HTTP_SERVER}');

// DIR
define('DIR_OPENCART', '/var/www/html/');
define('DIR_APPLICATION', DIR_OPENCART . 'admin/');
define('DIR_SYSTEM', DIR_OPENCART . 'system/');
define('DIR_EXTENSION', DIR_OPENCART . 'extension/');
define('DIR_IMAGE', DIR_OPENCART . 'image/');
define('DIR_STORAGE', DIR_SYSTEM . 'storage/');
define('DIR_CATALOG', DIR_OPENCART . 'catalog/');
define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');
define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');
define('DIR_CONFIG', DIR_SYSTEM . 'config/');
define('DIR_CACHE', DIR_STORAGE . 'cache/');
define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');
define('DIR_LOGS', DIR_STORAGE . 'logs/');
define('DIR_SESSION', DIR_STORAGE . 'session/');
define('DIR_UPLOAD', DIR_STORAGE . 'upload/');

// DB
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '${DB_HOST}');
define('DB_USERNAME', '${DB_USER}');
define('DB_PASSWORD', '${DB_PASS}');
define('DB_DATABASE', '${DB_NAME}');
define('DB_PREFIX', 'oc_');
define('DB_PORT', '${DB_PORT}');

// OpenCart API
define('OPENCART_SERVER', 'https://www.opencart.com/');
EOF

    chmod 666 /var/www/html/config.php /var/www/html/admin/config.php
}

write_config

# --- Wait for the database ----------------------------------------------------
echo "Waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
i=0
until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" --silent 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 40 ]; then
        echo "ERROR: MySQL not reachable after 120s" >&2
        exit 1
    fi
    sleep 3
done

# --- Install only when the schema is missing (idempotent across restarts) ------
TABLE_COUNT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='oc_user';" 2>/dev/null || echo 0)

if [ "$TABLE_COUNT" = "0" ]; then
    echo "Fresh database -> running OpenCart CLI installer..."
    php install/cli_install.php install \
        --username "$ADMIN_USER" \
        --email "$ADMIN_EMAIL" \
        --password "$ADMIN_PASSWORD" \
        --http_server "$HTTP_SERVER" \
        --db_driver mysqli \
        --db_hostname "$DB_HOST" \
        --db_username "$DB_USER" \
        --db_password "$DB_PASS" \
        --db_database "$DB_NAME" \
        --db_port "$DB_PORT" \
        --db_prefix oc_
    # Installer rewrites config.php with the same values; re-pin ours for URL/env.
    write_config
else
    echo "Schema already present -> skipping install."
fi

# OpenCart requires the install directory be removed after setup
rm -rf /var/www/html/install

exec apache2-foreground
