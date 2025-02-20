#######################
# Params
#######################
param (
	[string]$prometheus_version,
	[string]$grafana_version,
	[string]$pg_username,
	[string]$pg_password,
	[script]$dhis2_db_name,
	[string]$proxy_hostname,
	[string]$proxy_version
)

$prometheus_base_install_path = "C:\Program Files\Prometheus" 

#######################
# Functions
#######################

# Install postgres exporter v0.16.0
function Install-postgres_exporter {
	Write-Host "Installing postgres_exporter v0.16.0"
	$pgExporterZipFile = ".\Prometheus\postgres_exporter\postgres_exporter-0.16.0.zip"
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
	cmd.exe /c ".\nssm.exe set AppParameters `"--auto-discover-databases --exclude-databases=`"template0,template1,postgres`" --collector.long_running_transactions --collector.stat_statements`""
	cmd.exe /c ".\nssm.exe set postgres_exporter Environment `"DATA_SOURCE_NAME=postgresql://${pg_username}:${pg_password}@localhost:5432/${dhis2_db_name}?sslmode=disable`""
	Set-Location $current_path

	# Start postgres_exporter service
	Start-Service -Name $pgExporterServiceName
	
	Write-Host "postgres_exporter installed and running http://localhost:9187/metrics"
}

# Install windows_exporter v0.30.4
function Install-windows_exporter {
	Write-Host "Installing windows_exporter v0.30.4"
	$windowsExporterZipFile = ".\Prometheus\windows_exporter\windows_exporter-0.30.4.zip"
	$windowsExporterInstallPath = "${prometheus_base_install_path}\windows_exporter"
	$windowsExporterFile = "${pgExporterInstallPath}\windows_exporter.exe"
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
	Write-Host "Installing nginx-prometheus-exporter v1.4.1"
	$nginxExporterZipFile = ".\Prometheus\nginx-prometheus-exporter\nginx-prometheus-exporter-1.4.1.zip"
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

# Install nginx-log-exporter
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
	
		# Config prometheus.yml
	$nginxLogExporterConfig = @"
- name: nginx
  format: $remote_addr - $remote_user [$time_local] "$method $request $protocol" $request_time-$upstream_response_time $status $body_bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for"
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
	cmd.exe /c ".\nssm.exe set ${nginxLogExporterServiceName}"
	Set-Location ${current_path}

	# Start nginx exporter service
	Start-Service -Name $nginxExporterServiceName

	Write-Host "nginx-prometheus-exporter installed and running  http://localhost:9113/metrics"
}

function Install-Prometheus {
	Write-Host "Installing Prometheus v${prometheus_version}"
	Write-Host "*** Please, remember to modify credentials to access DHIS2 in prometheus.yml config file"
	$prometheusUrl = "https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.windows-amd64.zip"
	$prometheusZip = "prometheus.zip"
	$prometheusInstallPath = "${prometheus_base_install_path}\Prometheus"
	$prometheusServiceName = "Prometheus"

	if (!(Test-Path $prometheusInstallPath)) {
		New-Item -ItemType Directory -Path $prometheusInstallPath
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
	  
  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
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
	$grafanaInstallPath = "C:\Program Files\Grafana"
	$grafanaZip = "grafana.zip"
	$grafanaServiceName = "Grafana"

	if (!(Test-Path $grafanaPath)) {
		New-Item -ItemType Directory -Path $grafanaPath
	}

	# Download and unzip Grafana
	Invoke-WebRequest -Uri $grafanaUrl -OutFile $grafanaZip
	Expand-Archive -Path $grafanaZip -DestinationPath $grafanaInstallPath -Force

	#Rename-Item -Path "${grafanaInstallPath}\grafana-v${grafana_version}" -NewName "${grafanaInstallPath}" -Force
	
	# Create Grafana windows service
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	cmd.exe /c ".\nssm.exe install ${grafanaServiceName} `"${grafanaInstallPath}\bin\grafana-server.exe`""
	Set-Location ${current_path}
	
	# Modify default.ini to allow domain and sub-path in Grafana
	$grafanaConfFile = "${grafanaInstallPath}\conf\default.ini"
	$grafanaConfFileContent = Get-Content $grafanaConfFile
	# Comment root_url and serve_from_sub_path entries
	$grafanaConfFileContent = $grafanaConfFileContent -replace "^(root_url\s*=)", "# $1"
	$grafanaConfFileContent = $grafanaConfFileContent -replace "^(serve_from_sub_path\s*=)", "# $1"
	# Add new entries
	$contentNewEntries = @(
		"root_url = https://${proxy_hostname}/grafana"
		"serve_from_sub_path = true"
	)
	$grafanaConfFileContent + $contentNewEntries | Set-Content $grafanaConfFile -Encoding UTF8
	
	Start-Service -Name $grafanaServiceName

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