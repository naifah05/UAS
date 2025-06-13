#!/bin/bash

PROJECT_NAME="$1"

if [ -z "$PROJECT_NAME" ]; then
  echo "❌ Please provide a project name: ./script.sh myproject"
  exit 1
fi

# === Setup Paths ===
ROOT_DIR="/root/perkuliahan/$PROJECT_NAME"
TEMPLATE_DIR="./template"
DB_DIR="$ROOT_DIR/db/conf.d"
NGINX_DIR="$ROOT_DIR/nginx"
NGINX_SSL="$NGINX_DIR/ssl"
PHP_DIR="$ROOT_DIR/php"
SRC_DIR="$ROOT_DIR/src"
DOMAIN="${PROJECT_NAME}.test"
ENV_FILE="$ROOT_DIR/.env"
GITIGNORE_FILE="$ROOT_DIR/.gitignore"
HOST_ENTRY="127.0.0.1 $DOMAIN"

echo "📁 Creating folder structure for '$PROJECT_NAME'..."
mkdir -p "$DB_DIR" "$NGINX_SSL" "$PHP_DIR" "$SRC_DIR"

# === Copy template files ===
cp "$TEMPLATE_DIR/db/my.cnf" "$DB_DIR/"
cp "$TEMPLATE_DIR/nginx/Dockerfile" "$NGINX_DIR/"
cp "$TEMPLATE_DIR/php/Dockerfile" "$PHP_DIR/"
cp "$TEMPLATE_DIR/php/www.conf" "$PHP_DIR/"
cp "$TEMPLATE_DIR/php/local.ini" "$PHP_DIR/"

# === Check for Chocolatey and install if needed ===
echo "🔍 Checking for Chocolatey..."
if ! powershell.exe -Command "Get-Command choco" &> /dev/null; then
  echo "❌ Chocolatey is not installed."
  read -p "📦 Do you want to install Chocolatey? (y/n): " install_choco
  if [[ "$install_choco" == [Yy] ]]; then
    echo "🚀 Installing Chocolatey..."
    powershell.exe -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; \
      [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; \
      iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    sleep 10
  else
    echo "❌ Cannot continue without Chocolatey. Please install manually: https://chocolatey.org/install"
    exit 1
  fi
fi

# === Check for mkcert and install if needed ===
echo "🔍 Checking for mkcert..."
if ! powershell.exe -Command "Get-Command mkcert" &> /dev/null; then
  echo "❌ mkcert not found."
  read -p "📦 Do you want to install mkcert using Chocolatey? (y/n): " install_mkcert
  if [[ "$install_mkcert" == [Yy] ]]; then
    powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command \"choco install mkcert -y\"'"
    echo "⏳ Waiting for mkcert installation to complete..."
    sleep 10
  else
    echo "❌ mkcert is required. Install manually: https://github.com/FiloSottile/mkcert"
    exit 1
  fi
fi

# === Trust mkcert local CA if not already trusted ===
echo "🔐 Running 'mkcert -install' to trust local CA..."
powershell.exe -Command "mkcert -install"
sleep 2

# === Generate cert if not exist ===
CERT_SOURCE_CRT="./${PROJECT_NAME}.pem"
CERT_SOURCE_KEY="./${PROJECT_NAME}-key.pem"
CERT_DEST_CRT="$NGINX_SSL/${DOMAIN}.crt"
CERT_DEST_KEY="$NGINX_SSL/${DOMAIN}.key"

if [[ ! -f "$CERT_SOURCE_CRT" || ! -f "$CERT_SOURCE_KEY" ]]; then
  echo "🔐 Generating SSL cert with mkcert for $DOMAIN..."
  powershell.exe -Command "mkcert -cert-file ${PROJECT_NAME}.pem -key-file ${PROJECT_NAME}-key.pem ${DOMAIN}"
  sleep 2
fi

# === Copy certs to nginx/ssl ===
echo "📄 Copying certs to $NGINX_SSL..."
cp "$CERT_SOURCE_CRT" "$CERT_DEST_CRT"
cp "$CERT_SOURCE_KEY" "$CERT_DEST_KEY"

# === Clean up root certs ===
rm -f "$CERT_SOURCE_CRT" "$CERT_SOURCE_KEY"

# === Generate docker-entrypoint.sh ===
ENTRYPOINT_TEMPLATE="$TEMPLATE_DIR/php/docker-entrypoint.sh.template"
ENTRYPOINT_TARGET="$PHP_DIR/docker-entrypoint.sh"
sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    "$ENTRYPOINT_TEMPLATE" > "$ENTRYPOINT_TARGET"
chmod +x "$ENTRYPOINT_TARGET"

# === Render nginx/default.conf ===
DEFAULT_TEMPLATE="$TEMPLATE_DIR/nginx/default.conf.template"
DEFAULT_OUTPUT="$NGINX_DIR/default.conf"
sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    "$DEFAULT_TEMPLATE" > "$DEFAULT_OUTPUT"

# === Create Compose .env ===
cat <<EOF > "$ROOT_DIR/.env"
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
REPOSITORY_NAME=${PROJECT_NAME}
IMAGE_TAG=latest
COMPOSE_BAKE=true
APP_NAME="${PROJECT_NAME}"
APP_URL="https://${DOMAIN}"
ASSET_URL="https://${DOMAIN}"
EOF

# === Create .gitignore ===
cat <<EOF > "$ROOT_DIR/.gitignore"
db/data/*
*/db/data/*
../db/data/*
EOF

# === Create docker-compose.yml ===
cat <<EOF > "$ROOT_DIR/docker-compose.yml"
services:
  php:
    build:
      context: ./php
    container_name: ${PROJECT_NAME}_php
    volumes:
      - ./src:/var/www/html
    environment:
      - PROJECT_NAME=${PROJECT_NAME}
    depends_on:
      - db

  nginx:
    build:
      context: ./nginx
    container_name: ${PROJECT_NAME}_nginx
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./src:/var/www/html
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - php

  db:
    image: mariadb:10.11
    container_name: ${PROJECT_NAME}_db
    ports:
      - "13306:3306"
    environment:
      MYSQL_DATABASE: $PROJECT_NAME
      MYSQL_ROOT_PASSWORD: p455w0rd
    volumes:
      - ./db/conf.d:/etc/mysql/conf.d
      - ./db/data:/var/lib/mysql
EOF

echo "✅ docker-compose.yml created."

# === Add dcm alias ===
ALIAS_CMD="alias dcm='docker exec -it \$(docker ps --filter \"name=_php\" --format \"{{.Names}}\" | head -n 1) art'"
ZSHRC_FILE="/root/.zshrc"

if ! grep -q "alias dcm=" "$ZSHRC_FILE"; then
  echo "$ALIAS_CMD" >> "$ZSHRC_FILE"
  echo "✅ Added 'dcm' alias to $ZSHRC_FILE"
else
  sed -i '/alias dcm=/d' "$ZSHRC_FILE"
  echo "$ALIAS_CMD" >> "$ZSHRC_FILE"
  echo "✅ Updated 'dcm' alias in $ZSHRC_FILE"
fi

# === Add dcd alias ===
ZSHRC_FILE="/root/.zshrc"

# Escape the alias command for insertion
ALIAS_CMD=$(cat <<'EOF'
alias dcd='
  PROJECT=$(docker ps --format "{{.Names}}" | grep _php | cut -d"_" -f1)
  if [ -n "$PROJECT" ]; then
    echo "🔻 Stopping containers for $PROJECT..."
    docker compose -p "$PROJECT" down
  else
    echo "❌ Could not detect project name."
  fi
'
EOF
)

if ! grep -q "alias dcd=" "$ZSHRC_FILE"; then
  echo "$ALIAS_CMD" >> "$ZSHRC_FILE"
  echo "✅ Added 'dcd' alias to $ZSHRC_FILE"
else
  sed -i '/alias dcd=/,/^'\''$/d' "$ZSHRC_FILE"
  echo "$ALIAS_CMD" >> "$ZSHRC_FILE"
  echo "✅ Updated 'dcd' alias in $ZSHRC_FILE"
fi

# === Update Linux /etc/hosts ===
if ! grep -q "$DOMAIN" /etc/hosts; then
  echo "$HOST_ENTRY" | sudo tee -a /etc/hosts > /dev/null
  echo "✅ Added $DOMAIN to WSL /etc/hosts"
fi

# === Update Windows hosts file safely ===
WIN_HOSTS_SCRIPT_WIN_PATH="C:\\Windows\\Temp\\add_hosts_entry.ps1"
WIN_HOSTS_SCRIPT_UNIX_PATH="/mnt/c/Windows/Temp/add_hosts_entry.ps1"

cat <<EOF > "$WIN_HOSTS_SCRIPT_UNIX_PATH"
\$HostsPath = "C:\\Windows\\System32\\drivers\\etc\\hosts"
\$Entry = "$HOST_ENTRY"
\$wasReadOnly = \$false

# Remove read-only attribute if set
if ((Get-Item \$HostsPath).Attributes -band [System.IO.FileAttributes]::ReadOnly) {
    Write-Host "🔓 Removing read-only attribute from hosts file..."
    attrib -R \$HostsPath
    \$wasReadOnly = \$true
}

# Append entry if not already present
if ((Get-Content \$HostsPath) -notcontains \$Entry) {
    Write-Host "➕ Adding host entry..."
    Add-Content -Path \$HostsPath -Value \$Entry
    Write-Host "✅ Host entry added."
} else {
    Write-Host "ℹ️ Host entry already exists."
}

# Restore read-only attribute
if (\$wasReadOnly) {
    Write-Host "🔒 Restoring read-only attribute..."
    attrib +R \$HostsPath
    Write-Host "✅ Read-only attribute restored."
}
EOF

echo "🪟 Attempting to add $DOMAIN to Windows hosts file..."
powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File $WIN_HOSTS_SCRIPT_WIN_PATH'" \
  && echo "✅ Windows hosts file updated." \
  || echo "⚠️ Please manually add: $HOST_ENTRY"


# === Done ===
echo "✅ Project '$PROJECT_NAME' is ready at https://${DOMAIN}"
read -p "🚀 Start project now with Docker Compose? (y/n): " start_now
if [[ "$start_now" == [Yy] ]]; then
  cd "$ROOT_DIR" && docker-compose up -d --build -y
fi
