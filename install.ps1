#######################
# Functions
#######################

# Add firewall rule if it does not exist REVIEW
function Add-PortFirewall {
    param (
        [int]$Port
    )

    if (Get-NetFirewallRule | Where-Object {($_ | Get-NetFirewallPortFilter).LocalPort -eq ${Port} -and $_.Enabled -eq "True"}) {
		Write-Host "Port ${Port} already opened in the firewall"
	} else {
		Write-Host "Adding firewall rule to allow port ${Port}"
		New-NetFirewallRule -DisplayName "Allow Port ${Port}" -Direction Inbound -Protocol "TCP" -LocalPort ${Port}.ToString() -Action Allow
	}
}

#######################
# Script
#######################

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "DHIS2 has to be installed as Administrator."
    Exit 1
}

Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Unblock-File -Path ".\JDK\install_openJDK.ps1"
Unblock-File -Path ".\Tomcat\install_Tomcat.ps1"
Unblock-File -Path ".\PostgreSQL\install_PostgreSQL.ps1"
Unblock-File -Path ".\DHIS2\install_DHIS2.ps1"
Unblock-File -Path ".\Nginx\install_Nginx.ps1"
Unblock-File -Path ".\Prometheus\install_Prometheus.ps1"

Write-Host "Init DHIS2 installation...."
Write-Host "Loading config settings"

# Load config.json and get variables
try {
	$config = Get-Content -Raw -Path ".\config.json" | ConvertFrom-Json
} catch {
    Write-Error "Config file: config.json has errors. Please review it!  $_"
}

$jdk_version = $config.jdk.version
$tomcat_version = $config.tomcat.version
$tomcat_path = $config.tomcat.path
$tomcat_service_name = $config.tomcat.service_name
$tomcat_xmx = $config.tomcat.xmx
$tomcat_xms = $config.tomcat.xms
$tomcat_username = $config.tomcat.username
$tomcat_password = $config.tomcat.password
$glowroot_enabled = $config.monitoring.glowroot.enabled
$glowroot_version = $config.monitoring.glowroot.version
$glowroot_username = $config.monitoring.glowroot.username
$glowroot_password = $config.monitoring.glowroot.password
$prometheus_grafana_enabled = $config.monitoring.prometheus_grafana.enabled
$prometheus_version = $config.monitoring.prometheus_grafana.prometheus_version
$grafana_version = $config.monitoring.prometheus_grafana.grafana_version
$pg_version = $config.postgresql.version
$pg_host = $config.postgresql.host
$pg_port = $config.postgresql.port
$pg_username = $config.postgresql.username
$pg_password = $config.postgresql.password
$pg_service_name = $config.postgresql.service_name
$pg_max_connections = $config.postgresql.max_connections
$pg_memory_gb = $config.postgresql.memory
$pg_cpus = $config.postgresql.cpus
$postgis_version = $config.postgresql.postgis_version
$dhis2_version = $config.dhis2.version
$dhis2_home = $config.dhis2.home
$dhis2_path = $config.dhis2.path
$dhis2_db_name = $config.dhis2.db_name
$dhis2_db_username = $config.dhis2.db_username
$dhis2_db_password = $config.dhis2.db_password
$proxy_name = $config.proxy.name
$proxy_version = $config.proxy.version
$proxy_hostname = $config.proxy.hostname
$proxy_service_name = $config.proxy.service_name

# REVIEW URLS previamente

# If hostname is not localhost, create firewall rules to open ports 80 and 443
if (${proxy_hostname} -ne "localhost") {
	Write-Host "Adding firewall rules to allow HTTP and HTTPS connections."
	Add-PortFirewall -Port 80 *> $null
	Add-PortFirewall -Port 443 *> $null
} else {
	Write-Host "Hostname is localhost. No firewall rules needed."
}

# Install JDK
try {
    .\JDK\install_OpenJDK.ps1 -jdk_version $jdk_version
} catch {
    Write-Error "JDK $jdk_version installation failed: $_"
}

# Install Tomcat and Glowroot
try {
    .\Tomcat\install_Tomcat.ps1 -tomcat_version $tomcat_version -tomcat_service_name $tomcat_service_name -tomcat_path $tomcat_path -tomcat_xmx $tomcat_xmx -tomcat_xms $tomcat_xms -tomcat_username $tomcat_username -tomcat_password $tomcat_password -glowroot_enabled $glowroot_enabled -glowroot_version $glowroot_version -glowroot_username $glowroot_username -glowroot_password $glowroot_password
} catch {
    Write-Error "Tomcat $tomcat_version installation failed: $_"
}

# Install PostgreSQL, postgis and PGAdmin
try {
    .\PostgreSQL\install_PostgreSQL.ps1 -pg_version $pg_version -pg_username $pg_username -pg_password $pg_password -pg_port $pg_port -pg_service_name $pg_service_name -pg_max_connections $pg_max_connections -pg_memory_gb $pg_memory_gb -pg_cpus $pg_cpus -dhis2_db_name $dhis2_db_name -postgis_version $postgis_version
} catch {
    Write-Error "PostgreSQL $pg_version installation failed: $_"
}

# Install DHIS2
try {
    .\DHIS2\install_DHIS2.ps1 -dhis2_version $dhis2_version -dhis2_path $dhis2_path -dhis2_db_name $dhis2_db_name -dhis2_db_username $dhis2_db_username -dhis2_db_password $dhis2_db_password -dhis2_home $dhis2_home -pg_version $pg_version -pg_host $pg_host -pg_port $pg_port -pg_username $pg_username -pg_password $pg_password -pg_service_name $pg_service_name -pg_max_connections $pg_max_connections -tomcat_path $tomcat_path -tomcat_service_name $tomcat_service_name -proxy_hostname $proxy_hostname
} catch {
    Write-Error "DHIS2 $dhis2_version installation failed: $_"
}

# Install Nginx
try {
	if ($proxy_name -ieq "nginx") {
		.\Nginx\install_Nginx.ps1 -proxy_hostname $proxy_hostname -proxy_version $proxy_version -proxy_service_name $proxy_service_name
	}
} catch {
    Write-Error "Nginx installation failed: $_"
}

# Install Prometheus and Grafana
try {
	if ($prometheus_grafana_enabled -ieq "Y") {
		.\Prometheus\install_Prometheus.ps1 -proxy_hostname $proxy_hostname -proxy_version $proxy_version -prometheus_version $prometheus_version -grafana_version $grafana_version -pg_username $pg_username -pg_password $pg_password -dhis2_db_name $dhis2_db_name
	}
} catch {
    Write-Error "Prometheus and Grafana installation failed: $_"
}