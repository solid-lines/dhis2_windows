# DHIS2 Automated Installation for Windows (PowerShell)

This repository provides PowerShell scripts to automate a DHIS2 deployment on Windows by installing and configuring:

- Java (JDK)
- PostgreSQL + PostGIS
- Apache Tomcat
- DHIS2 (WAR deployment)
- Nginx reverse proxy (HTTPS)
- Optional monitoring: Glowroot APM, Prometheus + Grafana

The installer is designed to run on a *clean* Windows server with no existing services occupying the required ports.

## Supported / Tested

- Windows Server 2022 / 2025 (should work on Windows 10/11 as well)
- Windows PowerShell 5.1 or PowerShell 7+

## Prerequisites

- Run **PowerShell as Administrator**.
- Internet access to download installers.
- A valid DNS record for your DHIS2 hostname (used for HTTPS certificate generation).
- Ensure required ports are free (typical defaults):
  - 80/443 (Nginx)
  - 8080 (Tomcat)
  - 5432 (PostgreSQL)
  - 4000 (Glowroot, if enabled)
  - 9090/3000 (Prometheus/Grafana, if enabled)

## Install Git (if not already installed)

```powershell
winget install --id Git.Git -e --source winget
```

Close and re-open PowerShell after installation.

## Quickstart

```powershell
cd C:\
git clone https://github.com/solid-lines/dhis2_windows.git
cd dhis2_windows

# Allow local script execution for current user
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Unblock the main installer
Unblock-File -Path .\install.ps1

# Edit configuration
notepad .\config.json

# Run installer
.\install.ps1
```

## Configuration (config.json)

`install.ps1` reads `config.json` to decide which components to install and how to configure them.

### Important notes

- **Passwords:** change all default values like `changeme` before running.
- **Memory/CPU sizing:** tune Tomcat heap (Xmx/Xms) and PostgreSQL memory/CPU to match your server.
- **Hostname:** `proxy.hostname` must be a valid DNS name pointing to the server IP.
- **Valid JSON:** `config.json` must be strict JSON (no `//` comments). If you want comments, keep a separate `config.example.json`.

### DHIS2 / Java / Tomcat compatibility (guideline)

| DHIS2 Version | Java (Recommended) | Java (Minimum) | Tomcat (LTS) |
|---|---:|---:|---|
| 2.42 | 17 | 17 | 10.1.x |
| 2.41 | 17 | 17 | 9.x |
| 2.40 | 17 | 11 | 9.x |
| 2.38 | 11 | 11 | 9.x |
| 2.35 | 11 | 8  | 9.x |
| < 2.35 | 8  | 8  | 9.x |

### Recommended database versions

- PostgreSQL **16** (LTS)
- PostGIS **3.x**

### Example config.json (minimal, valid JSON)

```json
{
  "components": {
    "jdk": true,
    "postgresql": true,
    "tomcat": true,
    "dhis2": true,
    "nginx": true
  },
  "logging": {
    "level": "DEBUG",
    "path": ".\\logs"
  },
  "jdk": {
    "version": "17"
  },
  "tomcat": {
    "version": "10.1.50",
    "path": "latest",
    "service_name": "Tomcat10",
    "port": "8080",
    "xmx": "4096",
    "xms": "4096",
    "username": "admin",
    "password": "REPLACE_ME"
  },
  "monitoring": {
    "glowroot": {
      "enabled": "Y",
      "version": "0.14.2",
      "username": "admin",
      "password": "REPLACE_ME"
    },
    "prometheus_grafana": {
      "enabled": "N",
      "prometheus_version": "3.1.0",
      "grafana_version": "11.5.1"
    }
  },
  "postgresql": {
    "version": "16",
    "host": "localhost",
    "username": "postgres",
    "password": "REPLACE_ME",
    "service_name": "Postgres16",
    "max_connections": "80",
    "memory": "10",
    "cpus": "3",
    "port": "5432",
    "postgis_version": "3.6.1"
  },
  "dhis2": {
    "version": "42.3.1",
    "home": "C:\\dhis2-home",
    "path": "ROOT",
    "db_name": "dhis2",
    "db_username": "dhis",
    "db_password": "REPLACE_ME"
  },
  "proxy": {
    "name": "nginx",
    "service_name": "Nginx",
    "version": "1.28.1",
    "hostname": "windows.dhis2.example.org"
  }
}
```

## Outputs / Access URLs

After installation, you should be able to access:

- **DHIS2:** `https://<proxy.hostname>` (default DHIS2 credentials: `admin` / `district`)
- **Glowroot (optional):** `https://<proxy.hostname>/glowroot` (credentials from config)
- **Grafana (optional):** `https://<proxy.hostname>/grafana` (default `admin/admin`, first login prompts password change)

## Logs

Logs are printed to the console and also written to the directory configured in:

- `logging.path` (default: `./logs`)

## Troubleshooting

- **"Mixed content" or browser warnings:** verify HTTPS is configured correctly and the hostname matches the certificate.
- **Port already in use:** stop the conflicting service or change ports in `config.json`.
- **Downloads failing (503/timeout):** add retries/backoff to URL checks and downloads; prefer BITS for large files.
- **config.json parsing errors:** ensure it is valid JSON (no comments/trailing commas).

## Rollback / Uninstall

A complete rollback is not always possible (depends on component installers). However, zip-based components (Tomcat, Nginx, Prometheus, Glowroot) can usually be removed by:

- Stopping/deleting Windows services created by the installer
- Removing the installation directories

Database rollback requires more care (data loss risk). Consider snapshots/VM checkpoints before first run.

---

Maintained by SolidLines (DHIS2 / infrastructure automation).
