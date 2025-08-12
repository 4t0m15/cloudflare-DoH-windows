# Enable Cloudflare DoH (Windows 10/11)

Sets Cloudflare DNS (IPv4, optional IPv6) and enables Auto-DoH on Windows 10. Run as Administrator.

Usage:

1. Save `Enable-Cloudflare-DoH.ps1`.
2. Open PowerShell as Admin in that folder.
3. Run one of:

   * `.\Enable-Cloudflare-DoH.ps1 -InterfaceAlias "Wi-Fi"`
   * `.\Enable-Cloudflare-DoH.ps1 -InterfaceAlias "Ethernet" -ConfigureIPv6`

When it finishes, restart your PC.

Test @ 1.1.1.1/help
