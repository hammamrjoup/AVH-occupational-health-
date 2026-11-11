# ==============================================================================
# AVH OCCUPATIONAL HEALTH - ZERO-ADMIN MOBILE & IPAD BRIDGE
# Enables iPhone, iPad, and Android access across Wi-Fi without Administrator rights!
# ==============================================================================

param(
    [int]$LanPort = 8086,
    [int]$LocalPort = 8085
)

$baseDir = $PSScriptRoot
$serveScript = Join-Path $baseDir "serve.ps1"

Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "  AUGUSTA VICTORIA HOSPITAL - ZERO-ADMIN MOBILE & IPAD ACCESS" -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Initializing zero-admin network bridge on port $LanPort..." -ForegroundColor Cyan

# 1. Ensure local server is running on localhost:8085
$serverOnline = $false
try {
    $r = Invoke-WebRequest -Uri "http://localhost:$LocalPort/api/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
    if ($r.StatusCode -eq 200) { $serverOnline = $true }
} catch {}

$serverProcess = $null
if (-not $serverOnline) {
    Write-Host " Starting local Occupational Health engine (port $LocalPort)..." -ForegroundColor Gray
    $serverProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$serveScript`" -Port $LocalPort" -PassThru -WindowStyle Hidden
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Milliseconds 400
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$LocalPort/api/health" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
            if ($r.StatusCode -eq 200) {
                $serverOnline = $true
                break
            }
        } catch {}
    }
}

if (-not $serverOnline) {
    Write-Host " [ERROR] Failed to start local engine on port $LocalPort." -ForegroundColor Red
    pause
    exit 1
}

# 2. Compile and launch lightweight in-memory WinSock TCP bridge (Requires ZERO admin privileges)
$bridgeSource = @"
#pragma warning disable 4014
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

public class ZeroAdminMobileBridge
{
    private TcpListener _listener;
    private int _targetPort;
    private bool _running;

    public void Start(int listenPort, int targetPort)
    {
        _targetPort = targetPort;
        _listener = new TcpListener(IPAddress.Any, listenPort);
        _listener.Start();
        _running = true;
        Task.Run((Action)AcceptLoop);
    }

    private async void AcceptLoop()
    {
        while (_running)
        {
            try
            {
                var client = await _listener.AcceptTcpClientAsync();
                Task.Run(() => HandleClient(client));
            }
            catch
            {
                if (!_running) break;
            }
        }
    }

    private async void HandleClient(TcpClient client)
    {
        using (client)
        {
            try
            {
                using (var target = new TcpClient())
                {
                    await target.ConnectAsync("127.0.0.1", _targetPort);
                    var clientStream = client.GetStream();
                    var targetStream = target.GetStream();

                    var t1 = clientStream.CopyToAsync(targetStream);
                    var t2 = targetStream.CopyToAsync(clientStream);

                    await Task.WhenAny(t1, t2);
                }
            }
            catch { }
        }
    }

    public void Stop()
    {
        _running = false;
        try { _listener.Stop(); } catch { }
    }
}
"@

try {
    Add-Type -TypeDefinition $bridgeSource -Language CSharp -ErrorAction SilentlyContinue
} catch {}

$bridge = New-Object ZeroAdminMobileBridge
try {
    $bridge.Start($LanPort, $LocalPort)
} catch {
    Write-Host " [!] Port $LanPort appears to be in use. Trying port $($LanPort + 1)..." -ForegroundColor Yellow
    $LanPort = $LanPort + 1
    $bridge.Start($LanPort, $LocalPort)
}

# 3. Detect active network IP addresses
$ipAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -Type Unicast -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' -and -not $_.IPAddress.StartsWith('169.254.') } | Select-Object -ExpandProperty IPAddress)
if ($ipAddresses.Count -eq 0) {
    $ipAddresses = @([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.IPAddressToString -ne '127.0.0.1' -and -not $_.IPAddressToString.StartsWith('169.254.') } | ForEach-Object { $_.IPAddressToString })
}

Write-Host " PC Local Browser  : http://localhost:$LocalPort/" -ForegroundColor Cyan
Write-Host " Mobile & iPad URL [NO ADMINISTRATOR RIGHTS REQUIRED]:" -ForegroundColor Yellow
foreach ($ip in $ipAddresses) {
    Write-Host "   --> http://$ip`:$LanPort/" -ForegroundColor Green
}
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Instructions for your Phone / iPad:" -ForegroundColor Cyan
Write-Host " 1. Make sure your Phone / iPad is on the same Wi-Fi network." -ForegroundColor Gray
Write-Host " 2. Open Safari (iOS / iPad) or Chrome (Android)." -ForegroundColor Gray
if ($ipAddresses.Count -gt 0) {
    Write-Host " 3. Enter URL: http://$($ipAddresses[0]):$LanPort/" -ForegroundColor White
}
Write-Host " 4. Tap Share -> 'Add to Home Screen' to use it as a full-screen app!" -ForegroundColor Gray
Write-Host ""
Write-Host " Server is active. Leave this window open while using your mobile/iPad." -ForegroundColor Yellow
Write-Host " Press Ctrl+C in this window when you want to stop." -ForegroundColor Gray
Write-Host "==========================================================================" -ForegroundColor Green

try {
    while ($true) {
        Start-Sleep -Seconds 2
    }
} finally {
    $bridge.Stop()
    if ($serverProcess) {
        try { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Host "Zero-admin bridge stopped cleanly." -ForegroundColor Gray
}
