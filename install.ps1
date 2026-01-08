#######################
# Functions
#######################

function Init-Logs {
	# Log Levels
	$LogLevels = @{
		"DEBUG" = 0
		"INFO"  = 1
		"WARN"  = 2
		"ERROR" = 3
	}
	
	# Get Log Level from config.json (default: INFO)
	$ConfigLogLevel = if ($config.logging.level) { $config.logging.level.ToUpper() } else { "INFO" }

	if (-not $LogLevels.ContainsKey($ConfigLogLevel)) {
		Write-Host "Invalid log level '$ConfigLogLevel'. Using INFO." -ForegroundColor Yellow
		$ConfigLogLevel = "INFO"
	}

	# Create logs path
	$LogPath = if ($config.logging.path) { $config.logging.path } else { ".\logs" }
	$LogFile = "$LogPath\install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
	New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )
    
    if ($LogLevels[$Level] -lt $LogLevels[$ConfigLogLevel]) {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        "INFO"  { Write-Host $logEntry -ForegroundColor White }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
    }
    
    # Write to file
    Add-Content -Path $LogFile -Value $logEntry
}

# Add firewall rule if it does not exist REVIEW
function Add-PortFirewall {
    param (
        [int]$Port
    )

    if (Get-NetFirewallRule | Where-Object {($_ | Get-NetFirewallPortFilter).LocalPort -eq ${Port} -and $_.Enabled -eq "True"}) {
		Write-Log "Port ${Port} already opened in the firewall" -Level WARN
	} else {
		Write-Log "Adding firewall rule to allow port ${Port}" -Level INFO
		New-NetFirewallRule -DisplayName "Allow Port ${Port}" -Direction Inbound -Protocol "TCP" -LocalPort ${Port}.ToString() -Action Allow
	}
}

function Should-Run([string]$name) {
	if ($Components.Count -gt 0) { return ($Components -contains $name) }
	return [bool]$config.components.$name
}

#######################
# Script
#######################

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "DHIS2 has to be installed as Administrator." -Level ERROR 
    Exit 1
}

Write-Log "Set Execution Policies and Unblock powershell scripts" -Level DEBUG
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Unblock-File -Path ".\JDK\install_openJDK.ps1"
Unblock-File -Path ".\Tomcat\install_Tomcat.ps1"
Unblock-File -Path ".\PostgreSQL\install_PostgreSQL.ps1"
Unblock-File -Path ".\DHIS2\install_DHIS2.ps1"
Unblock-File -Path ".\Nginx\install_Nginx.ps1"
Unblock-File -Path ".\Prometheus\install_Prometheus.ps1"

Write-Host "Loading config settings" -ForegroundColor White

# Load config.json and get variables
try {
	$config = Get-Content -Raw -Path ".\config.json" | ConvertFrom-Json
	$Components = @()
	$glowroot_enabled = $config.monitoring.glowroot.enabled
	$prometheus_grafana_enabled = $config.monitoring.prometheus_grafana.enabled
} catch {
	Write-Error "Config file: config.json has errors. Please review it!  $_" 
    Exit 1
}

Write-Log "Init DHIS2 installation...." -Level INFO
$Root_Location = Get-Location

# Check used ports
# 80, 443 -> nginx
# 8080 -> Tomcat
# 5432 -> postgresql
# 4000 -> Glowroot
# 9090, 3000 -> Prometheus, Grafana
Write-Log "Check used ports" -Level DEBUG
$requiredPorts = @(80, 443, ${pg_port}, ${tomcat_port})
if ($glowroot_enabled -ieq "Y") {
    $requiredPorts += 4000
}
if ($prometheus_grafana_enabled -ieq "Y") {
    $requiredPorts += 3000
	$requiredPorts += 9090
}
foreach ($port in $requiredPorts) {
	$inUse = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
	if ($inUse) {
		$portsused += "Port $port already in use"
	}
}
if ($portsused.Count -gt 0) {
        Write-Log "Ports in use. Review services and configuration." -Level ERROR 
        $portsused | ForEach-Object { Write-Log "  - $_" -Level ERROR }
        Exit 1
}

# If hostname is not localhost, create firewall rules to open ports 80 and 443
if (${proxy_hostname} -ne "localhost") {
	Write-Log "Adding firewall rules to allow HTTP and HTTPS connections." -Level INFO 
	Add-PortFirewall -Port 80 *> $null
	Add-PortFirewall -Port 443 *> $null
} else {
	Write-Log "Hostname is localhost. No firewall rules needed." -Level INFO
}

try {
  if (Should-Run "jdk") {
    & (Join-Path $Root_Location "JDK\install_OpenJDK.ps1") -Config $config
  }
  if (Should-Run "postgresql") {
    & (Join-Path $Root_Location "PostgreSQL\install_PostgreSQL.ps1") -Config $config
  }
  if (Should-Run "tomcat") {
    & (Join-Path $Root_Location "Tomcat\install_Tomcat.ps1") -Config $config
  }
  if (Should-Run "dhis2") {
    & (Join-Path $Root_Location "DHIS2\install_DHIS2.ps1") -Config $config
  }
  if (Should-Run "nginx") {
    & (Join-Path $Root_Location "Nginx\install_Nginx.ps1") -Config $config
  }
  if ($prometheus_grafana_enabled -ieq "Y") {
	& (Join-Path $Root_Location "Prometheus\install_Prometheus.ps1") -Config $config
  }

  Write-Log "Installation finished successfully!" -Level INFO
} catch {
  Write-Log "Installation fail: $($_.Exception.Message)" -Level ERROR 
  throw
} finally {
  Stop-Transcript | Out-Null
}
