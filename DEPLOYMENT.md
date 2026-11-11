# AVH Occupational Health & Infection Control — Deployment & Multi-Device Guide

## 1. Overview
The Augusta Victoria Hospital (AVH) Occupational Health Dashboard is designed for high-availability clinical deployment across hospital local area networks (LAN), intranet subnets, and mobile devices (iPads, tablets, nursing station workstations).

This document details:
1. Environment variables and backend configuration.
2. Network topology and multi-device connection.
3. Production HTTPS deployment options (Caddy, IIS, Nginx).
4. Firewall and port configuration.
5. Windows Service unattended hosting.

---

## 2. Server Configuration & Environment Variables

The server process is driven by `serve.ps1`. It accepts command-line parameters or reads environment variables:

| Setting | Parameter | Environment Variable | Default Value | Description |
|---|---|---|---|---|
| **Port** | `-Port` | `env:PORT` | `8080` | TCP port the server listens on |
| **Network Access** | `-AllowNetworkAccess` | `env:AVH_ALLOW_LAN` | `$false` (Localhost only) | Bind to `+` (all IP interfaces) for LAN access |
| **Owner Account** | `-OwnerUsername` | `env:AVH_OWNER_ACCOUNT` | `hammam` | Sole username permitted to delete records |
| **Data Directory** | `-DataDir` | `env:AVH_DATA_DIR` | `./server_data` | Directory where SQLite database lives |
| **Database File** | `-DbPath` | `env:AVH_DB_PATH` | `./server_data/avh_occupational_health.db` | Absolute or relative path to SQLite file |

### Starting the Server for Hospital LAN Access:
```powershell
powershell -ExecutionPolicy Bypass -File .\serve.ps1 -Port 8080 -AllowNetworkAccess
```

---

## 3. Network Topology & Multi-Device Access

```
                    +------------------------------------------+
                    |  AVH Occupational Health Server          |
                    |  IP: 192.168.10.50 (or avh-health.org)   |
                    |  Backend: serve.ps1                      |
                    |  Database: avh_occupational_health.db    |
                    +------------------------------------------+
                                       ▲
                                       │ HTTPS / Port 443
               +───────────────────────┼───────────────────────+
               │                       │                       │
               ▼                       ▼                       ▼
    +────────────────----+   +───────────────────+   +───────────────────+
    | Nursing Station PC |   | Doctor's Tablet   |   | Infection Control |
    | Edge / Chrome      |   | Safari (iPad)     |   | Workstation       |
    | (Clinic Room 1)    |   | (Mobile Ward)     |   | (Admin Office)    |
    +────────────────----+   +───────────────────+   +───────────────────+
```

### 3.1 iPad & Mobile Device Access
1. Connect the iPad to the AVH secure hospital Wi-Fi network.
2. Open Safari and navigate to `https://avh-health.avh.org` (or `https://192.168.10.50`).
3. Sign in with standard staff health credentials (`occ_health` or `hammam`).
4. All 516 employee records, vaccination histories, and injuries load directly from the central SQLite database.
5. When a record is updated on the iPad, an OCC `_version` tag ensures no edits made simultaneously on a desktop workstation are overwritten.

---

## 4. Production HTTPS Configuration

HTTPS is required in production to ensure:
- Clinical data in transit is encrypted with TLS 1.3.
- Authentication tokens and passwords cannot be intercepted.
- Browser features (IndexedDB, PWA caching, cryptographic random) operate without security restrictions.

### Option A: Caddy Server (Recommended — Automatic TLS)
Caddy provides zero-maintenance HTTPS with automatic reverse proxying.

1. Download Caddy for Windows (`caddy.exe`).
2. Create a `Caddyfile` next to `caddy.exe`:
```caddy
avh-health.avh.org {
    reverse_proxy localhost:8080
    
    # Block direct access to database and internal files
    @blocked {
        path /server_data/*
        path *.db*
        path *.ps1
    }
    respond @blocked 403
}
```
3. Run Caddy: `caddy run`.

### Option B: Microsoft IIS Reverse Proxy (Standard Windows Server)
1. Install IIS, Application Request Routing (ARR), and URL Rewrite modules on the Windows Server.
2. Bind an SSL certificate issued by the AVH Internal Active Directory Certificate Authority (AD CS) to port 443 on the Default Web Site.
3. Add a URL Rewrite reverse proxy rule pointing incoming requests to `http://localhost:8080/`.
4. Add Request Filtering to deny URL segments `.db`, `.db-wal`, `server_data`, and `scratch`.

---

## 5. Running as a Permanent Windows Service

To ensure the backend runs continuously without an interactive user logged into the server:

### Using NSSM (Non-Sucking Service Manager):
```powershell
# 1. Download nssm.exe
# 2. Install the service:
nssm install AVHOccupationalHealth "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" "-ExecutionPolicy Bypass -NoProfile -File C:\avh-dashboard\serve.ps1 -Port 8080 -AllowNetworkAccess"

# 3. Set service working directory:
nssm set AVHOccupationalHealth AppDirectory "C:\avh-dashboard"

# 4. Set restart policy:
nssm set AVHOccupationalHealth AppThrottle 5000
nssm set AVHOccupationalHealth AppExit Default Restart

# 5. Start service:
nssm start AVHOccupationalHealth
```

---

## 6. Security Hardening Checklist

- [x] **Database File Isolation**: The `.db` file lives in `server_data/`. `serve.ps1` explicitly rejects static requests to `/server_data/*` or any path ending in `.db` with HTTP 403 Forbidden.
- [x] **Owner Account Lockdown**: Only the designated owner (`hammam`) can execute delete or restore endpoints. Non-owners receive HTTP 403 Forbidden.
- [x] **Password Protection**: Passwords in `users.json` are stored with individual cryptographic salts and PBKDF2-SHA256 hashes.
- [x] **Input Validation**: All server endpoints validate payload structure, data types, and required fields before committing transactions.
- [x] **CORS & Framing**: Frame protection headers (`X-Frame-Options: SAMEORIGIN`) and Content-Type sniffing prevention (`X-Content-Type-Options: nosniff`) are set on all HTTP responses.
