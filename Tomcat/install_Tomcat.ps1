#######################
# Params
#######################
param(
  [Parameter(Mandatory)] $Config
)
$tomcat = $Config.tomcat
$glowroot = $Config.monitoring.glowroot
$tomcat_version = [string]$tomcat.version
$tomcat_path = [string]$tomcat.path
$tomcat_service_name = [string]$tomcat.service_name
$tomcat_port = [string]$tomcat.port
$tomcat_xmx = [string]$tomcat.xmx
$tomcat_xms = [string]$tomcat.xms
$tomcat_username = [string]$tomcat.username
$tomcat_password = [string]$tomcat.password
$glowroot_enabled =	[string]$glowroot.enabled
$glowroot_version =	[string]$glowroot.version
$glowroot_username = [string]$glowroot.username
$glowroot_password = [string]$glowroot.password

# URLs and paths
$tomcat_base_version = $tomcat_version.Split(".")[0]
$tomcat_base_url = "https://dlcdn.apache.org/tomcat/tomcat-${tomcat_base_version}/v${tomcat_version}/bin/apache-tomcat-${tomcat_version}-windows-x64.zip"
$tomcat_archive_url = "https://archive.apache.org/dist/tomcat/tomcat-${tomcat_base_version}/v${tomcat_version}/bin/apache-tomcat-${tomcat_version}-windows-x64.zip"
$tomcat_download_file = "${downloads_path}\${tomcat_path}.zip"
$tomcat_base_dir = "C:\Program Files\Tomcat"
$tomcat_install_path = "C:\Program Files\Tomcat\${tomcat_path}"
$glowroot_url = "https://github.com/glowroot/glowroot/releases/download/v${glowroot_version}/glowroot-${glowroot_version}-dist.zip"
$glowroot_download_file = "${downloads_path}\glowroot-${glowroot_version}.zip"
$glowroot_central_url = "https://github.com/glowroot/glowroot/releases/download/v${glowroot_version}/glowroot-central-${glowroot_version}-dist.zip"
$glowroot_central_download_file = "${downloads_path}\glowroot-central-${glowroot_version}.zip"

#######################
# Functions
#######################

# Check if URL exists
function Check-UrlExists {
    param ([string]$url)
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Check if Tomcat can be downloaded from dlcdn on the main server or is an archived version
function Download-Tomcat {
    Write-Log "Downloading Apache Tomcat v$tomcat_version..." -Level INFO

    if (Check-UrlExists -url $tomcat_base_url) {
        Write-Log "Apache Tomcat v${tomcat_version} found on the main server." -Level INFO
        Invoke-WebRequest -Uri $tomcat_base_url -OutFile $tomcat_download_file -UseBasicParsing -ErrorAction Stop
		Write-Log "Apache Tomcat v${tomcat_version} downloaded from ${tomcat_base_url}." -Level INFO
    } elseif (Check-UrlExists -url $tomcat_archive_url) {
        Write-Log "Apache Tomcat v${tomcat_version}not found on the main server, trying on the archive..." -Level INFO
        Invoke-WebRequest -Uri $tomcat_archive_url -OutFile $tomcat_download_file -UseBasicParsing -ErrorAction Stop
		Write-Log "Apache Tomcat downloaded from ${tomcat_archive_url}." -Level INFO
    } else {
        Write-Log "Error: Apache Tomcat v${tomcat_version} not found." -Level ERROR
        Exit 1
    }
}

# Download Glowroot APM
function Download-Glowroot {
	Write-Log "Downloading Glowroot v$glowroot_version..." -Level INFO

    if (Check-UrlExists -url $glowroot_url) {
        Invoke-WebRequest -Uri $glowroot_url -OutFile $glowroot_download_file -UseBasicParsing -ErrorAction Stop
		Invoke-WebRequest -Uri $glowroot_central_url -OutFile $glowroot_central_download_file -UseBasicParsing -ErrorAction Stop
		Write-Log "Glowroot downloaded from ${glowroot_url}." -Level INFO
    } else {
        Write-Log "Glowroot v${glowroot_version} not found. Skipping Glowroot APM." -Level WARN
    }
}

# Install and configure Tomcat
function Install-Tomcat {
	# Extract Tomcat 
	Write-Log "Extracting Apache Tomcat to ${tomcat_base_dir}..." -Level INFO
	if (-Not (Test-Path -Path $tomcat_base_dir)) {
		New-Item -ItemType Directory -Path $tomcat_base_dir | Out-Null
	}
	Expand-Archive -Path $tomcat_download_file -DestinationPath $tomcat_base_dir -Force | Out-Null
	$tomcat_install_old_path = "${tomcat_base_dir}\apache-tomcat-${tomcat_version}"
	
	# If tomcat destination path exists, remove it. Rename Tomcat installation path to new path
	if (Test-Path $tomcat_install_path) {
		Remove-Item -Path $tomcat_install_path -Recurse -Force | Out-Null
	}
	Rename-Item -Path $tomcat_install_old_path -NewName $tomcat_install_path -Force | Out-Null
	
	# remove al items in webapps folder
	Get-ChildItem -Path "${tomcat_install_path}\webapps" -Recurse | Remove-Item -Recurse -Force | Out-Null
	
	# Update tomcat-users.xml
	Write-Log "Updating tomcat-users.xml..." -Level DEBUG
	$tomcat_users_file = "${tomcat_install_path}\conf\tomcat-users.xml"
	Set-Content -Path $tomcat_users_file -Value @"
<tomcat-users xmlns="http://tomcat.apache.org/xml"
			xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
			xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
			version="1.0">
	<role rolename="manager-gui"/>
	<role rolename="admin-gui"/>
	<user username="${tomcat_username}" password="${tomcat_password}" roles="manager-gui,admin-gui"/>
</tomcat-users>
"@
	
	# Update server.xml
	Write-Log "Updating server.xml..." -Level DEBUG
	$tomcat_server_file = "${tomcat_install_path}\conf\server.xml"
	#$server_template_file = ".\server_template.xml"
	#$server_template_content = Get-Content -Path ${server_template_file} -Raw
	#Set-Content -Path ${server_file} -Value ${server_template_content}
	Set-Content -Path $tomcat_server_file -Value @"
<?xml version="1.0" encoding="UTF-8"?>

<Server port="-1">
	<Listener className="org.apache.catalina.startup.VersionLoggerListener" />
	<Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
	<Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
	<Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
	<Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

	<GlobalNamingResources>
		<Resource name="UserDatabase" auth="Container"
				type="org.apache.catalina.UserDatabase"
				description="User database that can be updated and saved"
				factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
				pathname="conf/tomcat-users.xml" />
	</GlobalNamingResources>

	<Service name="Catalina">
		<Executor	name="tomcatThreadPool"	namePrefix="tomcat-http-"
					maxThreads="200" minSpareThreads="10" />                     
		<Connector 	port="${tomcat_port}"	protocol="HTTP/1.1"
					proxyPort="443"	scheme="https" 
					URIEncoding="UTF-8" executor="tomcatThreadPool"
					connectionTimeout="20000" relaxedQueryChars="[,]"/>
	
		<Engine name="Catalina" defaultHost="localhost">	
			<Realm className="org.apache.catalina.realm.LockOutRealm">
				<Realm className="org.apache.catalina.realm.UserDatabaseRealm"
					resourceName="UserDatabase"/>
			</Realm>		
			<Host name="localhost"  appBase="webapps"
					unpackWARs="true" autoDeploy="true">
				<Valve className="org.apache.catalina.valves.RemoteIpValve"
						remoteIpHeader="X-Forwarded-For"
						requestAttributesEnabled="true"
						internalProxies="127.0.0.1" />		
				<Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
						prefix="localhost_access_log" suffix=".txt"
						pattern="%h %l %u %t &quot;%r&quot; %s %b &quot;%{Referer}i&quot; &quot;%{User-Agent}i&quot; &quot;%{X-Forwarded-For}i&quot;" />		
			</Host>
		</Engine>
	</Service>
</Server>
"@

	# Update logging.properties
	Write-Log "Updating logging.properties..." -Level DEBUG
	$tomcat_logging_file = "${tomcat_install_path}\conf\logging.properties"
	Set-Content -Path $tomcat_logging_file -Value @"
handlers = 1catalina.org.apache.juli.AsyncFileHandler, 2localhost.org.apache.juli.AsyncFileHandler, java.util.logging.ConsoleHandler

.handlers = 1catalina.org.apache.juli.AsyncFileHandler, java.util.logging.ConsoleHandler

############################################################
# Handler specific properties.
# Describes specific configuration info for Handlers.
############################################################

1catalina.org.apache.juli.AsyncFileHandler.level = FINE
1catalina.org.apache.juli.AsyncFileHandler.directory = ${catalina.base}/logs
1catalina.org.apache.juli.AsyncFileHandler.prefix = catalina.
1catalina.org.apache.juli.AsyncFileHandler.maxDays = 90
1catalina.org.apache.juli.AsyncFileHandler.encoding = UTF-8
1catalina.org.apache.juli.AsyncFileHandler.rotatable = false
1catalina.org.apache.juli.AsyncFileHandler.suffix = log

2localhost.org.apache.juli.AsyncFileHandler.level = FINE
2localhost.org.apache.juli.AsyncFileHandler.directory = ${catalina.base}/logs
2localhost.org.apache.juli.AsyncFileHandler.prefix = localhost.
2localhost.org.apache.juli.AsyncFileHandler.maxDays = 90
2localhost.org.apache.juli.AsyncFileHandler.encoding = UTF-8
2localhost.org.apache.juli.AsyncFileHandler.rotatable = false
2localhost.org.apache.juli.AsyncFileHandler.suffix = log

java.util.logging.ConsoleHandler.level = FINE
java.util.logging.ConsoleHandler.formatter = org.apache.juli.OneLineFormatter
java.util.logging.ConsoleHandler.encoding = UTF-8

############################################################
# Facility specific properties.
# Provides extra control for each logger.
############################################################

org.apache.catalina.core.ContainerBase.[Catalina].[localhost].level = INFO
org.apache.catalina.core.ContainerBase.[Catalina].[localhost].handlers = 2localhost.org.apache.juli.AsyncFileHandler
"@
}

# Install and configure Glowroot APM
function Install-Glowroot {
	Write-Log "Started Glowroot v${glowroot_version} installation..." -Level INFO
	# Extract Glowroot 
	Write-Log "Extracting Glowroot v${glowroot_version} to ${tomcat_base_dir}" -Level INFO
	if (-Not (Test-Path -Path $tomcat_base_dir)) {
		New-Item -ItemType Directory -Path $tomcat_base_dir | Out-Null
	}
	Expand-Archive -Path $glowroot_download_file -DestinationPath $tomcat_base_dir -Force | Out-Null
	Expand-Archive -Path $glowroot_central_download_file -DestinationPath $tomcat_base_dir -Force | Out-Null
	
	Write-Log "Configuring Glowroot v${glowroot_version}..." -Level INFO
	$glowroot_hash_password = & java -jar ${tomcat_base_dir}\glowroot-central\glowroot-central.jar hash-password $glowroot_password
	#Write-Log "Glowroot password:${glowroot_password} hash to ${glowroot_hash_password}" -Level INFO
	$glowroot_admin_file = "${tomcat_base_dir}\glowroot\admin.json"
	Set-Content -Path $glowroot_admin_file -Value @"
{
  "users": [
    {
      "username": "${glowroot_username}",
      "passwordHash": "${glowroot_hash_password}",
      "roles": [
        "Administrator"
      ]
    }
  ],
  "roles": [
    {
      "name": "Administrator",
      "permissions": [
        "agent:transaction",
        "agent:error",
        "agent:jvm",
        "agent:incident",
        "agent:config",
        "admin"
      ]
    }
  ],
  "web": {
    "port": 4000,
    "bindAddress": "0.0.0.0",
    "contextPath": "/glowroot",
    "sessionTimeoutMinutes": 30,
    "sessionCookieName": "GLOWROOT_SESSION_ID"
  },
  "storage": {
    "rollupExpirationHours": [
      72,
      336,
      2160,
      2160
    ],
    "traceExpirationHours": 336,
    "fullQueryTextExpirationHours": 336,
    "rollupCappedDatabaseSizesMb": [
      500,
      500,
      500,
      500
    ],
    "traceCappedDatabaseSizeMb": 500
  }
}
"@
}


#######################
# Script
#######################

Write-Log "Started Tomcat v$tomcat_version and Glowroot v${glowroot_version} installation..." -Level INFO

# Verify if tomcat service exists and is running
$service = Get-Service -Name $tomcat_service_name -ErrorAction SilentlyContinue

if ($service) {
	# If tomcat service is running, stop it
	if ($service.Status -ieq "Running") {
		Write-Log "Tomcat service ${tomcat_service_name} found" -Level INFO
		Stop-Service -Name $tomcat_service_name -Force -ErrorAction Stop
		Write-Log "Stopped service ${tomcat_service_name}" -Level INFO
	} 
}

# Download Tomcat and Glowroot
Download-Tomcat
if ($glowroot_enabled -ieq "Y") {
	Download-Glowroot
}

# Install Tomcat and Glowroot
Install-Tomcat
if ($glowroot_enabled -ieq "Y") {
	Install-Glowroot
}

# Adjust permissions
icacls ${tomcat_base_dir} /grant "NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F" /T | Out-Null
	
$current_path = Get-Location
Set-Location ${tomcat_install_path}\bin
if (-Not ($service)) {
	# Create Tomcat service if not exists
	Write-Log "Creating Tomcat service '${tomcat_service_name}'" -Level INFO
	cmd.exe /c "service.bat install ${tomcat_service_name}"
}
$tomcatExe = "tomcat${tomcat_base_version}.exe"
if ($glowroot_enabled -ieq "Y") {
cmd.exe /c "${tomcatExe} //US//${tomcat_service_name} --JvmMx=${tomcat_xmx} --JvmMs=${tomcat_xms} ++JvmOptions=`"-javaagent:'${tomcat_base_dir}\glowroot\glowroot.jar'`" --Startup=auto"
} else {
	cmd.exe /c "${tomcatExe} //US//${tomcat_service_name} --JvmMx=${tomcat_xmx} --JvmMs=${tomcat_xms} --Startup=auto"
}
Set-Location $current_path

# Start Tomcat service
Start-Service -Name $tomcat_service_name
Write-Log "Started service ${tomcat_service_name}" -Level INFO

Write-Log "Tomcat v${tomcat_version} and Glowroot v${glowroot_version} installed and configured successfully." -Level INFO
