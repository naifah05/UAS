#!/bin/bash
set -euo pipefail

PROJECT_NAME="$1"
if [ -z "$PROJECT_NAME" ]; then
  echo "❌ Please provide a project name: ./start.sh myproject"
  exit 1
fi

DOMAIN="${PROJECT_NAME}.test"
ROOT_DIR="$HOME/perkuliahan/$PROJECT_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

DB_DIR="$ROOT_DIR/db/conf.d"
NGINX_DIR="$ROOT_DIR/nginx"
NGINX_SSL="$NGINX_DIR/ssl"
PHP_DIR="$ROOT_DIR/php"
SRC_DIR="$ROOT_DIR/src"

mkdir -p "$DB_DIR" "$NGINX_SSL" "$PHP_DIR" "$SRC_DIR"

echo "🔍 Checking prerequisites..."
# === Check and install Docker Desktop ===
if ! command -v docker &>/dev/null; then
  echo "🐳 Installing Docker Desktop..."
  brew install --cask docker
else
  echo "✅ Docker Desktop already installed."
fi
# === Start Docker Desktop if not running ===
if ! pgrep -x "Docker" > /dev/null; then
  echo "🔄 Starting Docker Desktop..."
  open -a Docker
  # Wait for Docker to start
  while ! docker info &>/dev/null; do
    sleep 1
  done
else
  echo "✅ Docker Desktop is already running."
fi
# === Check and install Docker Compose ===
if ! command -v docker-compose &>/dev/null; then
  echo "📦 Installing Docker Compose..."
  brew install docker-compose
else
  echo "✅ Docker Compose already installed."
fi
# === Check and install Homebrew ===
if ! command -v brew &>/dev/null; then
  echo "🍺 Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "✅ Homebrew already installed."
fi

# === Check and install mkcert ===
if ! command -v mkcert &>/dev/null; then
  echo "🔐 Installing mkcert..."
  brew install mkcert
else
  echo "✅ mkcert already installed."
fi

# === Check and install zsh ===
if ! command -v zsh &>/dev/null; then
  echo "💻 Installing zsh..."
  brew install zsh
else
  echo "✅ zsh already installed."
fi

# === Set zsh as default shell ===
if [ "$SHELL" != "/bin/zsh" ]; then
  echo "🔄 Changing default shell to zsh..."
  chsh -s /bin/zsh
fi

# === Check and install Oh My Zsh ===
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "💅 Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
  echo "✅ Oh My Zsh already installed."
fi

# === Powerlevel10k and Zsh Enhancements ===
echo "🎨 Setting up Powerlevel10k and Zsh plugins..."

# Install MesloLGS NF font (only if missing)
FONT_DIR="$HOME/Library/Fonts"
MESLO_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
MESLO_FONT_INSTALLED=$(ls "$FONT_DIR" | grep -i "MesloLGS NF Regular.ttf" || true)

if [ -z "$MESLO_FONT_INSTALLED" ]; then
  echo "🔤 Installing MesloLGS NF fonts..."
  for font in "MesloLGS NF Regular.ttf" "MesloLGS NF Bold.ttf" "MesloLGS NF Italic.ttf" "MesloLGS NF Bold Italic.ttf"; do
    curl -fsSL "$MESLO_URL/$(echo $font | sed 's/ /%20/g')" -o "$FONT_DIR/$font"
  done
  echo "✅ MesloLGS NF fonts installed."
else
  echo "✅ MesloLGS NF fonts already installed."
fi

# === Powerlevel10k and Zsh Enhancements ===
echo "🎨 Setting up Powerlevel10k and Zsh plugins..."

# === Install MesloLGS NF Nerd Fonts (macOS Nerd Fonts tap) ===
echo "🔤 Checking MesloLGS NF Nerd Font..."

if ! fc-list | grep -qi "MesloLGS NF"; then
  echo "⬇️  Installing MesloLGS NF Nerd Font..."
  brew tap homebrew/cask-fonts
  brew install --cask font-meslo-lg-nerd-font
else
  echo "✅ MesloLGS NF Nerd Font already installed."
fi

# Prompt to open Terminal font settings
read -p "🎨 Do you want to open Terminal font settings to apply MesloLGS NF now? (y/n): " change_font

if [[ "$change_font" =~ ^[Yy]$ ]]; then
  osascript <<EOF
  tell application "Terminal"
    activate
    delay 1
    display dialog "Go to Terminal > Settings > Profile > Text and set font to 'MesloLGS NF Regular'."
  end tell
EOF
fi

# Optionally configure iTerm2
if [ -d "/Applications/iTerm.app" ]; then
  read -p "🎛 Do you use iTerm2 and want to open it now to set Meslo font? (y/n): " iterm_font

  if [[ "$iterm_font" =~ ^[Yy]$ ]]; then
    open -a iTerm
    osascript <<EOF
    tell application "iTerm"
      activate
      display dialog "In iTerm: Preferences > Profiles > Text > Change Font > 'MesloLGS NF Regular'"
    end tell
EOF
  fi
fi

# Install Powerlevel10k if not already installed
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  echo "🌈 Installing Powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
else
  echo "✅ Powerlevel10k already installed."
fi

# Set ZSH_THEME in .zshrc (if not already set)
if ! grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSHRC_FILE"; then
  sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC_FILE"
  echo "✅ Set ZSH_THEME to powerlevel10k."
else
  echo "✅ ZSH_THEME already set to powerlevel10k."
fi

# Install zsh-autosuggestions if missing
AUTOSUGGEST_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
if [ ! -d "$AUTOSUGGEST_DIR" ]; then
  echo "💡 Installing zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGEST_DIR"
else
  echo "✅ zsh-autosuggestions already installed."
fi

# Install zsh-syntax-highlighting if missing
SYNTAX_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
if [ ! -d "$SYNTAX_DIR" ]; then
  echo "💡 Installing zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_DIR"
else
  echo "✅ zsh-syntax-highlighting already installed."
fi

# Add plugins if not already present
if ! grep -q "zsh-autosuggestions" "$ZSHRC_FILE"; then
  sed -i '' '/^plugins=/ s/)/ zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC_FILE"
  echo "✅ Plugins zsh-autosuggestions and zsh-syntax-highlighting added."
else
  echo "✅ Zsh plugins already configured."
fi

echo "✅ Zsh enhancements complete."
echo "🧼 Restart terminal and run 'p10k configure' to customize your prompt."

ZSHRC_FILE="$HOME/.zshrc"

echo "🔗 Updating functions and aliases in $ZSHRC_FILE..."
sed -i '' '/# === START ===/,/# === END ===/d' "$ZSHRC_FILE"

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
    echo "❌ Usage: dcv <ModelName>"
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

unalias dcu 2>/dev/null
alias dcu='docker compose up -d'

unalias dci 2>/dev/null
alias dci='docker exec -it $(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1) art project:init'

unalias dca 2>/dev/null
alias dca='docker exec -it $(docker ps --filter "name=_php" --format "{{.Names}}" | head -n 1) art'
# === END ===
EOF

echo "✅ Aliases and functions added to $ZSHRC_FILE"
echo "✅ macOS Laravel scaffolding complete. Reload terminal or run: source ~/.zshrc"

echo "📁 Copying template files..."
cp "$TEMPLATE_DIR/db/my.cnf" "$DB_DIR/"
cp "$TEMPLATE_DIR/nginx/Dockerfile" "$NGINX_DIR/"
cp "$TEMPLATE_DIR/php/"* "$PHP_DIR/"
cp -a "$TEMPLATE_DIR/src/." "$SRC_DIR/" || true

echo "🔐 Generating SSL certificate for $DOMAIN..."
CERT_SOURCE_CRT="./${PROJECT_NAME}.pem"
CERT_SOURCE_KEY="./${PROJECT_NAME}-key.pem"
CERT_DEST_CRT="$NGINX_SSL/${DOMAIN}.crt"
CERT_DEST_KEY="$NGINX_SSL/${DOMAIN}.key"

if [[ ! -f "$CERT_SOURCE_CRT" || ! -f "$CERT_SOURCE_KEY" ]]; then
  mkcert -cert-file "$CERT_SOURCE_CRT" -key-file "$CERT_SOURCE_KEY" "$DOMAIN"
fi

cp "$CERT_SOURCE_CRT" "$CERT_DEST_CRT"
cp "$CERT_SOURCE_KEY" "$CERT_DEST_KEY"
rm -f "$CERT_SOURCE_CRT" "$CERT_SOURCE_KEY"

sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    "$TEMPLATE_DIR/php/docker-entrypoint.sh.template" > "$PHP_DIR/docker-entrypoint.sh"
chmod +x "$PHP_DIR/docker-entrypoint.sh"

sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    "$TEMPLATE_DIR/nginx/default.conf.template" > "$NGINX_DIR/default.conf"

# Write .env
cat <<EOF > "$ROOT_DIR/.env"
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
REPOSITORY_NAME=${PROJECT_NAME}
IMAGE_TAG=latest
COMPOSE_BAKE=true
APP_NAME="${PROJECT_NAME}"
APP_URL="https://${DOMAIN}"
ASSET_URL="https://${DOMAIN}"
EOF

# .gitignore
cat <<EOF > "$ROOT_DIR/.gitignore"
db/data/*
*/db/data/*
../db/data/*
EOF

# docker-compose.yml
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

# Add host entry
if ! grep -q "$DOMAIN" /etc/hosts; then
  echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts >/dev/null
fi

echo "✅ Project ready at https://${DOMAIN}"
read -p "🚀 Start Docker Compose now? (y/n): " run_now
if [[ "$run_now" =~ ^[Yy]$ ]]; then
  cd "$ROOT_DIR" && docker-compose up -d --build
fi

echo "💻 Opening in VS Code..."
code "$ROOT_DIR"
