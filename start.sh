#!/bin/bash
set -euo pipefail

PROJECT_NAME="$1"
if [ -z "$PROJECT_NAME" ]; then
  echo "❌ Please provide a project name: ./start.sh myproject"
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
ZSHRC_FILE="$HOME/.zshrc"

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
    healthcheck:
      test: ["CMD-SHELL", "php artisan --version"]
      interval: 10s
      timeout: 10s
      retries: 5
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
    healthcheck:
      test: ["CMD-SHELL", "curl -k -fsSL https://${DOMAIN} || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
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
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
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

# === Cleaning up Docker ===
CLEANUP_FLAG="$SCRIPT_DIR/.docker_cleanup_done"
if [ ! -f "$CLEANUP_FLAG" ]; then
  echo "🧹 Running initial docker-cleanup.sh..."
  zsh "$SCRIPT_DIR/docker-cleanup.sh" && touch "$CLEANUP_FLAG" && echo "✅ Cleanup completed." || echo "⚠️ docker-cleanup.sh failed."
else
  echo "ℹ️ Cleanup already run, skipping."
fi

# === Add Aliases/Functions to .zshrc ===
echo "🔗 Updating functions and aliases in $ZSHRC_FILE..."
sed -i '/# === START ===/,/# === END ===/d' "$ZSHRC_FILE"

cat <<'EOF' >> "$ZSHRC_FILE"
# === START ===
unalias dcr 2>/dev/null
dcr() {
  local NAME="$1"
  if [ -z "$NAME" ]; then
    echo "❌ Usage: dcr <ModelName>"
    return 1
  fi

  local CONTAINER=$(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1)
  if [ -z "$CONTAINER" ]; then
    echo "❌ No PHP container found."
    return 1
  fi

  local NAME_SNAKE=$(echo "$NAME" | sed -E 's/([a-z])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')
  local NAME_PLURAL="${NAME_SNAKE}s"

  echo "🗑 Removing $NAME files from container: $CONTAINER"
  docker exec "$CONTAINER" bash -c "rm -f app/Models/$NAME.php"
  docker exec "$CONTAINER" bash -c "rm -f app/Http/Controllers/${NAME}Controller.php"
  docker exec "$CONTAINER" bash -c "rm -f database/seeders/${NAME}Seeder.php"
  docker exec "$CONTAINER" bash -c "find database/migrations -type f -name '*create_${NAME_PLURAL}_table*.php' -delete"
  docker exec "$CONTAINER" bash -c "rm -rf app/Filament/Admin/Resources/${NAME}*"
  docker exec "$CONTAINER" bash -c "rm -f app/Policies/${NAME}Policy.php"
  echo "✅ Done Remove: $NAME"
}
unalias dcm 2>/dev/null
dcm() {
  if [ -z "$1" ]; then
    echo "❌ Usage: dcm <ModelName>"
    return 1
  fi
  local CONTAINER=$(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1)
  if [ -z "$CONTAINER" ]; then
    echo "❌ PHP container not found."
    return 1
  fi
  local NAME="$1"
  docker exec -it "$CONTAINER" art make:model "$NAME" -msc
  docker exec -it "$CONTAINER" art make:filament-resource "$NAME" --generate
  echo "✅ $NAME scaffolded with Filament."
}
unalias dcv 2>/dev/null
dcv() {
  if [ -z "$1" ]; then
    echo "❌ Usage: dcm <ModelName>"
    return 1
  fi
  local CONTAINER=$(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1)
  if [ -z "$CONTAINER" ]; then
    echo "❌ PHP container not found."
    return 1
  fi
  local NAME="$1"
  docker exec -it "$CONTAINER" art make:filament-resource "$NAME" --generate
  echo "✅ $NAME resource with Filament."
}
unalias dcp 2>/dev/null
dcp() {
  if [ $# -eq 0 ]; then
    echo "❌ Usage: dcp your commit message"
    return 1
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "⚠️ Warning: You have uncommitted changes."
  fi
  git add .
  git commit -m "$*"
  git push -u origin main
  echo "✅ Changes pushed to origin/main."
}
unalias dcd 2>/dev/null
dcd() {
  PROJECT=$(docker ps --format "{{.Names}}" | grep _php | cut -d"_" -f1)
  if [ -n "$PROJECT" ]; then
    echo "🔻 Stopping containers for $PROJECT..."
    docker compose -p "$PROJECT" down
  else
    echo "❌ Could not detect project name."
  fi
}
unalias pip 2>/dev/null
pip() {
  if [[ "$1" == "install" ]]; then
    command pip install --break-system-packages "${@:2}"
  else
    command pip "$@"
  fi
}
unalias pip3 2>/dev/null
pip3() {
  if [[ "$1" == "install" ]]; then
    command pip3 install --break-system-packages "${@:2}"
  else
    command pip3 "$@"
  fi
}
unalias start 2>/dev/null
alias start='cd /root/boilerplate && ./start.sh'
unalias gc 2>/dev/null
gclone() {
  local user=$1
  local repo=$2
  local ssh_url="git@github.com:${user}/${repo}.git"
  local https_url="https://github.com/${user}/${repo}.git"

  echo "🛠️ Trying SSH clone: $ssh_url"
  if git clone "$ssh_url"; then
    echo "✅ Cloned via SSH"
  else
    echo "⚠️ SSH failed, falling back to HTTPS..."
    git clone "$https_url" && echo "✅ Cloned via HTTPS"
  fi
}
alias gc=gclone
unalias dcu 2>/dev/null
alias dcu='docker compose up -d'
unalias dci 2>/dev/null
alias dci='docker exec -it $(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1) art project:init'
unalias dca 2>/dev/null
alias dca='docker exec -it $(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1) art'
# === END ===
EOF

# === Update WSL /etc/hosts ===
if ! grep -q "$DOMAIN" /etc/hosts; then
  echo "$HOST_ENTRY" | sudo tee -a /etc/hosts > /dev/null
  echo "✅ Added $DOMAIN to WSL /etc/hosts"
fi

# === Patch Windows hosts file ===
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
powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File C:\\Windows\\Temp\\add_hosts_entry.ps1'" \
  && echo "✅ Windows hosts file updated." || echo "⚠️ Please manually add: $HOST_ENTRY"

# === Prompt to Start ===
echo "✅ Project '$PROJECT_NAME' ready at https://$DOMAIN"
read -p "🚀 Start project with Docker Compose now? (y/n): " start_now
if [[ "$start_now" =~ ^[Yy]$ ]]; then
  cd "$ROOT_DIR" && docker compose up -d --build

  echo "⏳ Waiting for containers to become healthy..."

  # Wait for all expected containers
  containers=("php" "nginx" "db")
  for service in "${containers[@]}"; do
    container_name="${PROJECT_NAME}_${service}"

    echo "🔍 Waiting for $container_name..."
    while true; do
      status=$(docker inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "starting")
      if [[ "$status" == "healthy" || "$status" == "running" ]]; then
        echo "✅ $container_name is $status."
        break
      else
        sleep 1
      fi
    done
  done

  echo "🚀 All containers are up and healthy!"
fi

# === GitHub Repo Creation ===
echo "🌐 Creating GitHub repository..."
if [ ! -f "$SCRIPT_DIR/.github-user" ]; then
  read -p "👤 Enter your GitHub username: " GITHUB_USER
  echo "$GITHUB_USER" > "$SCRIPT_DIR/.github-user"
else
  GITHUB_USER=$(<"$SCRIPT_DIR/.github-user")
fi

if [ ! -f "$SCRIPT_DIR/.github-token" ]; then
  read -s -p "🔑 Enter your GitHub token: " GITHUB_TOKEN
  echo
  echo "$GITHUB_TOKEN" > "$SCRIPT_DIR/.github-token"
else
  GITHUB_TOKEN=$(<"$SCRIPT_DIR/.github-token")
fi

REPO_NAME="${PROJECT_NAME}-$(date +%Y)"
API_URL="https://api.github.com/user/repos"
REPO_PAYLOAD=$(cat <<EOF
{
  "name": "$REPO_NAME",
  "private": false
}
EOF
)

RESPONSE=$(curl -s -w "\n%{http_code}" -u "$GITHUB_USER:$GITHUB_TOKEN" \
  -X POST "$API_URL" \
  -H "Accept: application/vnd.github+json" \
  -d "$REPO_PAYLOAD")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n1)

if [ "$STATUS" = "201" ]; then
  echo "✅ GitHub repository '$REPO_NAME' created."
  GITHUB_SSH="git@github.com:$GITHUB_USER/$REPO_NAME.git"
elif [ "$STATUS" = "422" ]; then
  echo "⚠️ Repo exists or invalid. Proceeding..."
  GITHUB_SSH="git@github.com:$GITHUB_USER/$REPO_NAME.git"
else
  echo "❌ GitHub API failed: $BODY"
  GITHUB_SSH=""
fi

if [ -n "$GITHUB_SSH" ]; then
  echo "🔧 Initializing Git..."
  cd "$ROOT_DIR"
  git init
  git remote remove origin 2>/dev/null || true
  git remote add origin "$GITHUB_SSH"
  git add .
  git commit -m "🔥 fresh from the oven"
  git branch -M main
  git push -u origin main && echo "✅ Project pushed to GitHub." || echo "⚠️ Failed to push."
fi

# === Launch VS Code ===
echo "🧠 Opening in VS Code..."
code .

# === Reload ZSH if inside ZSH ===
if [ "${ZSH_VERSION:-}" ]; then
  echo "🔄 Reloading $ZSHRC_FILE..."
  source "$ZSHRC_FILE"
else
  echo "🔁 Switching to Zsh..."
  echo "🎉 All done! Project '$PROJECT_NAME' is ready at $ROOT_DIR"
  echo "🚀 You can now start developing your project!"
  exec zsh
fi

# === End of Script ===
