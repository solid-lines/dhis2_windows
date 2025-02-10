#######################
# Params
#######################
param (
    [string]$dhis2_version,              
    [string]$dhis2_db_name,    
    [string]$dhis2_db_username,    
    [string]$dhis2_db_password, 
    [string]$dhis2_path, 
    [string]$dhis2_home,
	[string]$pg_version,
	[string]$pg_host,
	[string]$pg_port,
	[string]$pg_username,
	[string]$pg_password,
	[string]$pg_service_name,
	[string]$tomcat_version,
	[string]$tomcat_service_name,
	[string]$proxy_hostname
)

$tomcat_install_dir = "C:\Program Files\Tomcat9\apache-tomcat-${tomcat_version}"

#######################
# Functions
#######################

# Download DHIS2 war file
function Download-DHIS2 {
	# Download DHIS2 war file. REVIEW VERSION
	$war_url = "https://releases.dhis2.org/${dhis2_version}/dhis2-stable-latest.war"
	$war_file = ".\${dhis2_path}.war"
	Write-Host "Downloading DHIS2 v${dhis2_version} war file..."

	try {
		Invoke-WebRequest -Uri ${war_url} -OutFile ${war_file} -ErrorAction Stop
		return ${war_file}
	} catch {
		Write-Error "Error downloading DHIS2 v${dhis2_version} war file."
		Exit 1
	}
}

# Configure DHIS_HOME and dhis.conf
function Configure-DHIS2 {
	Write-Host "Configuring DHIS2_HOME in ${dhis_home}"
	if (-Not (Test-Path -Path ${dhis2_home})) {
		New-Item -Path ${dhis2_home} -ItemType Directory
	}
	
	Write-Host "Configuring dhis.conf"
	$dhis2_config_file = "${dhis2_home}\dhis.conf"
	Set-Content -Path $dhis2_config_file -Value @"
connection.dialect = org.hibernate.dialect.PostgreSQLDialect
connection.driver_class = org.postgresql.Driver
connection.url=jdbc:postgresql://${pg_host}:${pg_port}/${dhis2_db_name}
connection.username=${dhis2_db_username}
connection.password=${dhis2_db_password}
connection.schema = update
connection.pool.max_size = 70
server.base.url = https://${proxy_hostname}
server.https = on
connection.pool.max_idle_time_excess_con = 30
analytics.table.unlogged = on
"@

# CHECK if LOCALHOST
# Add new line if there is an encryption password
#encryption.password=SuperSecretEncryptionPassword

	# Set env variable$Env:DHIS2_HOME = $dhis2_home
	[Environment]::SetEnvironmentVariable("DHIS2_HOME", $dhis2_home, "Machine")
}

# Create DHIS2 database
function Create-DHIS2-Database {
	Write-Host "Configuring DHIS2 database"
	# Create dhis role in PostgreSQL
	Write-Host "Creating dhis role in PostgreSQL"
	try {
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -c "CREATE ROLE ${dhis2_db_username} WITH LOGIN PASSWORD '${dhis2_db_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE;"
	} catch {
		Write-Error "Error creating dhis role."
	}
	
	# Create DHIS2 databse in PostgreSQL
	Write-Host "Creating DHIS2 database..."
	try {
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -c "CREATE DATABASE ${dhis2_db_name} OWNER ${dhis2_db_username};"
	} catch {
		Write-Error "Error creating dhis2 database."
	}
	
	# Create extensions
	Write-Host "Creating postgres extensions for DHIS2..."
	try {
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION postgis;"
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION btree_gin;"
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION pg_trgm;"
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION pg_stat_statements;"
	} catch {
		Write-Error "Error creating postgres extension in DHIS2 database."
	}
	
	# Add .pgpass entry
	$pgpass_path = "$env:APPDATA\postgresql\pgpass.conf"
	if (-not (Test-Path -Path (Split-Path -Path ${pgpass_path}))) {
		New-Item -ItemType Directory -Path (Split-Path -Path ${pgpass_path}) -Force
	}
	$current_pgpass_entries = Get-Content -Path ${pgpass_path}
	$dhis2_entry = "localhost:${pg_port}:${dhis2_db_name}:${dhis2_db_username}:${dhis2_db_password}"
	if (-not (${current_pgpass_entries} -contains ${dhis2_entry})) {
		Add-Content -Path ${pgpass_path} -Value ${dhis2_entry}
	}
	icacls $pgpass_path /inheritance:r /grant "$($env:USERNAME):F" | Out-Null
	
	Restart-Service -Name "${pg_service_name}"
}

# Deploy DHIS2 war file
function Deploy-DHIS2 {
	Write-Host "Deploying DHIS2 war file..."
	$webapps_dir = "$tomcat_install_dir\webapps"
	$dhis2_deploy_dir = "$webapps_dir\${dhis2_path}"

	# Remove previous deployments
	if (Test-Path -Path "$webapps_dir\${dhis2_path}.war") {
		Remove-Item -Path "$webapps_dir\${dhis2_path}.war" -Force
	}
	if (Test-Path -Path ${dhis2_deploy_dir}) {
		Remove-Item -Path ${dhis2_deploy_dir} -Recurse -Force
	}
	
	# Copy war file to webapps folder
	Copy-Item -Path $war_file -Destination "$webapps_dir\${dhis2_path}.war"
	
	# Restart Tomcat service
	Stop-Service -Name "${tomcat_service_name}" -ErrorAction SilentlyContinue
	Start-Service -Name "${tomcat_service_name}"
}

#######################
# Script
#######################

Write-Host "Init DHIS2 v${dhis2_version} installation..."

$war_file = Download-DHIS2
Configure-DHIS2
Create-DHIS2-Database
Deploy-DHIS2

Write-Host "DHIS2 v${dhis2_version} deployed and configured successfully."