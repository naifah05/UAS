# DOWNLOAD TOOLS
```php
unzip ptt.zip
chmod +x main
mv main /usr/local/bin/ptt
```

# USAGE
```php
ptt run website_scanner
```

# USING TUNNEL CLOUDFLARE
```php
dpkg -i cloudflared.deb
```

# check TUNNEL
```php
cloudflared --version
```
# USING TUNNEL
```php
cloudflared tunnel --url https://warranty.test:443 --no-tls-verify
```

# SAMPLE URL
https://bernard-verbal-cement-garmin.trycloudflare.com


# FOR REMOVE
```php
apt remove cloudflared
sudo rm -rf ~/.cloudflared
sudo rm -rf /etc/cloudflared
```
