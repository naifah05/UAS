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

# === Ensure mkcert SSL certs exist or generate them ===
CERT_SOURCE_CRT="./${PROJECT_NAME}.pem"
CERT_SOURCE_KEY="./${PROJECT_NAME}-key.pem"
CERT_DEST_CRT="$NGINX_SSL/${DOMAIN}.crt"
CERT_DEST_KEY="$NGINX_SSL/${DOMAIN}.key"

if [[ ! -f "$CERT_SOURCE_CRT" || ! -f "$CERT_SOURCE_KEY" ]]; then
  echo "🛠️ SSL certificates (.pem) not found. Attempting to generate with mkcert via PowerShell..."
  powershell.exe -Command "mkcert -cert-file ${PROJECT_NAME}.pem -key-file ${PROJECT_NAME}-key.pem ${DOMAIN}"

  sleep 2

  if [[ ! -f "$CERT_SOURCE_CRT" || ! -f "$CERT_SOURCE_KEY" ]]; then
    echo "❌ Failed to generate SSL certificates using mkcert."
    echo "👉 Please install mkcert on Windows and trust the root CA."
    echo "👉 Or manually run: mkcert -cert-file ${PROJECT_NAME}.pem -key-file ${PROJECT_NAME}-key.pem ${DOMAIN}"
    exit 1
  fi
fi

# === Copy certs to nginx/ssl ===
echo "🔐 Copying mkcert .pem files into nginx/ssl/ as .crt and .key..."
cp "$CERT_SOURCE_CRT" "$CERT_DEST_CRT"
cp "$CERT_SOURCE_KEY" "$CERT_DEST_KEY"
echo "✅ SSL files copied to $NGINX_SSL"

# === Remove cert.pem and key.pem if they exist in the root directory ===
echo "🔐 Copying mkcert .pem files into nginx/ssl/ as .crt and .key..."
if [[ -f "$CERT_SOURCE_CRT" ]]; then
  echo "🗑️ Removing $CERT_SOURCE_CRT from root directory..."
  rm -f "$CERT_SOURCE_CRT"
fi
if [[ -f "$CERT_SOURCE_KEY" ]]; then
  echo "🗑️ Removing $CERT_SOURCE_KEY from root directory..."
  rm -f "$CERT_SOURCE_KEY"
fi
echo "✅ SSL files Removed from root directory."

# === Render docker-entrypoint.sh ===
ENTRYPOINT_TEMPLATE="$TEMPLATE_DIR/php/docker-entrypoint.sh.template"
ENTRYPOINT_TARGET="$PHP_DIR/docker-entrypoint.sh"
echo "📝 Generating docker-entrypoint.sh with project name '$PROJECT_NAME'..."
sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    "$ENTRYPOINT_TEMPLATE" > "$ENTRYPOINT_TARGET"
chmod +x "$ENTRYPOINT_TARGET"

# === Render nginx/default.conf from template ===
DEFAULT_TEMPLATE="$TEMPLATE_DIR/nginx/default.conf.template"
DEFAULT_OUTPUT="$NGINX_DIR/default.conf"
echo "📝 Generating nginx/default.conf from template..."
sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    "$DEFAULT_TEMPLATE" > "$DEFAULT_OUTPUT"

# === Create .env for Docker Compose ===
COMPOSE_ENV_FILE="$ROOT_DIR/.env"
echo "📝 Generating Compose .env at $COMPOSE_ENV_FILE..."
cat <<EOF > "$COMPOSE_ENV_FILE"
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
REPOSITORY_NAME=${PROJECT_NAME}
IMAGE_TAG=latest
COMPOSE_BAKE=true
APP_NAME="${PROJECT_NAME}"
APP_URL="https://${DOMAIN}"
ASSET_URL="https://${DOMAIN}"
EOF

# === Create .gitignore for Database ===
GITIGNORE_FILE="$ROOT_DIR/.gitignore"
echo "📝 Generating ,gitignore at $GITIGNORE_FILE..."
cat <<EOF > "$GITIGNORE_FILE"
db/data/*
*/db/data/*
../db/data/*
#src/.env
#*/src/.env
EOF

# === Create docker-compose.yml ===
echo "📝 Creating docker-compose.yml..."
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

# === Add dcm alias to shell config ===
ALIAS_CMD="alias dcm='docker exec -it \$(docker ps --filter \"name=_php\" --format \"{{.Names}}\" | head -n 1) art'"
ZSHRC_FILE="/root/.zshrc"

if ! grep -q "alias dcm=" "$ZSHRC_FILE"; then
  echo "$ALIAS_CMD" >> "$ZSHRC_FILE"
  echo "✅ Added 'dcm' alias to $ZSHRC_FILE"
else
  echo "ℹ️ 'dcm' alias already exists in $ZSHRC_FILE"
  sed -i '/alias dcm=/d' "$ZSHRC_FILE"
  echo "$ALIAS_CMD" >> "$ZSHRC_FILE"
echo "✅ 'dcm' alias has been updated in $ZSHRC_FILE"
fi

# === Update WSL /etc/hosts ===
if ! grep -q "$DOMAIN" /etc/hosts; then
  echo "$HOST_ENTRY" | sudo tee -a /etc/hosts > /dev/null
  echo "✅ Added $DOMAIN to WSL /etc/hosts"
fi

# === Add to Windows hosts file ===
echo "🪟 Attempting to add $DOMAIN to Windows hosts file..."
powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command \"Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value \\\"$HOST_ENTRY\\\"\"'" \
  && echo "✅ Added $DOMAIN to Windows hosts file" \
  || echo "⚠️ Please run PowerShell as Administrator and manually add: $HOST_ENTRY"

# === Done ===
echo "✅ Project folder '$PROJECT_NAME' is ready."
echo "📦 Navigate to '$PROJECT_NAME' and run: docker-compose up --build"
read -p "🚀 Do you want to start the project now? (y/n): " start_now
if [[ $start_now == [Yy] ]]; then
  cd "$ROOT_DIR" && docker-compose up -d --build
fi
