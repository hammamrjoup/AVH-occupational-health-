# ==============================================================================
# AVH OCCUPATIONAL HEALTH - RESILIENT BACKGROUND SERVER WATCHDOG
# Guarantees http://localhost:8085/ is permanently online and auto-recovers.
# ==============================================================================

$baseDir = $PSScriptRoot
$serveScript = Join-Path $baseDir "serve.ps1"
$logFile = Join-Path $baseDir "server_watchdog.log"
$port = 8085
$healthUrl = "http://localhost:$port/api/health"

function Write-WatchdogLog([string]$msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] $msg"
    try {
        Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-WatchdogLog "=== Watchdog Service Started (Port $port) ==="

function Is-ServerHealthy {
    try {
        $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            return $true
        }
    } catch {}
    return $false
}

function Ensure-PortFree {
    try {
        $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($connections) {
            foreach ($conn in $connections) {
                $pidToKill = $conn.OwningProcess
                if ($pidToKill -and $pidToKill -gt 0 -and $pidToKill -ne $PID) {
                    Write-WatchdogLog "Port $port occupied by unresponsive PID $pidToKill. Terminating..."
                    Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Milliseconds 500
        }
    } catch {}
}

function Start-ServerProcess {
    Ensure-PortFree
    Write-WatchdogLog "Starting serve.ps1 in background..."
    try {
        $procArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$serveScript`" -Port $port"
        Start-Process -FilePath "powershell.exe" -ArgumentList $procArgs -WindowStyle Hidden
        Start-Sleep -Seconds 2
    } catch {
        Write-WatchdogLog "Error launching serve.ps1: $($_.Exception.Message)"
    }
}

# Main Watchdog Loop - runs permanently
$consecutiveFailures = 0

while ($true) {
    if (Is-ServerHealthy) {
        $consecutiveFailures = 0
    } else {
        $consecutiveFailures++
        Write-WatchdogLog "Server health check failed ($consecutiveFailures/3)"
        
        # If it fails twice consecutively, restart it
        if ($consecutiveFailures -ge 3) {
            Write-WatchdogLog "Server unresponsive. Triggering auto-recovery..."
            Start-ServerProcess
            $consecutiveFailures = 0
            
            # Wait up to 5 seconds to let it initialize
            for ($i = 0; $i -lt 5; $i++) {
                Start-Sleep -Seconds 1
                if (Is-ServerHealthy) {
                    Write-WatchdogLog "Server auto-recovery SUCCESSFUL. Portal online at $healthUrl"
                    break
                }
            }
        }
    }
    
    Start-Sleep -Seconds 12
}

