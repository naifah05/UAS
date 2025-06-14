#!/bin/bash

# === Combined Script ===

# === Function to Start Project ===
start_project() {
  PROJECT_NAME="$1"
  if [ -z "$PROJECT_NAME" ]; then
    echo "❌ Please provide a project name: ./script.sh start myproject"
    exit 1
  fi

  # === Setup Paths ===
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  cp -a "$TEMPLATE_DIR/src/." "$SRC_DIR/"

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

  # === Cleaning up first ===
  CLEANUP_FLAG="$SCRIPT_DIR/.docker_cleanup_done"
  if [ ! -f "$CLEANUP_FLAG" ]; then
    echo "🧹 Running initial docker-cleanup.sh..."
    zsh "$SCRIPT_DIR/docker-cleanup.sh"
    if [ $? -eq 0 ]; then
      touch "$CLEANUP_FLAG"
      echo "✅ docker-cleanup.sh completed and flagged."
    else
      echo "⚠️ docker-cleanup.sh failed."
    fi
  else
    echo "ℹ️ docker-cleanup.sh already run before, skipping."
  fi

  # === Prompt to start project ===
  echo "✅ Project '$PROJECT_NAME' ready at https://$DOMAIN"
  read -p "🚀 Start project with Docker Compose now? (y/n): " start_now
  if [[ "$start_now" =~ ^[Yy]$ ]]; then
    cd "$ROOT_DIR" && docker-compose up -d --build
  fi

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

  # === GitHub Repo Creation ===
  echo "🌐 Creating GitHub repository via API..."

  REPO_NAME="${PROJECT_NAME}-$(date +%Y%m%d%H%M%S)"
  API_URL="https://api.github.com/user/repos"

  # === Load GitHub User ===
  if [ -f "$SCRIPT_DIR/.github-user" ]; then
    GITHUB_USER=$(<"$SCRIPT_DIR/.github-user")
  else
    echo "❌ GitHub user file not found at $SCRIPT_DIR/.github-user"
    exit 1
  fi

  # === Load GitHub Token ===
  if [ -f "$SCRIPT_DIR/.github-token" ]; then
    GITHUB_TOKEN=$(<"$SCRIPT_DIR/.github-token")
  else
    echo "❌ GitHub token file not found at $SCRIPT_DIR/.github-token"
    exit 1
  fi

  REPO_PAYLOAD=$(cat <<EOF
{
  "name": "$REPO_NAME",
  "private": false
}
EOF
  )

  # Call API and capture both body and status
  RESPONSE=$(curl -s -w "\n%{http_code}" -u "$GITHUB_USER:$GITHUB_TOKEN" \
    -X POST "$API_URL" \
    -H "Accept: application/vnd.github+json" \
    -d "$REPO_PAYLOAD")

  BODY=$(echo "$RESPONSE" | head -n -1)
  STATUS=$(echo "$RESPONSE" | tail -n1)

  if [ "$STATUS" = "201" ]; then
    echo "✅ GitHub repository '$REPO_NAME' created successfully."
    GITHUB_SSH="git@github.com:$GITHUB_USER/$REPO_NAME.git"
  elif [ "$STATUS" = "422" ]; then
    echo "❌ Repository already exists or invalid request."
    if command -v jq >/dev/null; then
      echo "📦 GitHub says: $(echo "$BODY" | jq -r '.errors[0].message')"
    else
      echo "📦 GitHub says: $BODY"
    fi
    GITHUB_SSH="git@github.com:$GITHUB_USER/$REPO_NAME.git"
  else
    echo "❌ Failed to create GitHub repository. HTTP Status: $STATUS"
    echo "🔐 Check your GitHub username/token or if the repo already exists."
    echo "📦 GitHub response: $BODY"
    GITHUB_SSH=""
  fi
  if [ -n "$GITHUB_SSH" ]; then
    echo "🔧 Initializing Git repository..."
    cd "$ROOT_DIR"
    git init
    git add .
    git commit -m "🔥 fresh from the oven"
    git branch -M main
    git remote add origin "$GITHUB_SSH"
    git push -u origin main && echo "✅ Project pushed to GitHub." || echo "❌ Failed to push to GitHub."
  fi

  # === Open VS Code ===
  echo "🧠 Opening project in VS Code..."
  code .
  echo "🎉 Setup complete! Your project '$PROJECT_NAME' is ready to go! $ROOT_DIR"
}

# === Update Zsh Config ===
update_zsh_config() {
  ZSHRC_FILE="/root/.zshrc"

  touch "$ZSHRC_FILE"

  echo "🔗 Updating functions and aliases in $ZSHRC_FILE..."

  # === Remove previously added block ===
  sed -i '/# === START ===/,/# === END ===/d' "$ZSHRC_FILE"

  # === Append updated block ===
  cat <<EOF >> "$ZSHRC_FILE"
# === START ===

start() {
  if [ -z "\$1" ]; then
    echo "❌ Usage: start <project-name>"
    return 1
  fi
  bash "$(dirname "${BASH_SOURCE[0]}")/setup.sh start" "\$1"
}

dcr() {
  local NAME="\$1"
  if [ -z "\$NAME" ]; then
    echo "❌ Usage: dcr <ModelName>"
    return 1
  fi

  local CONTAINER=\$(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1)
  if [ -z "\$CONTAINER" ]; then
    echo "❌ No PHP container found."
    return 1
  fi

  local NAME_SNAKE=\$(echo "\$NAME" | sed -E 's/([a-z])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')
  local NAME_PLURAL="\${NAME_SNAKE}s"

  echo "🗑 Removing \$NAME files in container: \$CONTAINER"

  docker exec "\$CONTAINER" bash -c "rm -f app/Models/\$NAME.php"
  docker exec "\$CONTAINER" bash -c "rm -f app/Http/Controllers/\${NAME}Controller.php"
  docker exec "\$CONTAINER" bash -c "rm -f database/seeders/\${NAME}Seeder.php"
  docker exec "\$CONTAINER" bash -c "find database/migrations -type f -name '*create_\${NAME_PLURAL}_table*.php' -delete"

  echo "✅ Done removing model, controller, seeder, and migration for: \$NAME"
}

dcm() {
  if [ -z "\$1" ]; then
    echo "❌ Usage: dcm <ModelName>"
    return 1
  fi
  local CONTAINER=\$(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1)
  if [ -z "\$CONTAINER" ]; then
    echo "❌ PHP container not found."
    return 1
  fi
  docker exec -it "\$CONTAINER" art make:model "\$1" -msc
}

dcv() {
  if [ -z "\$1" ]; then
    echo "❌ Usage: dcv <ModelName>"
    return 1
  fi
  local CONTAINER=\$(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1)
  if [ -z "\$CONTAINER" ]; then
    echo "❌ PHP container not found."
    return 1
  fi
  docker exec -it "\$CONTAINER" art make:filament-resource "\$1" --generate
}

dcp() {
  if [ \$# -eq 0 ]; then
    echo "❌ Usage: dcp your commit message"
    return 1
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "⚠️ Warning: You have uncommitted changes."
  fi
  git add .
  git commit -m "\$*"
  git push -u origin main
  echo "✅ Changes pushed to origin/main."
}

dcd() {
  PROJECT=\$(docker ps --format "{{.Names}}" | grep _php | cut -d"_" -f1)
  if [ -n "\$PROJECT" ]; then
    echo "🔻 Stopping containers for \$PROJECT..."
    docker compose -p "\$PROJECT" down
  else
    echo "❌ Could not detect project name."
  fi
}

alias dcu='docker compose up -d'
alias dci='docker exec -it \$(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1) art project:init'

# === END ===
EOF

  # === Reload Zsh Config Only If Running Zsh ===
  if [ -n "${ZSH_VERSION:-}" ]; then
    echo "🔄 You're already in Zsh. Sourcing $ZSHRC_FILE..."
    source "$ZSHRC_FILE"
  else
    echo "✅ Aliases written to $ZSHRC_FILE."
    echo "🔁 Open a new Zsh terminal or run: exec zsh"
  fi
}

# === Main Execution ===
if [ "$1" == "start" ]; then
  start_project "$2"
elif [ "$1" == "alias" ]; then
  update_zsh_config
else
  echo "❌ Invalid command. Use 'start <project-name>' or 'alias'."
fi