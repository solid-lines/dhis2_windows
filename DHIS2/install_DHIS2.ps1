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
	[string]$pg_max_connections,
	[string]$tomcat_path,
	[string]$tomcat_service_name,
	[string]$proxy_hostname
)

$tomcat_install_path = "C:\Program Files\Tomcat\${tomcat_path}"
$war_file = ".\${dhis2_path}.war"

#######################
# Functions
#######################

# Get DHIS2 URL from the dhis2_version. It could be 40, 2.40, 40.7.0, 2.40.7.0 ...
function Get-DHIS2-URL {
    $parts = $dhis2_version -split "\."

    if ($parts[0] -ne "2") {
        $release = $parts[0]
		if ([int]$release -lt 40) {
			$release = "2." + $release
		}
        $version = ($parts | Select-Object -Skip 1) -join "."
    }
    else {
        $release = $parts[1]
		if ([int]$release -lt 40) {
			$release = "2." + $release
		}
        $version = ($parts | Select-Object -Skip 2) -join "."
    }

    if ($version -eq "") {
        $DHIS2_URL = "https://releases.dhis2.org/${release}/dhis2-stable-latest.war"
    } else {
		$DHIS2_URL = "https://releases.dhis2.org/${release}/dhis2-stable-${release}.${version}.war"
	}

    return $DHIS2_URL
}

# Download DHIS2 war file
function Download-DHIS2 {
	# Compose URL and download war file
	$war_url = Get-DHIS2-URL
	
	Write-Host "Downloading DHIS2 v${dhis2_version} war file... (${war_url})"

	try {
		Invoke-WebRequest -Uri $war_url -OutFile $war_file -ErrorAction Stop
	} catch {
		Write-Error "Error downloading DHIS2 v${dhis2_version} war file."
		Exit 1
	}
}

# Configure DHIS_HOME and dhis.conf
function Configure-DHIS2 {
	Write-Host "Configuring DHIS2_HOME in ${dhis_home}"
	if (-Not (Test-Path -Path $dhis2_home)) {
		New-Item -Path $dhis2_home -ItemType Directory | Out-Null
	}
	
	# Leave free connections in postgresql
	$dhis2MaxPoolInt = [int]$pg_max_connections - 10
	$dhis2MaxPool = $dhis2MaxPoolInt.ToString()
	
	Write-Host "Configuring dhis.conf"
	$dhis2_config_file = "${dhis2_home}\dhis.conf"
	Set-Content -Path $dhis2_config_file -Value @"
connection.dialect = org.hibernate.dialect.PostgreSQLDialect
connection.driver_class = org.postgresql.Driver
connection.url=jdbc:postgresql://${pg_host}:${pg_port}/${dhis2_db_name}
connection.username=${dhis2_db_username}
connection.password=${dhis2_db_password}
connection.schema = update
connection.pool.max_size = ${dhis2MaxPool}
server.base.url = https://${proxy_hostname}
server.https = on
connection.pool.max_idle_time_excess_con = 30
analytics.table.unlogged = on
analytics.table.unlogged = on
monitoring.api.enabled = on
monitoring.jvm.enabled = on
monitoring.dbpool.enabled = on
monitoring.hibernate.enabled = on
monitoring.uptime.enabled = on
monitoring.cpu.enabled = on
"@

# CHECK if LOCALHOST
# Add new line if there is an encryption password
#encryption.password=SuperSecretEncryptionPassword

	# Set env variable$Env:DHIS2_HOME = $dhis2_home
	[Environment]::SetEnvironmentVariable("DHIS2_HOME", $dhis2_home, "Machine")
}

# Create DHIS2 database
function Create-DHIS2-Database {
	Write-Host "Creating and configuring DHIS2 database"

	$checkRoleCommand = "& 'C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe' -h localhost -U ${pg_username} -tAc `"SELECT 1 FROM pg_roles WHERE rolname='${dhis2_db_username}';`""
	try {
		# Check if Role already exists
		$roleExists = Invoke-Expression $checkRoleCommand
		
		if ($roleExists -match "1") {
			Write-Output "Role '${dhis2_db_username}' already exists in PostgreSQL. Updating password"
			& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -c "ALTER ROLE ${dhis2_db_username} WITH PASSWORD '${dhis2_db_password}';"
		} else {
			Write-Output "Creating Role '${dhis2_db_username}' in PostgreSQL"
			& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -c "CREATE ROLE ${dhis2_db_username} WITH LOGIN PASSWORD '${dhis2_db_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE;"
		}
	} catch {
		Write-Error "Error creating dhis role."
	}
	
	# Create DHIS2 databse in PostgreSQL
	Write-Host "Creating DHIS2 database..."
	$checkDbCommand = "& 'C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe' -h localhost -U ${pg_username} -tAc `"SELECT 1 FROM pg_database WHERE datname='${dhis2_db_name}';`""

	try {
		# Check if database already exists
		$dbExists = Invoke-Expression $checkDbCommand

		if ($dbExists -match "1") {
			Write-Output "Database '${dhis2_db_name}' already exists in PostgreSQL. Dropping database"
			& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE datname = '${dhis2_db_name}';"
			& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -c "DROP DATABASE ${dhis2_db_name};"
		}
		Write-Output "Creating database '${dhis2_db_name}' in PostgreSQL"
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -c "CREATE DATABASE ${dhis2_db_name} OWNER ${dhis2_db_username};"
	} catch {
		Write-Error "Error creating dhis2 database."
	}
	
	# Create extensions
	Write-Host "Creating postgres extensions for DHIS2..."
	try {
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION IF NOT EXISTS postgis;"
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION IF NOT EXISTS btree_gin;"
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
		& "C:\Program Files\PostgreSQL\${pg_version}\bin\psql.exe" -h localhost -U ${pg_username} -d ${dhis2_db_name} -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
	} catch {
		Write-Error "Error creating postgres extension in DHIS2 database."
	}
	
	# Add .pgpass entry
	$pgpass_path = "$env:APPDATA\postgresql\pgpass.conf"
	if (-not (Test-Path -Path (Split-Path -Path ${pgpass_path}))) {
		New-Item -ItemType Directory -Path (Split-Path -Path ${pgpass_path}) -Force | Out-Null
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
	$webapps_path = "${tomcat_install_path}\webapps"
	$dhis2_deploy_path = "${webapps_path}\${dhis2_path}"

	Write-Host "WEBAPPS PATH: ${webapps_path}, DHIS_DEPLOY_PATH: ${dhis2_deploy_path}"
	# Remove previous deployments
	if (Test-Path -Path "${webapps_path}\${dhis2_path}.war") {
		Remove-Item -Path "${webapps_path}\${dhis2_path}.war" -Force
	}
	if (Test-Path -Path $dhis2_deploy_path) {
		Remove-Item -Path $dhis2_deploy_path -Recurse -Force
	}
Write-Host "COPIANDO ${war_file} a ${webapps_path}\${dhis2_path}.war"
	# Copy war file to webapps folder
	Copy-Item -Path $war_file -Destination "${webapps_path}\${dhis2_path}.war"
	
	# Restart Tomcat service
	Restart-Service -Name "${tomcat_service_name}"
}

#######################
# Script
#######################

Write-Host "Init DHIS2 v${dhis2_version} installation..."

Download-DHIS2
Configure-DHIS2
Create-DHIS2-Database
Deploy-DHIS2

Write-Host "DHIS2 v${dhis2_version} deployed and configured successfully."