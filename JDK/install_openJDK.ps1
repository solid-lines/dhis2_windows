#######################
# Params
#######################
param(
  [Parameter(Mandatory)] $Config
)
$jdk_version = $Config.jdk.version

#######################
# Functions
#######################

# Check if JDK is installed
function Is-JdkInstalled {
    Write-Log "Checking if JDK ${jdk_version} is installed..." -Level INFO 

    if (-not (Get-Command -Name java -ErrorAction SilentlyContinue)) {
        Write-Log "'java' command not found. JDK ${jdk_version} is not installed." -Level INFO
        return $false
    }
	
    # Check `java -version` output
    try {
        $javaVersion = (Get-Command java | Select-Object -ExpandProperty Version).toString()
        if ($javaVersion -match "${jdk_version}.*") {
            Write-Log "JDK ${jdk_version} found." -Level INFO
            return $true
        }
    } catch {
        Write-Log "JDK ${jdk_version} not found."  -Level INFO
		return $false
    }

    Write-Log "JDK ${jdk_version} not found." -Level INFO
    return $false
}

#######################
# Script
#######################

Write-Log "Init JDK ${jdk_version} installation..." -Level INFO
Write-Log "Parameter jdk_version:${jdk_version}" -Level DEBUG

# Download and install OpenJDK (if not installed)
if (-not (Is-JdkInstalled)) {
	# Check the latest OpenJDK version from Adoptium API
    $response = Invoke-WebRequest -Uri "https://api.adoptium.net/v3/assets/feature_releases/${jdk_version}/ga?architecture=x64&os=windows&image_type=jdk&page_size=1" -UseBasicParsing -ErrorAction Stop
    $latest_jdk = ($response.Content | ConvertFrom-Json)[0]

    # Download OpenJDK Package
    $download_url = $latest_jdk.binaries.package.link
    $downloaded_file = ".\OpenJDK-${jdk_version}.zip"
    Write-Log "Download OpenJDK package from: ${download_url}" -Level INFO
    Invoke-WebRequest -Uri $download_url -OutFile $downloaded_file -UseBasicParsing -ErrorAction Stop

    # Install OpenJDK
    Write-Log "Unzipping OpenJDK ${jdk_version} binaries package..." -Level INFO
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$downloaded_file_path = Get-Location 
	$zip_file = "${downloaded_file_path}\${downloaded_file}"
	$zipArchive = [System.IO.Compression.ZipFile]::OpenRead(${zip_file})
	$entries = $zipArchive.Entries
	$folderName = $entries | Where-Object { $_.FullName -match '/$' } | Select-Object -First 1

	$java_installation_path = "C:\Program Files\Java\"
	Expand-Archive -Path $downloaded_file -DestinationPath $java_installation_path -Force
    #Remove-Item -Path ${downloaded_file} -Recurse -Force

	$java_home_path = "${java_installation_path}\${folderName}"
    # Config JAVA_HOME environment variable
    $Env:JAVA_HOME = ${java_home_path}
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $java_home_path, "Machine")
    [Environment]::SetEnvironmentVariable("Path", $Env:Path + ";${java_home_path}\bin\", "Machine")
	$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

    Write-Log "OpenJDK ${jdk_version} installed and configured successfully." -Level INFO
} else {
    Write-Log "JDK ${jdk_version} already installed." -Level INFO
}
