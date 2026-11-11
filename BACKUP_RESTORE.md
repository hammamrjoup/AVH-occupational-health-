# AVH Occupational Health & Infection Control — Backup & Disaster Recovery Guide

## 1. Overview
The Augusta Victoria Hospital (AVH) central database engine utilizes SQLite's native online atomic backup mechanism (`VACUUM INTO`). This allows consistent, point-in-time database snapshots without interrupting active clinical staff sessions or locking the database.

---

## 2. Backup Architecture

### 2.1 Backup Types
1. **Pre-Migration Baseline Snapshot**:
   Created in `server_data/backups/pre_migration/` prior to schema modifications.
2. **Automated Scheduled Backups**:
   Executed daily at 02:00 AM via Windows Task Scheduler. Stored in `server_data/backups/` and mirrored to an offsite secure network share.
3. **On-Demand Manual Backups**:
   Triggered by authorized administrators directly from the dashboard UI via the **"Central Database, Trash & Audit Trail"** management tab.

### 2.2 Backup Naming Convention
All backups are named using UTC/Local ISO timestamps:
```
avh_occupational_health_backup_YYYYMMDD_HHMMSS.db
```
Example: `avh_occupational_health_backup_20261022_154214.db`

---

## 3. Scheduled Automated Backups via Windows Task Scheduler

A scheduled PowerShell script (`backup_scheduler.ps1`) is provided to automate daily backups and enforce a 30-day retention policy.

### Creating the Scheduled Task:
Run in an elevated PowerShell prompt on the host server:

```powershell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -Command `"Invoke-RestMethod -Uri 'http://localhost:8080/api/system/backup' -Method POST -Headers @{ Authorization = 'Bearer SYSTEM_SECRET' }`""
$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "AVH_OccupationalHealth_DailyBackup" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings
```

### Alternatively, using direct file-level backup:
```powershell
powershell -ExecutionPolicy Bypass -Command {
    . "C:\avh-dashboard\server_data\AvhSqliteEngine.ps1"
    $dbPath = "C:\avh-dashboard\server_data\avh_occupational_health.db"
    $backupDir = "\\192.116.2.13\Hammam Rjoub\infection control folders\occupation health\Backups"
    $engine = [AvhSqliteEngine]::new($dbPath)
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $targetFile = Join-Path $backupDir "avh_backup_$ts.db"
    $engine.Execute("VACUUM INTO '$targetFile';")
    $engine.Dispose()
    Write-Host "Offsite backup saved to $targetFile"
}
```

---

## 4. Disaster Recovery & Restoration Protocol

In the event of hardware failure, catastrophic server corruption, or accidental deletion of critical records, follow these steps to restore the database:

### Step 1: Stop the Server Process
```powershell
Stop-Process -Name "powershell" -ErrorAction SilentlyContinue
# If running as a Windows service:
# Stop-Service -Name "AVHOccupationalHealth"
```

### Step 2: Archive the Current Database State
Before replacing files, always snapshot the current state:
```powershell
Copy-Item "C:\avh-dashboard\server_data\avh_occupational_health.db" "C:\avh-dashboard\server_data\avh_corrupted_snapshot.db" -Force
```

### Step 3: Select and Verify the Desired Backup File
Locate the desired backup in `server_data/backups/` or the offsite share. Verify its integrity using PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -Command {
    . "C:\avh-dashboard\server_data\AvhSqliteEngine.ps1"
    $testEngine = [AvhSqliteEngine]::new("C:\avh-dashboard\server_data\backups\avh_occupational_health_backup_20261022_154214.db")
    $chk = $testEngine.Query("PRAGMA integrity_check;")
    $cnt = $testEngine.Query("SELECT COUNT(*) as cnt FROM employees WHERE is_deleted = 0;")
    Write-Host "Integrity status : $($chk[0].integrity_check)"
    Write-Host "Active employees : $($cnt[0].cnt)"
    $testEngine.Dispose()
}
```

### Step 4: Overwrite the Main Database File
```powershell
Copy-Item "C:\avh-dashboard\server_data\backups\avh_occupational_health_backup_20261022_154214.db" "C:\avh-dashboard\server_data\avh_occupational_health.db" -Force
```

### Step 5: Start the Server Process
```powershell
powershell -ExecutionPolicy Bypass -File .\serve.ps1 -Port 8080 -AllowNetworkAccess
# Or: Start-Service -Name "AVHOccupationalHealth"
```

### Step 6: Verify in Browser
1. Open the dashboard at `http://localhost:8080/index.html`.
2. Sign in as `hammam`.
3. Open **System Management > Central Database, Trash & Audit Trail**.
4. Confirm `activeEmployees = 516`, `status = online`, and audit logs reflect the restoration.

---

## 5. Retention & Offsite Replication Policy

| Tier | Frequency | Retention Period | Storage Location |
|---|---|---|---|
| **Local Snapshot** | Hourly during clinic hours | 48 hours | `server_data/backups/hourly/` |
| **Daily Full** | Every night at 02:00 AM | 30 days | `server_data/backups/daily/` |
| **Weekly Full** | Every Friday night | 12 months | `\\192.116.2.13\...\Backups\` (Hospital File Server) |
| **Annual Archive** | December 31 | 10 years (Legal requirement) | Encrypted tape / offsite cold storage |
