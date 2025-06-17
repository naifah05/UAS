# install-wsl2.ps1

Write-Host "🚀 Installing WSL 2 and Ubuntu..."

# Enable required Windows features
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart

# Set WSL 2 as default
wsl --set-default-version 2

# Download Ubuntu from Microsoft Store (if needed)
if (-not (wsl -l -v | Select-String "Ubuntu")) {
    Write-Host "⬇️ Downloading Ubuntu 22.04..."
    Invoke-WebRequest -Uri "https://aka.ms/wslubuntu2204" -OutFile "$env:USERPROFILE\Downloads\Ubuntu.appx"
    Add-AppxPackage "$env:USERPROFILE\Downloads\Ubuntu.appx"
    Write-Host "✅ Ubuntu installed. Please run it once from Start Menu to complete setup."
    Read-Host "Press Enter after you've created the default user..."
}

# Get installed distro name
$distro = "Ubuntu-22.04"

# Set default user to root
Write-Host "🧩 Setting WSL default user to root..."
wsl -d $distro -u root -- bash -c "echo 'root ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/root"
wsl -d $distro -u root -- bash -c "chmod 0440 /etc/sudoers.d/root"
wsl.exe -d $distro config --default-user root

# Copy provision script into Ubuntu
Write-Host "📁 Copying provision.sh into WSL..."
$provisionContent = Get-Content "./provision.sh" -Raw
$escaped = $provisionContent -replace '"', '\"'
$wslCmd = "echo `"$escaped`" > /root/provision.sh && chmod +x /root/provision.sh"
wsl -d $distro -u root -- bash -c "$wslCmd"

# Run provision.sh
Write-Host "🚀 Running provision.sh inside Ubuntu..."
wsl -d $distro -u root -- bash /root/provision.sh

Write-Host "✅ Setup complete! Open Windows Terminal > Settings > WSL > set font to 'MesloLGS NF'"
