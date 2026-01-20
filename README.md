# DHIS2 Automated Installation on Windows

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://docs.microsoft.com/powershell/)
[![Windows Server](https://img.shields.io/badge/Windows%20Server-2019%2F2022-0078D6.svg)](https://www.microsoft.com/windows-server)
[![DHIS2](https://img.shields.io/badge/DHIS2-2.35--42.x-00796B.svg)](https://dhis2.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Automated deployment script for DHIS2 on Windows Server, including all required components: JDK, Tomcat, PostgreSQL/PostGIS, Nginx, and optional monitoring tools.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Version Compatibility](#version-compatibility)
- [Access URLs](#access-urls)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## 🔧 Prerequisites

- Windows Server 2019/2022 or Windows 10/11 Pro
- PowerShell 5.1 or higher
- Administrator privileges
- Internet connection
- Valid hostname with DNS pointing to server (for SSL certificate generation)

## 🚀 Quick Start

### 1. Install Git

Open PowerShell as Administrator and run:

```powershell
winget install --id Git.Git -e --source winget
```

Close the PowerShell window after installation completes.

### 2. Clone the Repository

Open a new PowerShell window as Administrator:

```powershell
cd c:\
git clone https://github.com/solid-lines/dhis2_windows.git
cd dhis2_windows
```

### 3. Prepare Execution

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Unblock-File -Path .\install.ps1
```

### 4. Configure Installation

Edit the configuration file:

```powershell
notepad .\config.json
```

**Important configurations to review:**

| Setting | Description |
|---------|-------------|
| Passwords | Change all `"changeme"` values to secure passwords |
| Memory | Adjust `tomcat.xmx/xms` (MB) and `postgresql.memory` (GB) based on available RAM |
| CPUs | Set `postgresql.cpus` based on available cores |
| Hostname | Set `proxy.hostname` to your valid domain (required for SSL) |
| Versions | Adjust component versions as needed |

### 5. Run Installation

```powershell
.\install.ps1
```

The automated installation will sequentially install all required components: JDK, Tomcat, PostgreSQL/PostGIS, DHIS2, Nginx, and monitoring tools.

> **Note:** Installation should complete without issues on a clean instance without occupied ports or pre-existing services.

## ⚙️ Configuration

### Example config.json

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
    "password": "changeme"
  },
  "monitoring": {
    "glowroot": {
      "enabled": "Y",
      "version": "0.14.2",
      "username": "admin",
      "password": "changeme"
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
    "password": "changeme",
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
    "db_password": "changeme"
  },
  "proxy": {
    "name": "nginx",
    "service_name": "Nginx",
    "version": "1.28.1",
    "hostname": "your-domain.example.com"
  }
}
```

### Memory Guidelines

Pre-configured values are optimized for a 16GB RAM instance. Adjust based on your server:

| Server RAM | Tomcat (xmx/xms) | PostgreSQL (memory) |
|------------|------------------|---------------------|
| 8 GB | 2048 MB | 4 GB |
| 16 GB | 4096 MB | 10 GB |
| 32 GB | 8192 MB | 20 GB |

## 📊 Version Compatibility

| DHIS2 Version | Recommended JDK | Minimum JDK | Tomcat Version (LTS) |
|---------------|-----------------|-------------|----------------------|
| 2.42 | 17 | 17 | 10.1.x |
| 2.41 | 17 | 17 | 9.x |
| 2.40 | 17 | 11 | 9.x |
| 2.38 | 11 | 11 | 9.x |
| 2.35 | 11 | 8 | 9.x |
| Pre-2.35 | 8 | 8 | 9.x |

**Recommended:** PostgreSQL 16 and PostGIS 3.x (LTS versions)

## 🌐 Access URLs

After successful installation:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| DHIS2 | `https://<proxy.hostname>` | admin / district |
| Glowroot | `https://<proxy.hostname>/glowroot` | As configured in `monitoring.glowroot` |
| Grafana | `https://<proxy.hostname>/grafana` | admin / admin (password change required on first login) |

## 🔍 Troubleshooting

### Check Service Status

```powershell
Get-Service Tomcat*, PostgreSQL*, Nginx, Prometheus, Grafana
```

### View Logs

Installation logs are saved to the path specified in `logging.path` (default: `.\logs`)

```powershell
# View latest installation log
Get-Content .\logs\*.log -Tail 100

# View Tomcat logs
Get-Content "C:\Program Files\Tomcat\latest\logs\catalina.log" -Tail 50
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Port already in use | Ensure ports 80, 443, 8080, 5432 are not occupied |
| SSL certificate fails | Verify hostname DNS points to server IP |
| Service won't start | Check Windows Event Viewer for errors |

## 📁 Project Structure

```
dhis2_windows/
├── install.ps1           # Main installation script
├── config.json           # Configuration file
├── JDK/                  # JDK installation scripts
├── Tomcat/               # Tomcat installation scripts
├── PostgreSQL/           # PostgreSQL installation scripts
├── DHIS2/                # DHIS2 configuration scripts
├── Nginx/                # Nginx installation scripts
├── Prometheus/           # Monitoring stack scripts
│   └── dashboards/       # Grafana dashboards
└── logs/                 # Installation logs
```

## 🔐 Security Recommendations

After installation, ensure you:

1. ✅ Change all default passwords
2. ✅ Change DHIS2 admin password (`admin/district`)
3. ✅ Change Grafana admin password on first login
4. ✅ Review firewall rules
5. ✅ Keep all components updated

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Support

- **Issues:** [GitHub Issues](https://github.com/solid-lines/dhis2_windows/issues)
- **DHIS2 Community:** [community.dhis2.org](https://community.dhis2.org)

---

Made with ❤️ by [SolidLines](https://solidlines.io)
