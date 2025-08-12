#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$InterfaceAlias,     # e.g., "Wi-Fi" or "Ethernet"
    [switch]$ConfigureIPv6       # pass -ConfigureIPv6 to also set IPv6 DNS
)

try {
    # Choose adapter if not provided
    if (-not $InterfaceAlias) {
        $up = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual }
        if ($up.Count -eq 1) {
            $InterfaceAlias = $up[0].Name
        } else {
            Write-Host "Available adapters:" -ForegroundColor Cyan
            Get-NetAdapter | Select-Object Name, Status | Format-Table -AutoSize
            $InterfaceAlias = Read-Host 'Enter the adapter Name to configure (e.g., Wi-Fi or Ethernet)'
        }
    }

    # Validate adapter
    $null = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop

    # Set Cloudflare DNS (IPv4)
    Write-Host "Setting IPv4 DNS on '$InterfaceAlias' to Cloudflare (1.1.1.1, 1.0.0.1)..."
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses 1.1.1.1,1.0.0.1

    # Optionally set IPv6
    if ($ConfigureIPv6) {
        Write-Host "Setting IPv6 DNS on '$InterfaceAlias' to Cloudflare (2606:4700:4700::1111, 2606:4700:4700::1001)..."
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses 2606:4700:4700::1111,2606:4700:4700::1001
    }

    # Enable Auto-DoH via registry (single line; no PowerShell line continuations)
    Write-Host "Enabling Auto-DoH (registry)..."
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v EnableAutoDoh /t REG_DWORD /d 2 /f | Out-Null

    # Finish: no service restarts or checks—just instruct to reboot
    Write-Host "`nAll set. Please restart your PC to apply the changes." -ForegroundColor Green
}
catch {
    Write-Error $_
    exit 1
}
