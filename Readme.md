## LAKUKAN DI POWERSHELL DENGAN RUN AS ADMINISTRATOR
```php
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```
## MASIH DI POWERSHELL DENGAN RUN AS ADMINISTRATOR
```php
choco install mkcert
```
## MASIH DI POWERSHELL DENGAN RUN AS ADMINISTRATOR
```php
mkcert -install
```

### JIKA ERROR TIDAK BISA INSTALL COBA LANGKAH INI MASIH DILAKUKAN DENGAN POWERSHELL RUN AS ADMINISTRATOR
#### SATU
```php
Set-ExecutionPolicy Bypass -Scope Process -Force; `
[System.IO.Directory]::Delete("$env:ProgramData\chocolatey", $true)
```

#### DUA
```php
$envPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
$newPath = ($envPath -split ";") -ne "C:\ProgramData\chocolatey\bin" -join ";"
[Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::Machine)
```

