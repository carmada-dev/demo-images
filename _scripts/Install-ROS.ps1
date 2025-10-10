Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-ROS.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function New-RosInstallScript() {

	$rosInstallScript = Join-Path $env:TEMP 'install_ros.sh'

	if (-not(Test-Path $rosInstallScript -PathType Leaf)) {

@"
#!/bin/bash
set -e

# Setup sources
sudo apt update && sudo apt install -y curl gnupg lsb-release
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=`$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu `$(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

# Install ROS
sudo apt update 
sudo apt install -y ros-jazzy-desktop ros-dev-tools

# Source ROS environment
echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc

"@ -replace "`r`n", "`n" | Set-Content $rosInstallScript -Force

	}

	return $rosInstallScript
}

function Clear-WslOutput() {

    param (
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
        [string] $Output
    )

    if ($Output) {
        return ($Output -replace "`r`n?", "`r`n" -replace "`0", "" -split "`r?`n" | Where-Object { -not ([System.String]::IsNullOrWhiteSpace($_)) } | Out-String) -replace "`r?`n$", ''
    } else {
        return $Output
    }
}

function ConvertTo-MntPath() {

	param (
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
		[string] $Path
	)

	$path = $Path -replace '\\', '/'
	$drive, $rest = $path -split ":", 2
	$drive = $drive.ToLower()

	if ($rest) {

		$rest = $rest -replace '^\/*', ''
		return "/mnt/$drive/$rest"

	} else {

		return "/mnt/$drive"

	}
}

function Wait-DistroReady() {

	param (
		[Parameter(Mandatory=$true)]
		[string] $DistroName 
	)

	Write-Host ">>> Waiting for WSL Distro '$DistroName' to be ready ..."

	$maxRetries = 30
	$retryCount = 0
	$delaySeconds = 10

	while ($retryCount -lt $maxRetries) {

		try {
			Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName -- echo Distro is ready" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host
			return
		} catch {
			Write-Host "Distro '$DistroName' is not ready yet. Retrying in $delaySeconds seconds..."
			Start-Sleep -Seconds $delaySeconds
		}

		$retryCount++
	}

	throw "Distro '$DistroName' did not become ready after $($maxRetries * $delaySeconds) seconds."
}

Invoke-ScriptSection -Title "Installing ROS" -ScriptBlock {

	$DistroName = "ROS2"
	$DistroHome = Join-Path $env:USERPROFILE "WSL\$DistroName"
	$DistroOffline = Join-Path $env:DEVBOX_HOME "WSL\$DistroName"
	$DistroRootFs = Join-Path $DistroOffline "rootfs.tar.gz"

	if (-not(Get-Command wsl -ErrorAction SilentlyContinue)) {
		Write-Host "Could not find wsl.exe"
		exit 1
	} 

	# Ensure WSL distro home exists
	New-Item -Path $DistroOffline -ItemType Directory -Force | Out-Null

	if (Test-IsPacker) {

		$ROSInstallScript = New-RosInstallScript | ConvertTo-MntPath

		Write-Host ">>> Downloading distro rootfs ..."
		Invoke-FileDownload -Url 'https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64-wsl.rootfs.tar.gz' | Move-Item -Destination $DistroRootFs -Force

		Write-Host ">>> Importing $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--import $DistroName $DistroHome $DistroRootFs --version 2" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		# Write-Host ">>> Register default user for $DistroName WSL instance ..."
		# Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName --user root -- bash -c 'useradd -m $($env:USERNAME) && echo `\`"$($env:USERNAME):automation`\`" | chpasswd && echo `"$($env:USERNAME) ALL=(ALL) NOPASSWD:ALL` >> /etc/sudoers'" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Installing ROS2 into $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName --user root -- bash -c 'chmod +x $ROSInstallScript && bash $ROSInstallScript'" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Exporting ROS2 WSL instance to $DistroRootFs ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--export $DistroName $DistroRootFs" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Unregistering temporary $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--unregister $DistroName"  | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

	} else {

		$adapter = Get-NetAdapter | Where-Object { $_.Status -ne 'Up' -and $_.Name -like 'Ethernet*' } | Select-Object -First 1
		if ($adapter) {
			Write-Host ">>> Creating external switch for ROS (adapter: $($adapter.Name)) ..."
			$switch = New-VMSwitch -Name "ROS" -NetAdapterName $adapter.Name -AllowManagementOS $true -Notes "ROS WSL2 Switch" | Out-Null
		} else {
			Write-Host ">>> Could not find a network adapter to create ROS switch. Available adapters:"
			Get-NetAdapter | Out-String | Write-Host
			exit 1
		}

		# Get total system memory in MB
		$memMB = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1MB
		$memGB = [math]::Round($memMB / 2048)  # Convert to GB and halve
		$swapGB = [math]::Round($memMB / 4096)  # Allocate 25% of total memory as swap

		# Get total logical processors
		$cpuCount = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
		$cpuCount = [math]::Floor($cpuCount / 2)

		# Build .wslconfig content
		# The configuration follows the recommendations from: https://github.com/espenakk/ros2-wsl2-guide
		Write-Host ">>> Configuring WSL with optimizations for ROS ..."
@"
[wsl2]
memory=${memGB}GB
processors=${cpuCount}
swap=${swapGB}GB
networkingMode=bridged
vmSwitch="$($switch.Name)"
"@ | Set-Content -Path "$env:USERPROFILE\.wslconfig" -Force

		Write-Host ">>> Restarting WSL ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--shutdown" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Importing WSL Distro '$DistroName' from $DistroRootFs ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--import $DistroName $DistroHome $DistroRootFs --version 2" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Waiting for $DistroName WSL instance to be imported ..."
		Wait-DistroReady -DistroName $DistroName

		Write-Host ">>> Setting default user for $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName -u root -- bash -c `"echo '[user]\ndefault=$($env:USERNAME)' > /etc/wsl.conf`"" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		$vscode = Get-Command 'code' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		if ($vscode) {

			Write-Host ">>> Installing the Robotics Developer Environment (RDE) extension into VSCode ..."
			Invoke-CommandLine -Command $vscode -Arguments "--install-extension ranch-hand-robotics.rde-pack" | Select-Object -ExpandProperty Output
		}
	}

}