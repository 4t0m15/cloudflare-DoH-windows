# setup-dnscrypt-cloudflare.ps1
# Installs dnscrypt-proxy on Windows with Cloudflare DoH and configures system DNS
# Requires: PowerShell 5+; run elevated

# --- Safety: elevate if needed ---
$currIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal    = New-Object Security.Principal.WindowsPrincipal($currIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

$ErrorActionPreference = 'Stop'

# --- Constants/paths ---
$installDir = 'C:\Program Files\dnscrypt-proxy'
$zipTemp    = Join-Path $env:TEMP 'dnscrypt-proxy-win64-latest.zip'
$configPath = Join-Path $installDir 'dnscrypt-proxy.toml'
$svcName    = 'dnscrypt-proxy'

# --- Get latest Windows x64 asset from GitHub releases ---
# Uses the official repo's "latest" API and picks the win64 zip
$latest = Invoke-RestMethod -Uri 'https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest' -Headers @{ 'User-Agent'='ps-dnscrypt-setup' }
$asset  = $latest.assets | Where-Object { $_.name -match 'dnscrypt-proxy-win64-.*\.zip$' } | Select-Object -First 1
if (-not $asset) { throw "Could not locate a win64 zip in the latest release." }

Write-Host "Downloading $($asset.name) ..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipTemp

# --- Create install dir fresh ---
if (Test-Path $installDir) {
  Write-Host "Stopping/removing any existing service..."
  try { sc.exe stop  $svcName   | Out-Null } catch {}
  try { sc.exe delete $svcName   | Out-Null } catch {}
  Start-Sleep -Seconds 1
  Remove-Item -Recurse -Force $installDir
}
New-Item -ItemType Directory -Path $installDir | Out-Null

# --- Extract zip ---
Expand-Archive -Path $zipTemp -DestinationPath $installDir
# Some archives unzip into a subfolder; flatten if needed
$possible = Get-ChildItem -Path $installDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'dnscrypt-proxy.exe') }
if ($possible) {
  Copy-Item -Path (Join-Path $possible.FullName '*') -Destination $installDir -Recurse
  Remove-Item -Recurse -Force $possible
}

# --- Write Cloudflare DoH config ---
# Keeps it minimal, verified by the public-resolvers source
@"
listen_addresses = ['127.0.0.1:53']

ipv4_servers = true
ipv6_servers = false
dnscrypt_servers = false
doh_servers = true
odoh_servers = false

require_dnssec = false
require_nolog = true
require_nofilter = true

timeout = 5000
keepalive = 30

cache = true
cache_size = 4096
cache_min_ttl = 2400
cache_max_ttl = 86400
cache_neg_min_ttl = 60
cache_neg_max_ttl = 600

ignore_system_dns = true
bootstrap_resolvers = ['9.9.9.11:53', '8.8.8.8:53']
netprobe_timeout = 60
netprobe_address = '9.9.9.9:53'

# Use Cloudflare DoH resolver(s)
server_names = ['cloudflare']

[query_log]
# file = 'query.log'
format = 'tsv'

[nx_log]
# file = 'nx.log'
format = 'tsv'

[sources]
  [sources.public-resolvers]
  urls = [
    'https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md',
    'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md',
  ]
  cache_file = 'public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 73
  prefix = ''

  [sources.relays]
  urls = [
    'https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md',
    'https://download.dnscrypt.info/resolvers-list/v3/relays.md',
  ]
  cache_file = 'relays.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 73
  prefix = ''
"@ | Set-Content -Encoding UTF8 -Path $configPath

# --- Install & start service (from install dir so it finds config) ---
Push-Location $installDir
try   { .\dnscrypt-proxy.exe --service install | Out-Host } catch {}
Start-Sleep -Seconds 1
.\dnscrypt-proxy.exe --service start | Out-Host
Pop-Location

# --- Point active/default-route NIC to 127.0.0.1 DNS ---
$def = Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
       Sort-Object -Property RouteMetric,ifMetric |
       Select-Object -First 1
if ($def) {
  Set-DnsClientServerAddress -InterfaceIndex $def.ifIndex -ServerAddresses 127.0.0.1
  ipconfig /flushdns | Out-Null
} else {
  Write-Warning "Could not determine default-route interface; DNS not changed."
}

# --- Scheduled task to re-apply DNS at logon (handles NIC/VPN changes) ---
$taskScript = @'
$def = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
       Sort-Object RouteMetric,ifMetric | Select-Object -First 1
if ($def) {
  try { Set-DnsClientServerAddress -InterfaceIndex $def.ifIndex -ServerAddresses 127.0.0.1 } catch {}
}
'@
$helper = 'C:\ProgramData\set-local-dns.ps1'
$null = New-Item -ItemType Directory -Path (Split-Path $helper) -Force
$taskScript | Set-Content -Encoding UTF8 -Path $helper

schtasks /Create /TN "SetLocalDNS127" /SC ONLOGON `
  /TR "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$helper`"" `
  /RL HIGHEST /F | Out-Null

# --- Smoke test ---
Write-Host "`nRunning quick resolve test against Cloudflare..."
& "$installDir\dnscrypt-proxy.exe" -resolve cloudflare-dns.com

Write-Host "`nAll done. dnscrypt-proxy installed to: $installDir"
Write-Host "DNS set to 127.0.0.1 on your active interface."
