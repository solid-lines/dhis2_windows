#######################
# Params
#######################
param (
    [string]$proxy_hostname,
    [string]$proxy_version,
	[string]$proxy_service_name
)

$nginx_install_path = "C:\Program Files\Nginx"
$letsencrypt_dir = "C:\Certbot"

#######################
# Functions
#######################

# Download and install nginx
function Download-Install-Nginx {
	Write-Host "Downloading and installing Nginx v${proxy_version}..."
	$nginxURL = "https://nginx.org/download/nginx-${proxy_version}.zip"
	$nginxZip = ".\nginx.zip"
	Invoke-WebRequest -Uri $nginxURL -OutFile $nginxZip -UseBasicParsing
	
	# Remove the previous nginx folder and extract the installation zip file
	if (Test-Path -Path ${nginx_install_path}) {
		Remove-Item -Path ${nginx_install_path} -Recurse -Force
	}
	Expand-Archive -Path $nginxZip -DestinationPath ${nginx_install_path} -Force | Out-Null
	#Remove-Item -Path $nginxZip
}

# Preconfigure Nginx creating performance.conf, gzip.conf, security.conf, stub-status.conf, proxycommon.conf, proxysecurity.conf and nginx.conf configuration files
function Preconfigure-Nginx {
	Write-Host "Configuring Nginx..."
	$nginx_performance_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\performance.conf"
	$nginx_gzip_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\gzip.conf"
	$nginx_security_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\security.conf"
	$nginx_proxycommon_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\proxycommon.conf"
	$nginx_proxysecurity_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\proxysecurity.conf"
	$nginx_stub_status_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\stub_status.conf"
	$nginx_base_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\nginx.conf"

	$nginx_stub_status_conf_content = @"
server {
	listen 127.0.0.1:80;
	server_name 127.0.0.1;
	location /stub_status {
		access_log off;
		stub_status on;
		allow 127.0.0.1;
		deny all;
	}
}
"@
	Set-Content -Path $nginx_stub_status_conf_file -Value $nginx_stub_status_conf_content
	
	$nginx_proxycommon_conf_content = @"
proxy_redirect            off;
proxy_set_header Host `$host;
proxy_set_header X-Real-IP `$remote_addr;
proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto `$scheme;

proxy_connect_timeout   480s;
proxy_read_timeout      480s;
proxy_send_timeout      480s;
proxy_buffer_size       128k;
proxy_buffers   8 128k;
proxy_busy_buffers_size 256k;
"@
	Set-Content -Path $nginx_proxycommon_conf_file -Value $nginx_proxycommon_conf_content

	$nginx_proxysecurity_conf_content = @"
# Referrer Policy
proxy_set_header Referrer-Policy "no-referrer";
# Avoid clickjacking attack
proxy_set_header X-Frame-Options "SAMEORIGIN";
# Enable Strict Transport Security (HSTS) for https
proxy_set_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload";
# Protect against MIME sniffing vulnerabilities
proxy_set_header X-Content-Type-Options "nosniff";
# X-XSS Protection
proxy_set_header X-XSS-Protection "1; mode=block";
proxy_hide_header X-Powered-By;
proxy_hide_header Server;
"@
	Set-Content -Path $nginx_proxysecurity_conf_file -Value $nginx_proxysecurity_conf_content
	
	$nginx_performance_conf_content = @"
sendfile              on;
tcp_nopush            on;
tcp_nodelay           on;
keepalive_timeout     10;
send_timeout 10;
types_hash_max_size   2048;
client_max_body_size  100M;
client_body_timeout 10;
client_header_timeout 10;
large_client_header_buffers 8 16k;
server_names_hash_bucket_size 64;
"@
	Set-Content -Path $nginx_performance_conf_file -Value $nginx_performance_conf_content
	
	$nginx_gzip_conf_content = @"
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
"@
	Set-Content -Path $nginx_gzip_conf_file -Value $nginx_gzip_conf_content

	$nginx_security_conf_content = @"
# Hide nginx server version
server_tokens off;
"@
	Set-Content -Path $nginx_security_conf_file -Value $nginx_security_conf_content
	
	$nginx_base_conf_content = @"
worker_processes auto;
error_log logs\error.log;

events { worker_connections  1024; }

http {
	map `$request_uri `$logging {
        default  1;
        ~^/grafana   0;
		~^/glowroot   0;
		~^/api/metrics	0;
	}
	
	log_format  main  '`$remote_addr - `$remote_user [`$time_local] "`$request" '
        '`$status `$body_bytes_sent "`$http_referer" '
        '"`$http_user_agent" "`$http_x_forwarded_for"';

	log_format  prometheus  '`$remote_addr - `$remote_user [`$time_local] "`$request" '
        '`$status `$body_bytes_sent "`$http_referer" '
        '"`$http_user_agent" "`$http_x_forwarded_for" `$request_time - `$upstream_response_time';
    
	access_log logs\access.log;
	access_log logs\prometheus.log prometheus if=`$logging;
	
    include  mime.types;
	include	 gzip.conf;
	include  performance.conf;
	include  security.conf;
	include  stub_status.conf;
    default_type  application/octet-stream;

    server {
        listen 80;
        server_name ${proxy_hostname};
		
		location /glowroot {
			proxy_pass http://localhost:4000;
            include proxycommon.conf;
			include proxysecurity.conf;
		}
		
		location /grafana {
			proxy_pass http://localhost:3000;
			include proxycommon.conf;
			include proxysecurity.conf;
		}
		
        location / {
            proxy_pass http://localhost:8080/;
            include proxycommon.conf;
			include proxysecurity.conf;
        }
    }
}
"@
	Set-Content -Path $nginx_base_conf_file -Value $nginx_base_conf_content
}

# Create Nginx Windows Service with nssm (https://nssm.cc/)
function Create-Nginx-Service {
	# Install nssm
	$nssm_url = "https://nssm.cc/release/nssm-2.24.zip"
	$nssm_file = ".\nssm.zip"
	Invoke-WebRequest -Uri ${nssm_url} -OutFile ${nssm_file} -UseBasicParsing
	Expand-Archive -Path ${nssm_file} -DestinationPath "C:\Program Files\" -Force | Out-Null
	Remove-Item -Path ${nssm_file}
	$current_path = Get-Location
	Set-Location "C:\Program Files\nssm-2.24\win64\"
	$nginx_exe = "${nginx_install_path}\nginx-${proxy_version}\nginx.exe"
	cmd.exe /c ".\nssm.exe install ${proxy_service_name} `"${nginx_exe}`""
	# Start-Service -Name ${proxy_service_name}
	Set-Location ${current_path}
}

# Download and install Certbot to get SSL Certificates (REVIEW if localhost)
function Install-Certbot {
	Write-Host "Downloading and installing certbot to request SSL certificate..."
	if (-not (Test-Path -Path $letsencrypt_dir)) {
		New-Item -ItemType Directory -Path $letsencrypt_dir | Out-Null
	}
	
	$certbot_url = "https://github.com/certbot/certbot/releases/download/v2.9.0/certbot-beta-installer-win_amd64_signed.exe"
	$certbot_installer = ".\certbot-installer.exe"
	Invoke-WebRequest -Uri $certbot_url -OutFile $certbot_installer
	Start-Process -FilePath $certbot_installer -ArgumentList "/S" -Wait
	Move-Item -Path "C:\Program Files\Certbot\*" -Destination ${letsencrypt_dir} -Force | Out-Null
	[Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";${letsencrypt_dir}", [EnvironmentVariableTarget]::Machine)
	Remove-Item -Path $certbot_installer
	
	# Request SSL Certificate for the domain name
	Write-Host "Requesting SSL Certificate..."
	$certbot_exe = "$letsencrypt_dir\bin\certbot.exe"
	Start-Process -FilePath $certbot_exe -ArgumentList "certonly --standalone -n --agree-tos -m admin@${proxy_hostname} -d ${proxy_hostname}" -Wait
}

# Configure Nginx with SSL
function Configure-SSL-Nginx {
	Write-Host "Configuring Nginx with SSL..."
	$nginx_base_ssl_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\nginx.conf"
	$nginx_ssl_conf_file = "${nginx_install_path}\nginx-${proxy_version}\conf\ssl.conf"
	
	$nginx_ssl_conf_content = @"
# SSL settings
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;

ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

ssl_session_cache shared:SSL:20m;
ssl_session_timeout 20m;
ssl_session_tickets off;

# SSL OCSP stapling
ssl_stapling         on;
ssl_stapling_verify  on;

# DNS resolver configuration for OCSP response
resolver          8.8.4.4 8.8.8.8 valid=300s ipv6=off;
resolver_timeout  10s;
"@
	Set-Content -Path $nginx_ssl_conf_file -Value $nginx_ssl_conf_content
	
	$nginx_base_ssl_conf_content = @"
worker_processes auto;
error_log logs\error.log;

events { worker_connections  1024; }

http {
	map `$request_uri `$logging {
        default  1;
        ~^/grafana   0;
		~^/glowroot   0;
		~^/api/metrics	0;
	}
	
	log_format  main  '`$remote_addr - `$remote_user [`$time_local] "`$request" '
        '`$status `$body_bytes_sent "`$http_referer" '
        '"`$http_user_agent" "`$http_x_forwarded_for"';

	log_format  prometheus  '`$remote_addr - `$remote_user [`$time_local] "`$request" '
        '`$status `$body_bytes_sent "`$http_referer" '
        '"`$http_user_agent" "`$http_x_forwarded_for" `$request_time - `$upstream_response_time';
    
	access_log logs\access.log;
	access_log logs\prometheus.log prometheus if=`$logging;
	
    include  mime.types;
	include	 gzip.conf;
	include  performance.conf;
	include  security.conf;
	include  stub_status.conf;
    default_type  application/octet-stream;
	
	server {
		listen  443 ssl;
		server_name  ${proxy_hostname};
	
		ssl_certificate  C:\Certbot\live\${proxy_hostname}\fullchain.pem;
		ssl_certificate_key  C:\Certbot\live\${proxy_hostname}\privkey.pem;
	
		location /glowroot {
			proxy_pass http://localhost:4000;
            include proxycommon.conf;
			include proxysecurity.conf;
		}
		
		location /grafana {
			proxy_pass http://localhost:3000;
			include proxycommon.conf;
			include proxysecurity.conf;
		}
		
		location / {
			proxy_pass http://localhost:8080/;
            include proxycommon.conf;
			include proxysecurity.conf;
		}
	}
	
	server {
		listen  80;
		server_name  ${proxy_hostname};
	
		return 301 https://`$host\`$request_uri;
	}
}
"@
	Set-Content -Path $nginx_base_ssl_conf_file -Value $nginx_base_ssl_conf_content
}

#######################
# Script
#######################

Write-Host "Init Nginx v${proxy_version} proxy server installation..."

Download-Install-Nginx
Preconfigure-Nginx
Create-Nginx-Service
Install-Certbot
Configure-SSL-Nginx
Restart-Service -Name $proxy_service_name

Write-Host "Nginx installed and configured successfully as proxy server (https://${proxy_hostname})"
