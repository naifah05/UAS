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

# === Generate certificates ===
CERT_SOURCE_CRT="./${PROJECT_NAME}.pem"
CERT_SOURCE_KEY="./${PROJECT_NAME}-key.pem"
CERT_DEST_CRT="$NGINX_SSL/${DOMAIN}.crt"
CERT_DEST_KEY="$NGINX_SSL/${DOMAIN}.key"

if [[ ! -f "$CERT_SOURCE_CRT" || ! -f "$CERT_SOURCE_KEY" ]]; then
  echo "🔐 Generating SSL certs for $DOMAIN..."
  powershell.exe -Command "mkcert -cert-file ${PROJECT_NAME}.pem -key-file ${PROJECT_NAME}-key.pem ${DOMAIN}"
  sleep 2
fi

# === Copy certs into nginx folder ===
cp "$CERT_SOURCE_CRT" "$CERT_DEST_CRT"
cp "$CERT_SOURCE_KEY" "$CERT_DEST_KEY"
rm -f "$CERT_SOURCE_CRT" "$CERT_SOURCE_KEY"

# === Generate docker-entrypoint.sh ===
sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    "$TEMPLATE_DIR/php/docker-entrypoint.sh.template" > "$PHP_DIR/docker-entrypoint.sh"
chmod +x "$PHP_DIR/docker-entrypoint.sh"

# === Render nginx config ===
sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    "$TEMPLATE_DIR/nginx/default.conf.template" > "$NGINX_DIR/default.conf"

# === Generate Compose .env ===
cat <<EOF > "$ENV_FILE"
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
REPOSITORY_NAME=${PROJECT_NAME}
IMAGE_TAG=latest
COMPOSE_BAKE=true
APP_NAME="${PROJECT_NAME}"
APP_URL="https://${DOMAIN}"
ASSET_URL="https://${DOMAIN}"
EOF

# === .gitignore ===
cat <<EOF > "$GITIGNORE_FILE"
db/data/*
*/db/data/*
../db/data/*
EOF

# === docker-compose.yml ===
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

# === Aliases ===
ZSHRC_FILE="/root/.zshrc"

# Add dcm
grep -q "alias dcm=" "$ZSHRC_FILE" && sed -i '/alias dcm=/d' "$ZSHRC_FILE"
echo "alias dcm='docker exec -it \$(docker ps --filter \"name=_php\" --format \"{{.Names}}\" | head -n 1) art'" >> "$ZSHRC_FILE"
echo "✅ Alias 'dcm' added to $ZSHRC_FILE"

# Add dcd
grep -q "alias dcd=" "$ZSHRC_FILE" && sed -i '/alias dcd=/,/^'\''$/d' "$ZSHRC_FILE"
cat <<'EOF' >> "$ZSHRC_FILE"
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
echo "✅ Alias 'dcd' added to $ZSHRC_FILE"

# === Source .zshrc ===
source "$ZSHRC_FILE"
echo "✅ Alias 'dcd and dcm' added to $ZSHRC_FILE"

# === WSL /etc/hosts ===
if ! grep -q "$DOMAIN" /etc/hosts; then
  echo "$HOST_ENTRY" | sudo tee -a /etc/hosts > /dev/null
  echo "✅ Added $DOMAIN to WSL /etc/hosts"
fi

# === Windows hosts patch ===
WIN_HOSTS_PWS="/mnt/c/Windows/Temp/add_hosts_entry.ps1"
cat <<EOF > "$WIN_HOSTS_PWS"
\$HostsPath = "C:\\Windows\\System32\\drivers\\etc\\hosts"
\$Entry = "$HOST_ENTRY"
\$wasReadOnly = \$false

if ((Get-Item \$HostsPath).Attributes -band [System.IO.FileAttributes]::ReadOnly) {
    attrib -R \$HostsPath
    \$wasReadOnly = \$true
}

if ((Get-Content \$HostsPath) -notcontains \$Entry) {
    Add-Content -Path \$HostsPath -Value \$Entry
}

if (\$wasReadOnly) {
    attrib +R \$HostsPath
}
EOF

echo "🪟 Updating Windows hosts file..."
powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File C:\\Windows\\Temp\\add_hosts_entry.ps1'" \
  && echo "✅ Windows hosts file updated." \
  || echo "⚠️ Please manually add: $HOST_ENTRY"

# === Prompt to start project ===
echo "✅ Project '$PROJECT_NAME' ready at https://$DOMAIN"
read -p "🚀 Start project with Docker Compose now? (y/n): " start_now
if [[ "$start_now" =~ ^[Yy]$ ]]; then
  cd "$ROOT_DIR" && docker-compose up -d --build
fi
