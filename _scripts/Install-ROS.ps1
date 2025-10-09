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

	if (not(Test-Path $rosInstallScript -PathType Leaf)) {

@"
#!/bin/bash
set -e

# Setup sources
sudo apt update && sudo apt install -y curl gnupg lsb-release
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu \$(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

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

function Optimize-WSL {

}

Invoke-ScriptSection -Title "Installing ROS" -ScriptBlock {

	$DistroHome = Join-Path $env:DEVBOX_HOME "WSL\ROS"

	if (-not(Get-Command wsl -ErrorAction SilentlyContinue)) {

		Write-Host "Could not find wsl.exe"
		exit 1

	} else {

		# Get total system memory in MB
		$memMB = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1MB
		$memGB = [math]::Round($memMB / 2048)  # Convert to GB and halve

		# Get total logical processors
		$cpuCount = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
		$cpuCount = [math]::Floor($cpuCount / 2)

		# Build .wslconfig content
		Write-Host ">>> Configuring WSL with $memGB GB memory and $cpuCount processors ..."
		$wslConfig = @"
[wsl2]
memory=${memGB}GB
processors=${cpuCount}
swap=0
localhostForwarding=true
nestedVirtualization=true
"@ | Set-Content -Path "$env:USERPROFILE\.wslconfig" -Force

		Write-Host "Restarting WSL ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--shutdown" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

	}

	# Ensure WSL distro home exists
	New-Item -Path $DistroHome -ItemType Directory -Force | Out-Null

	if (Test-IsPacker) {

		$DistroName = "Ubuntu-24.04"
		$ROSInstallScript = New-RosInstallScript | ConvertTo-MntPath

		Write-Host ">>> Creating $DistroName WSL instance for ROS ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--install -d $DistroName" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host	

		Write-Host ">>> Waiting for $DistroName WSL instance to be provisioned ..."
		Wait-DistroReady -DistroName $DistroName

		Write-Host ">>> Installing ROS into $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName -- bash -c 'chmod +x $ROSInstallScript && bash $ROSInstallScript'" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Exporting ROS WSL instance to $DistroHome\rootfs.tar ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--export $DistroName $DistroHome\rootfs.tar" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

	} else {

		$DistroName = Split-Path $DistroHome -Leaf

		write-Host ">>> Importing WSL Distro '$DistroName' from $DistroHome\rootfs.tar ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--import $DistroName $env:USERPROFILE\WSL\$DistroName $DistroHome\rootfs.tar --version 2" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Waiting for $DistroName WSL instance to be imported ..."
		Wait-DistroReady -DistroName $DistroName

		Write-Host ">>> Setting default user for $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName -u root -- bash -c 'echo '[user]\ndefault=$($env:USERNAME)' > /etc/wsl.conf'" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host
	}

}