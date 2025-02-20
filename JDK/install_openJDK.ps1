#######################
# Params
#######################
param (
    [string]$jdk_version
)

#######################
# Functions
#######################

# Check if JDK is installed
function Is-JdkInstalled {
    Write-Host "Checking if JDK ${jdk_version} is installed..."

    if (-not (Get-Command -Name java -ErrorAction SilentlyContinue)) {
        Write-Host "'java' command not found. JDK ${jdk_version} is not installed."
        return $false
    }
	
    # Check `java -version` output
    try {
        $javaVersion = (Get-Command java | Select-Object -ExpandProperty Version).toString()
        if ($javaVersion -match "${jdk_version}.*") {
            Write-Host "JDK ${jdk_version} found."
            return $true
        }
    } catch {
        Write-Host "JDK ${jdk_version} not found."
		return $false
    }

    Write-Host "JDK ${jdk_version} not found."
    return $false
}

#######################
# Script
#######################

Write-Host "Init JDK ${jdk_version} installation..."

# Download and install OpenJDK (if not installed)
if (-not (Is-JdkInstalled)) {
	# Check the latest OpenJDK version from Adoptium API
    $response = Invoke-WebRequest -Uri "https://api.adoptium.net/v3/assets/feature_releases/${jdk_version}/ga?architecture=x64&os=windows&image_type=jdk&page_size=1" -UseBasicParsing
    $latest_jdk = ($response.Content | ConvertFrom-Json)[0]

    # Download OpenJDK Package
    $download_url = $latest_jdk.binaries.package.link
    $downloaded_file = ".\OpenJDK-${jdk_version}.zip"
    Write-Host "Download OpenJDK package from: ${download_url}"
    Invoke-WebRequest -Uri $download_url -OutFile $downloaded_file

    # Install OpenJDK
    Write-Host "Unzipping OpenJDK ${jdk_version} binaries package..."
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$downloaded_file_path = Get-Location 
	$zip_file = "${downloaded_file_path}\${downloaded_file}"
	$zipArchive = [System.IO.Compression.ZipFile]::OpenRead(${zip_file})
	$entries = $zipArchive.Entries
	$folderName = $entries | Where-Object { $_.FullName -match '/$' } | Select-Object -First 1

	$java_installation_path = "C:\Program Files\Java\"
	Expand-Archive -Path $downloaded_file -DestinationPath $java_installation_path -Force
    #Remove-Item -Path ${downloaded_file}

	$java_home_path = "${java_installation_path}\${folderName}"
    # Config JAVA_HOME environment variable
    $Env:JAVA_HOME = ${java_home_path}
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $java_home_path, "Machine")
    [Environment]::SetEnvironmentVariable("Path", $Env:Path + ";${java_home_path}\bin\", "Machine")
	$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

    Write-Host "OpenJDK ${jdk_version} installed and configured successfully."
} else {
    Write-Host "JDK ${jdk_version} already installed."
}
