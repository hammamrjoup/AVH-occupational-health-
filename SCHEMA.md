# AVH Occupational Health & Infection Control — Central Database Schema

## 1. Overview
The Augusta Victoria Hospital (AVH) Occupational Health & Infection Control Dashboard uses a centralized, ACID-compliant SQLite database engine (`winsqlite3.dll`) located at `server_data/avh_occupational_health.db`.

This replaces fragmented, browser-only storage (localStorage and IndexedDB) as the **single source of truth** across all hospital workstations, clinical exam rooms, and mobile tablets (iPads).

---

## 2. Architecture & Design Principles

### 2.1 Single Authoritative Central Store
- **Central Authority**: The backend (`serve.ps1`) connects to `avh_occupational_health.db`.
- **Client Role**: Browser IndexedDB and in-memory caches function solely as read caches and offline draft stores. All permanent modifications require an authenticated HTTP commit to the central backend.
- **Offline / Draft State**: If connectivity is disrupted, records are stored locally with status `_pendingSync = true`. The UI explicitly displays **"Pending sync"** and never marks records as saved centrally until confirmed by an HTTP 200 response.

### 2.2 Concurrency & Versioning (OCC)
- Every entity has an integer `version` (exposed as `_version` to clients).
- When submitting an update, clients send their known `_version`.
- If the database version exceeds the client's known version, the backend rejects the update with **HTTP 409 Conflict** (`CONCURRENCY_CONFLICT`).
- The user is notified with a conflict banner and prompted to reload the latest changes, while retaining any entered form values to prevent loss of work.

### 2.3 Strict Owner-Only Recoverable Deletion
- Only the designated system owner (`hammam` by default, configurable via `$env:AVH_OWNER_ACCOUNT`) is authorized to delete records.
- All delete requests from other accounts (e.g. `occ_health`, `auditor`) are rejected by the backend with **HTTP 403 Forbidden**.
- Deletion is recoverable (soft delete: `is_deleted = 1`, `deleted_at = <ISO-8601>`, `deleted_by = <username>`).
- Only the designated owner can view deleted records via `/api/employees/trash` or restore them via `/api/employees/restore`.

### 2.4 Comprehensive Audit Trail
- Every lifecycle operation (`CREATE`, `UPDATE`, `SOFT_DELETE`, `RESTORE`) automatically inserts an immutable row into the `audit_logs` table recording the timestamp, operator username, client IP address, target entity ID, and event summary.

---

## 3. Database Tables & Schema DDL

### 3.1 `employees` Table
Stores master staff demographic, clinical, vaccination, and lab records.

```sql
CREATE TABLE IF NOT EXISTS employees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    emp_no TEXT NOT NULL UNIQUE,
    national_id TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    arabic_name TEXT,
    department TEXT,
    job_title TEXT,
    dob TEXT,
    hepb_titer TEXT,
    immunity_status TEXT,
    staff_group TEXT,
    invasive_procedure TEXT,
    data_json TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    created_by TEXT,
    updated_by TEXT,
    deleted_at TEXT,
    deleted_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_emp_no ON employees(emp_no);
CREATE INDEX IF NOT EXISTS idx_national_id ON employees(national_id);
CREATE INDEX IF NOT EXISTS idx_emp_dept ON employees(department);
CREATE INDEX IF NOT EXISTS idx_emp_deleted ON employees(is_deleted);
```

#### Field Explanations:
- `id`: Auto-incrementing internal integer primary key.
- `emp_no`: Hospital employee number (e.g., `10482`, `SYNTH-01`), unique.
- `national_id`: 9-digit Palestinian / Israeli National Identity card number, unique.
- `full_name`: Standardized English full name.
- `arabic_name`: Full Arabic name for bilingual certification and MOH compliance.
- `data_json`: Complete canonical 7-section clinical record JSON (demographics, employment, 14 vaccine schedules, laboratory antibody titers, MMR/Varicella/HepB/TB immunity assessments, and PEP history).
- `version`: Integer incremented on each update for Optimistic Concurrency Control.
- `is_deleted`: Soft-delete flag (0 = active, 1 = in trash).

---

### 3.2 `injury_reports` Table (SQE 02.01)
Stores occupational injury and exposure incident reports.

```sql
CREATE TABLE IF NOT EXISTS injury_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    serial_no TEXT NOT NULL UNIQUE,
    emp_no TEXT,
    national_id TEXT,
    employee_name TEXT NOT NULL,
    department TEXT,
    job_title TEXT,
    incident_date TEXT NOT NULL,
    report_date TEXT NOT NULL,
    incident_type TEXT,
    exposure_type TEXT,
    data_json TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    created_by TEXT,
    updated_by TEXT,
    deleted_at TEXT,
    deleted_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_injury_serial ON injury_reports(serial_no);
CREATE INDEX IF NOT EXISTS idx_injury_emp_no ON injury_reports(emp_no);
CREATE INDEX IF NOT EXISTS idx_injury_date ON injury_reports(incident_date);
CREATE INDEX IF NOT EXISTS idx_injury_deleted ON injury_reports(is_deleted);
```

#### Field Explanations:
- `serial_no`: Canonical sequential incident number (e.g., `INC-2026-10482-01`).
- `data_json`: Complete Part I, Part II, and Part III clinical exposure logs, including source patient viral status (HBsAg, Anti-HCV, HIV), staff post-exposure follow-up dates, and lab results.
- **PEP Linkage**: Saving an injury automatically updates the corresponding employee's PEP protocol history (`additionalPepRecords`) in the `employees` table within the same transaction.

---

### 3.3 `certificate_issuances` Table
Stores immutable issuance logs of official vaccination and immunity certificates.

```sql
CREATE TABLE IF NOT EXISTS certificate_issuances (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    certificate_no TEXT NOT NULL UNIQUE,
    emp_no TEXT NOT NULL,
    national_id TEXT,
    employee_name TEXT NOT NULL,
    cert_type TEXT NOT NULL,
    issued_at TEXT NOT NULL,
    issued_by TEXT NOT NULL,
    data_json TEXT NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    deleted_at TEXT,
    deleted_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_cert_no ON certificate_issuances(certificate_no);
CREATE INDEX IF NOT EXISTS idx_cert_emp ON certificate_issuances(emp_no);
```

#### Field Explanations:
- `certificate_no`: Official serial number formatted as `AVH-CERT-YYYY-NNNN`.
- `issued_by`: Authenticated username of the clinical officer who authorized the certificate.
- `data_json`: Snapshot of the clinical certificate at the time of issuance for verification audits.

---

### 3.4 `audit_logs` Table
Maintains an immutable chronological audit trail of all database write operations.

```sql
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,
    performed_by TEXT NOT NULL,
    ip_address TEXT,
    details_json TEXT,
    timestamp TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(performed_by);
CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_logs(timestamp);
```

#### Field Explanations:
- `action`: One of `CREATE`, `UPDATE`, `SOFT_DELETE`, `RESTORE`, or `BACKUP`.
- `ip_address`: Remote client IP address of the user initiating the change.
- `details_json`: Human-readable summary of the changes.

---

### 3.5 `system_meta` Table
Key-value store for application configuration, database versioning, migration flags, and last backup metadata.

```sql
CREATE TABLE IF NOT EXISTS system_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

---

## 4. Migration Tooling

### `migrate_to_sqlite.ps1`
A standalone, zero-data-loss migration utility that:
1. Creates a timestamped pre-migration backup of all files in `server_data/backups/pre_migration/`.
2. Inspects `server_data/avh_staff_2026_master.json` and loads all existing employee records.
3. Initializes `server_data/avh_occupational_health.db` with the schema and indexes above.
4. Uses SQLite batch transactions to safely deduplicate records by `emp_no` and `national_id`.
5. Imports existing injury records from `server_data/injuries.json` and local browser exports.
6. Records initial `MIGRATION_INITIALIZE` audit logs.
7. Produces a detailed reconciliation report confirming record counts match the baseline.

To run the migration manually:
```powershell
powershell -ExecutionPolicy Bypass -File .\migrate_to_sqlite.ps1
```
