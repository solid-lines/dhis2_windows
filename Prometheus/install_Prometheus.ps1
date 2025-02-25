#######################
# Params
#######################
param (
	[string]$prometheus_version,
	[string]$grafana_version,
	[string]$pg_username,
	[string]$pg_password,
	[string]$dhis2_db_name,
	[string]$proxy_hostname,
	[string]$proxy_version
)

$prometheus_base_install_path = "C:\Program Files\Prometheus"
$postgres_exporter_version = "0.16.0"
$windows_exporter_version = "0.30.4"
$nginx-prometheus-exporter_version = "1.4.1"

#######################
# Functions
#######################

# Install postgres exporter v0.16.0
function Install-postgres_exporter {
	Write-Host "Installing postgres_exporter v${postgres_exporter_version}"
	$pgExporterZipFile = ".\Prometheus\postgres_exporter\postgres_exporter-${postgres_exporter_version}.zip"
	$pgExporterInstallPath = "${prometheus_base_install_path}\postgres_exporter"
	$pgExporterFile = "${pgExporterInstallPath}\postgres_exporter.exe"
	$pgExporterServiceName = "postgres_exporter"

	# Create install path if it does not exist
	if (!(Test-Path "${pgExporterInstallPath}")) {
		New-Item -ItemType Directory -Path "${pgExporterInstallPath}"
	}

	# Unzip postgres_exporter
	Expand-Archive -Path $pgExporterZipFile -DestinationPath $pgExporterInstallPath -Force

	# Create windows exporter service
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	cmd.exe /c ".\nssm.exe install ${pgExporterServiceName} `"${pgExporterFile}`""
	cmd.exe /c ".\nssm.exe set ${pgExporterServiceName} AppParameters `"--auto-discover-databases --exclude-databases='template0,template1,postgres' --collector.long_running_transactions --collector.stat_statements`""
	cmd.exe /c ".\nssm.exe set ${pgExporterServiceName} AppEnvironmentExtra `"DATA_SOURCE_NAME=postgresql://${pg_username}:${pg_password}@localhost:5432/${dhis2_db_name}?sslmode=disable`""
	Set-Location $current_path

	# Start postgres_exporter service
	Start-Service -Name $pgExporterServiceName
	
	Write-Host "postgres_exporter installed and running http://localhost:9187/metrics"
}

# Install windows_exporter v0.30.4
function Install-windows_exporter {
Write-Host "Installing windows_exporter v${windows_exporter_version}"
	$windowsExporterZipFile = ".\Prometheus\windows_exporter\windows_exporter-${windows_exporter_version}.zip"
	$windowsExporterInstallPath = "${prometheus_base_install_path}\windows_exporter"
	$windowsExporterFile = "${windowsExporterInstallPath}\windows_exporter.exe"
	$windowsExporterServiceName = "windows_exporter"

	# Create install path if it does not exist
	if (!(Test-Path "${windowsExporterInstallPath}")) {
		New-Item -ItemType Directory -Path "${windowsExporterInstallPath}"
	}
	
	# Unzip windows_exporter
	Expand-Archive -Path $windowsExporterZipFile -DestinationPath $windowsExporterInstallPath -Force

	# Create windows_exporter service
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	cmd.exe /c ".\nssm.exe install ${windowsExporterServiceName} `"${windowsExporterFile}`""
	cmd.exe /c ".\nssm.exe set ${windowsExporterServiceName} AppParameters `"--collectors.enabled ad,adfs,cache,cpu,cpu_info,cs,container,dfsr,dhcp,dns,fsrmquota,iis,logical_disk,logon,memory,msmq,mssql,netframework,net,os,process,remote_fx,service,tcp,time,vmware`""
	Set-Location $current_path
	
	# Start windows_exporter service
	Start-Service -Name $windowsExporterServiceName

	Write-Host "windows_exporter installed and running  http://localhost:9182/metrics"
}

# Install nginx-prometheus-exporter v1.4.1
function Install-nginx-prometheus-exporter {
	Write-Host "Installing nginx-prometheus-exporter v${nginx-prometheus-exporter_version}"
	$nginxExporterZipFile = ".\Prometheus\nginx-prometheus-exporter\nginx-prometheus-exporter-${nginx-prometheus-exporter_version}.zip"
	$nginxExporterInstallPath = "${prometheus_base_install_path}\nginx-prometheus-exporter"
	$nginxExporterFile = "${nginxExporterInstallPath}\nginx-prometheus-exporter.exe"
	$nginxExporterServiceName = "nginx-prometheus-exporter"

	# Create install path if it does not exist
	if (!(Test-Path "${nginxExporterInstallPath}")) {
		New-Item -ItemType Directory -Path "${nginxExporterInstallPath}"
	}
	
	# Unzip nginx-prometheus-exporter
	Expand-Archive -Path $nginxExporterZipFile -DestinationPath $nginxExporterInstallPath -Force
	
	# Create nginx exporter service
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	cmd.exe /c ".\nssm.exe install ${nginxExporterServiceName} `"${nginxExporterFile}`""
	cmd.exe /c ".\nssm.exe set ${nginxExporterServiceName} AppParameters `"--nginx.scrape-uri=http://localhost/stub_status`""
	Set-Location $current_path

	# Start nginx-prometheus-exporter service
	Start-Service -Name $nginxExporterServiceName

	Write-Host "nginx-prometheus-exporter installed and running  http://localhost:9113/metrics"
}

# Install nginx-log-exporter (compiled windows versoin from https://github.com/songjiayang/nginx-log-exporter)
function Install-nginx-log-exporter {
	Write-Host "Installing nginx-log-exporter"
	$nginxLogExporterZipFile = ".\Prometheus\nginx-log-exporter\nginx-log-exporter.zip"
	$nginxLogExporterInstallPath = "${prometheus_base_install_path}\nginx-log-exporter"
	$nginxLogExporterFile = "${nginxLogExporterInstallPath}\nginx-log-exporter.exe"
	$nginxLogExporterServiceName = "nginx-log-exporter"
	
	# Create install path if it does not exist
	if (!(Test-Path "${nginxLogExporterInstallPath}")) {
		New-Item -ItemType Directory -Path "${nginxLogExporterInstallPath}"
	}
	
	# Unzip nginx-prometheus-exporter
	Expand-Archive -Path $nginxLogExporterZipFile -DestinationPath $nginxLogExporterInstallPath -Force
	
	# Config config.yml
	$nginxLogExporterConfig = @"
- name: nginx
  format: `$remote_addr - `$remote_user [`$time_local] "`$method `$request `$protocol" `$status `$body_bytes_sent "`$http_referer" "`$http_user_agent" "`$http_x_forwarded_for" `$request_time-`$upstream_response_time
  source_files:
    - C:\Program Files\Nginx\nginx-${proxy_version}\logs\prometheus.log
  relabel_config:
    source_labels:
      - request
      - method
      - status
    replacement:
      request:
        trim: "?"
      status:
        replace:
          - target: 4.+
            value: 4xx
          - target: 5.+
            value: 5xx
          - target: 3.+
            value: 3xx
          - target: 2.+
            value: 2xx
  buckets:
    upstream: [0.1, 0.3, 0.5, 1, 2]
    response: [0.1, 0.3, 0.5, 1, 2]
"@

	$nginxLogExporterConfig | Out-File -Encoding utf8 "${nginxLogExporterInstallPath}\config.yml"
	
	# Create nginx exporter service
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	cmd.exe /c ".\nssm.exe install ${nginxLogExporterServiceName} `"${nginxLogExporterFile}`""
	Set-Location ${current_path}

	# Start nginx exporter service
	Start-Service -Name $nginxLogExporterServiceName

	Write-Host "nginx-prometheus-exporter installed and running  http://localhost:9999/metrics"
}

function Install-Prometheus {
	Write-Host "Installing Prometheus v${prometheus_version}"
	Write-Host "*** Please, remember to modify credentials to access DHIS2 in prometheus.yml config file"
	$prometheusUrl = "https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.windows-amd64.zip"
	$prometheusZip = "prometheus.zip"
	$prometheusInstallPath = "${prometheus_base_install_path}\Prometheus"
	$prometheusServiceName = "Prometheus"

	if (!(Test-Path $prometheus_base_install_path)) {
		New-Item -ItemType Directory -Path $prometheus_base_install_path
	}

	# Download and unzip prometheus
	Invoke-WebRequest -Uri $prometheusUrl -OutFile $prometheusZip
	Expand-Archive -Path $prometheusZip -DestinationPath $prometheus_base_install_path -Force
	Rename-Item -Path "${prometheus_base_install_path}\prometheus-${prometheus_version}.windows-amd64" -NewName "${prometheusInstallPath}" -Force
	
	# Config prometheus.yml
	$prometheusConfig = @"
global:
  scrape_interval:     15s
  evaluation_interval: 15s 

scrape_configs:
  - job_name: 'dhis2'
    metrics_path: '/api/metrics'
    basic_auth:
      username: admin
      password: district
    scheme: https
    static_configs:
      - targets: ['${proxy_hostname}']

  - job_name: 'windows'
    static_configs:
      - targets: ['localhost:9182']

  - job_name: 'postgresql'
    static_configs:
      - targets: ['localhost:9187']

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']

  - job_name: 'nginx_logs'
    static_configs:
      - targets: ['localhost:9999']
"@

	$prometheusConfig | Out-File -Encoding utf8 "${prometheusInstallPath}\prometheus.yml"

	# Create Prometheus windows service
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	cmd.exe /c ".\nssm.exe install ${prometheusServiceName} `"${prometheusInstallPath}\prometheus.exe`""
	Set-Location ${current_path}

	# Start Prometheus service
	Start-Service -Name $prometheusServiceName
	
	Write-Host "Prometheus running http://localhost:9090"
}

# Install Grafana
function Install-Grafana {
	$grafanaUrl = "https://dl.grafana.com/enterprise/release/grafana-enterprise-${grafana_version}.windows-amd64.zip"
	$grafana_base_path = "C:\Program Files"
	$grafanaInstallPath = "C:\Program Files\Grafana"
	$grafanaZip = "grafana.zip"
	$grafanaServiceName = "Grafana"

	#if (!(Test-Path $grafanaInstallPath)) {
	#	New-Item -ItemType Directory -Path $grafanaInstallPath
	#}

	# Download and unzip Grafana
	Invoke-WebRequest -Uri $grafanaUrl -OutFile $grafanaZip
	Expand-Archive -Path $grafanaZip -DestinationPath $grafana_base_path -Force

	Rename-Item -Path "C:\Program Files\grafana-v${grafana_version}" -NewName "${grafanaInstallPath}" -Force
	
	# Create Grafana windows service
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	cmd.exe /c ".\nssm.exe install ${grafanaServiceName} `"${grafanaInstallPath}\bin\grafana-server.exe`""
	Set-Location ${current_path}
	
	# Modify default.ini to allow domain and sub-path in Grafana
	$grafanaConfFile = "${grafanaInstallPath}\conf\defaults.ini"
	(Get-Content "${grafanaConfFile}") -replace "root_url = %\(protocol\)s://%\(domain\)s:%\(http_port\)s/", "root_url = https://${proxy_hostname}/grafana" `
                                    -replace "serve_from_sub_path = false", "serve_from_sub_path = true" `
                                    | Set-Content "${grafanaConfFile}"
									
	# Start Grafana Iniciar Grafana primero para que cree los archivos de configuración
	Start-Service -Name $grafanaServiceName
	Start-Sleep -Seconds 5
	
	# Config Datasource
	New-Item -Path "${grafanaInstallPath}\conf\provisioning\datasources" -ItemType Directory -Force
	Set-Content -Path "${grafanaInstallPath}\conf\provisioning\datasources\prometheus.yaml" -Value @"
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    jsonData:
      timeInterval: 5s
"@

	# Config Dashboards folder
	New-Item -Path "${grafanaInstallPath}\conf\provisioning\dashboards" -ItemType Directory -Force
	Set-Content -Path "${grafanaInstallPath}\conf\provisioning\dashboards\dashboards.yaml" -Value @"
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: C:\Program Files\Grafana\conf\provisioning\dashboards\json
"@

	# Add dashboards
	New-Item -Path "${grafanaInstallPath}\conf\provisioning\dashboards\json" -ItemType Directory -Force
	Move-Item -Path ".\Prometheus\dashboards\*" -Destination "${grafanaInstallPath}\conf\provisioning\dashboards\json"

	# Restart Grafana service
	Restart-Service -Name $grafanaServiceName
	Start-Sleep -Seconds 5

	Write-Host "Grafana installed and running http://localhost:3000 (https://${proxy_hostname}/grafana"
}

#######################
# Script
#######################

Write-Host "Init Prometheus v${prometheus_version} and Grafana v${grafana_version} installation..."

Install-Prometheus
Install-windows_exporter
Install-postgres_exporter
Install-nginx-prometheus-exporter
Install-nginx-log-exporter
Install-Grafana

Write-Host "Prometheus and Grafana installed and configured successfully"