# INSTALLASI WSL2
## Run PowerShell as Administrator
## Execute this script
```php
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-wsl2.ps1
```
# 📝 Notes
### Works on Windows 10 (build 19041+) or Windows 11

### If WSL isn't installed, this script will automatically trigger download from Microsoft Store
### You may need to restart your system to complete the installation

### To verify Ubuntu installed:
``` powershell
wsl -l -v
```
