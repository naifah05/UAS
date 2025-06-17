#!/bin/bash

set -e

echo "🚀 Starting full WSL Ubuntu setup with Powerlevel10k..."

# === STEP 1: Update & Install Essentials ===
sudo apt update && sudo apt upgrade -y
sudo apt install -y plantuml default-jdk zsh curl git wget unzip fontconfig

# === STEP 2: Oh My Zsh ===
export RUNZSH=no
export CHSH=no
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

chsh -s $(which zsh)

# === STEP 3: Zsh Plugins ===
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# === STEP 4: Powerlevel10k Theme ===
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# === STEP 5: Auto Powerlevel10k Config ===
cat << 'EOF' > ~/.p10k.zsh
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time time)
typeset -g POWERLEVEL9K_PROMPT_ON_NEWLINE=true
typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX=""
typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX="❯ "
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
EOF

echo '[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh' >> ~/.zshrc

# === STEP 6: Install Nerd Fonts to Windows ===
echo "🔤 Installing MesloLGS NF into Windows Fonts..."

FONT_TMP="/mnt/c/Windows/Temp/fonts"
FONT_DST="/mnt/c/Windows/Fonts"
mkdir -p "$FONT_TMP"
cd "$FONT_TMP"

for style in Regular Bold Italic "Bold Italic"; do
    FILE="MesloLGS NF ${style}.ttf"
    wget -q "https://github.com/romkatv/powerlevel10k-media/raw/master/${FILE}" -O "$FILE"
    cp "$FILE" "$FONT_DST/"
done

echo "✅ Fonts copied to Windows Fonts."
echo "📝 Set your Windows Terminal font to 'MesloLGS NF'."

echo "✅ Ubuntu provisioning done. Launch Zsh now!"