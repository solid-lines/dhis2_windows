#######################
# Functions
#######################

function Init-Logs {
	param(
        [string]$LogPath
    )
	
	# Log Levels
	$global:LogLevels = @{
		"DEBUG" = 0
		"INFO"  = 1
		"WARN"  = 2
		"ERROR" = 3
	}
	
	# Get Log Level from config.json (default: INFO)
	$global:ConfigLogLevel = if ($config.logging.level) { $config.logging.level.ToUpper() } else { "INFO" }

	if (-not $global:LogLevels.ContainsKey($global:ConfigLogLevel)) {
		Write-Host "Invalid log level '$ConfigLogLevel'. Using INFO." -ForegroundColor Yellow
		$global:ConfigLogLevel = "INFO"
	}

	# Create logs path
	$global:LogPath = $LogPath
	$global:LogFile = "$LogPath\install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
	New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )
    
    if ($global:LogLevels[$Level] -lt $global:LogLevels[$global:ConfigLogLevel]) {
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
    Add-Content -Path $global:LogFile -Value $logEntry
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

# Check if URL exists
function Check-UrlExists {
    param (
        [string]$url,
        [int]$MaxRetries = 3,       # Número de intentos máximos
        [int]$RetryDelaySeconds = 5 # Segundos de espera entre intentos
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
		
		# TimeoutSec: Si el servidor tarda más de 10s en responder, cuenta como fallo
		$response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
		if ($response.StatusCode -eq 200) {
			return $true
		}

        if ($i -lt $MaxRetries) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    return $false
}

#######################
# Script
#######################

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "DHIS2 has to be installed as Administrator." 
    Exit 1
}

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

Init-Logs $config.logging.path

Write-Log "Set Execution Policies and Unblock powershell scripts" -Level DEBUG
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Unblock-File -Path ".\JDK\install_openJDK.ps1"
Unblock-File -Path ".\Tomcat\install_Tomcat.ps1"
Unblock-File -Path ".\PostgreSQL\install_PostgreSQL.ps1"
Unblock-File -Path ".\DHIS2\install_DHIS2.ps1"
Unblock-File -Path ".\Nginx\install_Nginx.ps1"
Unblock-File -Path ".\Prometheus\install_Prometheus.ps1"

Write-Log "Init DHIS2 installation...." -Level INFO
$Root_Location = Get-Location

# Check used ports
# 80, 443 -> nginx
# 8080 -> Tomcat
# 5432 -> postgresql
# 4000 -> Glowroot
# 9090, 3000 -> Prometheus, Grafana
Write-Log "Check used ports" -Level DEBUG
$requiredPorts = @()
if (Should-Run "nginx") { $requiredPorts += 80, 443 }
if (Should-Run "postgresql") { $requiredPorts += $config.postgresql.port }
if (Should-Run "tomcat") { $requiredPorts += $config.tomcat.port }
if ($glowroot_enabled -ieq "Y") { $requiredPorts += 4000 }
if ($prometheus_grafana_enabled -ieq "Y") { $requiredPorts += 3000, 9090 }
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

# Check nssm URLs (Sometimes is not available)
if ( -not (Check-UrlExists -url "https://nssm.cc/release/nssm-2.24.zip") ) {
	Write-Log "NNSM installation file is not available. Please try the installation again later." -Level ERROR
	exit 1
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
	New-Item -Path ".\downloads" -ItemType Directory -Force | Out-Null
	if (Should-Run "jdk") {
		& (Join-Path $Root_Location "JDK\install_openJDK.ps1") -Config $config
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
	Remove-Item -Path ".\downloads" -Recurse -Force | Out-Null
	Write-Log "Installation finished successfully!" -Level INFO
} catch {
	Remove-Item -Path ".\downloads" -Recurse -Force | Out-Null
	Write-Log "Installation fail: $($_.Exception.Message)" -Level ERROR 
	Write-Log "Position: $($_.InvocationInfo.PositionMessage)" -Level ERROR
	Write-Log "Stack: $($_.ScriptStackTrace)" -Level ERROR
	Exit 1
}
