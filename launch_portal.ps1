# ==============================================================================
# AVH OCCUPATIONAL HEALTH - INSTANT LAUNCHER & GUARDIAN
# Ensures server & watchdog are running, then opens http://localhost:8085/
# ==============================================================================

$baseDir = $PSScriptRoot
$watchdogScript = Join-Path $baseDir "server_watchdog.ps1"
$serveScript = Join-Path $baseDir "serve.ps1"
$port = 8085
$url = "http://localhost:$port/"
$healthUrl = "http://localhost:$port/api/health"

function Test-Health {
    try {
        $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

# 1. Check if server is already responding
$online = Test-Health

if (-not $online) {
    # Free port if stuck
    try {
        $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            if ($c.OwningProcess -and $c.OwningProcess -gt 0) {
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    # Start serve.ps1 directly
    Start-Process -FilePath "powershell.exe" -WorkingDirectory $baseDir -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ".\serve.ps1", "-Port", "$port" -WindowStyle Hidden

    # Wait up to 6 seconds for server to come up
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-Health) {
            $online = $true
            break
        }
    }
}

# 2. Make sure watchdog is running in background to keep it alive forever
$watchdogRunning = $false
try {
    $wProcs = Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%server_watchdog.ps1%'" -ErrorAction SilentlyContinue
    if ($wProcs) { $watchdogRunning = $true }
} catch {}

if (-not $watchdogRunning) {
    Start-Process -FilePath "powershell.exe" -WorkingDirectory $baseDir -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ".\server_watchdog.ps1" -WindowStyle Hidden
}

# 3. Open browser to the portal
Start-Process $url
