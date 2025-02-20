#######################
# Params
#######################
param (
    [string]$pg_version,
	[string]$pg_username,
    [string]$pg_password,
	[string]$pg_service_name,
	[string]$pg_port,
	[string]$pg_memory_gb,
    [string]$pg_max_connections,
    [string]$pg_cpus,
	[string]$dhis2_db_name,
	[string]$postgis_version
)

$pg_download_file = ".\postgresql_${pg_version}_installer.exe"
$pg_install_path = "C:\Program Files\PostgreSQL\${pg_version}"

#######################
# Functions
#######################

# Check if PostgreSQL is already running
function Check-PostgreSQL {
    # Check port
    $portInUse = netstat -ano | Select-String ":${pg_port}\s+LISTENING"

    # Check service
    $postgresService = Get-Service | Where-Object { $_.DisplayName -like "*postgres*" -and $_.Status -eq "Running" }

    if ($portInUse -or $postgresService) {
        Write-Host "There is already a postgresql service running and port ${pg_port} is already listening."
		return $true
    } elseif ($portInUse) {
        Write-Host "Port ${pg_port} is already listening."
		return $true
    } elseif ($postgresService) {
        Write-Host "There is already a postgresql service running."
		return $true
    } else {
        return $false
    }
}

# Get postgresql version and links from the windows donwload site
function Get-PostgreSQL-Versions {
	$url = "https://www.enterprisedb.com/downloads/postgres-postgresql-downloads"
	
	# Dopwnload HTML and get content
	$response = Invoke-WebRequest -Uri $url -UseBasicParsing
	$htmlContent = $response.Content
	[xml]$html = $htmlContent
	$table = $html.getElementsByTagName("table")[0]

	$data = @()
	
	# Iterate over the obtained table to get postgresql version and link
	$rows = $table.getElementsByTagName("tr")
	for ($i = 1; $i -lt $rows.Count; $i++) {
		$columns = $rows[$i].getElementsByTagName("td")
		if ($columns.Count -ge 5) {
			# First column: PostgreSQL Version
			$version = $columns[0].InnerText.Trim()
			# Fifth column: Link
			$link = $columns[4].getElementsByTagName("a")[0].href

			if ($version -and $link) {
				$data += @{
					version = $version
					download_link = $link
				}
			}
		}
	}
	
	# Save postgresql versions and links to a json file
	$jsonOutput = $data | ConvertTo-Json -Depth 10 -Compress
	$jsonFilePath = ".\postgresql_versions.json"
	Set-Content -Path $jsonFilePath -Value $jsonOutput
	
	return $data
}

# Get download link of a given postgresql version
function Get-PostgreSQL-DownloadLink {
	$jsonFilePath = ".\postgresql_versions.json"
	$jsonContent = Get-Content -Path $jsonFilePath -Raw | ConvertFrom-Json
	$filteredLink = $jsonContent | Where-Object { $_.version -like "${pg_version}*" } | Select-Object -ExpandProperty download_link
   
    if ($filteredLink) {
        return $filteredLink
    } else {
        return "PostgreSQL v${pg_version} download link not found."
    }
}

# Install PostgreSQL
function Install-PostgreSQL {
	$data = Get-PostgreSQL-Versions
	$downloadLink = Get-PostgreSQL-DownloadLink
	$pgDownloadFile = ".\postgresql_${pg_version}_installer.exe"
	Write-Host "Downloading PostgreSQL v${pg_version}..."

	Invoke-WebRequest -Uri ${downloadLink} -OutFile ${pgDownloadFile}
	
	# Install POstgreSQL, Postgis and PGAdmin. Create PostgreSQL service
	Write-Host "Installing PostgreSQL v${pg_version}..."
	Start-Process ${pgDownloadFile} -ArgumentList "--mode unattended", "--unattendedmodeui none", "--superpassword `"${pg_password}`"", "--serverport ${pg_port}", "--servicename `"${pg_service_name}`"", "--superaccount `"${pg_username}`"" -Wait;
	#Remove-Item -Path ${pgDownloadFile}
}

# Install Postgis
function Install-Postgis {	
    Write-Output "Downloading and installing Postgis for PostgreSQL v${pg_version}..."

    $postgisURL = "https://download.osgeo.org/postgis/windows/pg${pg_version}/postgis-bundle-pg${pg_version}x64-setup-${postgis_version}-1.exe"
    $postgisFile = ".\pg_${$pg_version}_postgis.exe"

    Invoke-WebRequest -Uri $postgisURL -OutFile $postgisFile

    Start-Process -FilePath $postgisFile -ArgumentList "/S" -Wait
}

# Configure PostgreSQL
function Configure-PostgreSQL {
	param (
		[int]$pg_cpus,
        [int]$pg_memory_gb,
		[int]$pg_max_connections
    )

	# Add include entry if it does not exist
	$pg_config_file = "${pg_install_path}\data\postgresql.conf"
	$include_line = "include_dir = 'conf.d'"
	if (-not (Select-String -Path $pg_config_file -Pattern "$($include_line)" -Quiet)) {
		Add-Content -Path $pg_config_file -Value $include_line
	}
	
	$pg_conf_path = "${pg_install_path}\data\conf.d"
	if (-not (Test-Path -Path $pg_conf_path)) {
		New-Item -Path $pg_conf_path -ItemType Directory | Out-Null
	}

    # Calculate postgresql parameters
    $shared_buffers = "{0}GB" -f [math]::Round($pg_memory_gb * 0.25)
    $effective_cache_size = "{0}GB" -f [math]::Round($pg_memory_gb * 0.75)
    $maintenance_work_mem = "{0}MB" -f [math]::Round(($pg_memory_gb * 1024) * 0.05)
    $work_mem = "{0}MB" -f [math]::Round(($pg_memory_gb * 1024) / $pg_max_connections * 0.25)
	$max_worker_processes = $pg_cpus
	$max_parallel_workers_per_gather = [math]::Ceiling($pg_cpus / 2)
	$max_parallel_workers = $pg_cpus
	$max_parallel_maintenance_workers = [math]::Ceiling($pg_cpus / 2)

    # Create postgresql config files
    $config_pgtune_file = "${pg_install_path}\data\conf.d\00-pgtune.conf"
    $config_pgtune_content = @"
shared_buffers = $shared_buffers
effective_cache_size = $effective_cache_size
maintenance_work_mem = $maintenance_work_mem
work_mem = $work_mem
wal_buffers = 16MB
checkpoint_completion_target = 0.9
default_statistics_target = 100
random_page_cost = 1.1
max_connections = $pg_max_connections
max_worker_processes = $max_worker_processes
max_parallel_workers_per_gather = $max_parallel_workers_per_gather
max_parallel_workers = $max_parallel_workers
max_parallel_maintenance_workers =$max_parallel_maintenance_workers
"@

	$config_logging_file = "${pg_install_path}\data\conf.d\01-logging.conf"
    $config_logging_content = @"
# Logging Settings
logging_collector = on
log_directory = 'C:\\Program Files\\PostgreSQL\\${pg_version}\\data\\log'
log_filename = 'postgresql.log'
log_line_prefix = '%m [%p] %u@%d '
log_rotation_age = 1440
log_rotation_size = 0
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_min_duration_statement = 5000
"@

    $config_dhis2_file = "${pg_install_path}\data\conf.d\02-dhis.conf"
    $config_dhis2_content = @"
jit = off
synchronous_commit = off
wal_writer_delay = 10000ms
max_locks_per_transaction = 256
track_activity_query_size = 8192
shared_preload_libraries = 'pg_stat_statements'
"@

	Set-Content -Path $config_pgtune_file -Value $config_pgtune_content
	Set-Content -Path $config_logging_file -Value $config_logging_content
    Set-Content -Path $config_dhis2_file -Value $config_dhis2_content
}


#######################
# Script
#######################

Write-Host "Init PostgreSQL v${pg_version} installation..."

if (-not (Check-PostgreSQL)) {
	# Download and install PostgreSQL (also PGAdmin)
	Install-PostgreSQL
	
	#  Download and install Postgis
	Install-Postgis
}

# Configure postgresql
Configure-PostgreSQL -pg_cpus $pg_cpus -pg_memory_gb $pg_memory_gb -pg_max_connections $pg_max_connections

# Add .pgpass entry
$pgpass_path = "$env:APPDATA\postgresql\pgpass.conf"
if (-not (Test-Path -Path (Split-Path -Path ${pgpass_path}))) {
	New-Item -ItemType Directory -Path (Split-Path -Path $pgpass_path) -Force
	New-Item -Path $pgpass_path -ItemType File -Force | Out-Null
}
$current_pgpass_entries = Get-Content -Path $pgpass_path
$postgres_entry = "localhost:5432:postgres:${pg_username}:${pg_password}"
if (-not ($current_pgpass_entries -contains $postgres_entry)) {
	Add-Content -Path $pgpass_path -Value $postgres_entry
} 
$postgres_dhis2_entry = "localhost:5432:${dhis2_db_name}:${pg_username}:${pg_password}"
if (-not ($current_pgpass_entries -contains $postgres_dhis2_entry)) {
	Add-Content -Path $pgpass_path -Value $postgres_dhis2_entry
} 
icacls $pgpass_path /inheritance:r /grant "$($env:USERNAME):F" | Out-Null

Restart-Service -Name $pg_service_name
Write-Host "PostgreSQL v${pg_version} installed and configured successfully."
