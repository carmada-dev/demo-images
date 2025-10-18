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

function New-ToolsShortcut() {

	param (
		[Parameter(Mandatory=$true)]
		[string] $DistroName,

		[Parameter(Mandatory=$true)]
		[string] $ShortcutName,

		[Parameter(Mandatory=$true)]
		[string] $ShortcutCommand
	)

	Write-Host ">>> Creating shortcut '$ShortcutName' for distro '${DistroName}': $ShortcutCommand ..."

	$shortcutPath = Join-Path $env:USERPROFILE "Desktop\$ShortcutName.lnk"
	$bashCommand = "source /opt/ros/humble/setup.bash && $ShortcutCommand"

	# Remove existing shortcut file if it exists
	Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue

	$WshShell = New-Object -ComObject WScript.Shell
	$Shortcut = $WshShell.CreateShortcut($shortcutPath)
	$Shortcut.TargetPath = "C:\Windows\System32\wsl.exe"
	$Shortcut.Arguments = "-d $DistroName -- bash -c `"$bashCommand`""
	$Shortcut.IconLocation = "C:\Windows\System32\wsl.exe,0"
	$Shortcut.WindowStyle = 7  # 7 = Minimized window
	$Shortcut.Save()
}

function New-RosInstallScript() {

	$rosInstallScript = Join-Path $env:TEMP 'install_ros.sh'

	if (-not(Test-Path $rosInstallScript -PathType Leaf)) {

		@(
			"#!/bin/bash",
			"set -e",

			"# Initial update and base packages",
			"sudo apt update",
			"sudo apt install -y locales software-properties-common curl",

			"# Locale setup",
			"sudo locale-gen en_US.UTF-8",
			"sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8",
			"export LANG=en_US.UTF-8",

			"# Add universe repo and ROS key",
			"sudo add-apt-repository -y universe",
			"curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | sudo apt-key add -",
			"echo `"deb [arch=amd64 signed-by=/etc/apt/trusted.gpg] http://packages.ros.org/ros2/ubuntu jammy main`" | sudo tee /etc/apt/sources.list.d/ros2.list",

			"# Final update after all sources added",
			"sudo apt update",
			"sudo apt install -y ros-humble-desktop ros-humble-foxglove-bridge ros-humble-urdf-tutorial python3-launchpadlib python3-colcon-common-extensions python3-rosdep python3-argcomplete",

			"# Shell integration",
			"echo `"source /opt/ros/humble/setup.bash`" | sudo tee -a /etc/bash.bashrc",
			"source /etc/bash.bashrc"

		) -join "`n" | Set-Content $rosInstallScript -Force

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

	# Ensure WSL distro home and offline folder 
	New-Item -Path $DistroOffline -ItemType Directory -Force | Out-Null
	New-Item -Path $DistroHome -ItemType Directory -Force | Out-Null

	if (Test-IsPacker) {

		$ROSInstallScript = New-RosInstallScript | ConvertTo-MntPath

		Write-Host ">>> Downloading distro rootfs ..."
		$temp = Invoke-FileDownload -Url 'https://cloud-images.ubuntu.com/wsl/jammy/current/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz'

		Write-Host ">>> Moving $temp to $DistroRootFs ..."
		Move-Item -Path $temp -Destination $DistroRootFs -Force | Out-Null

		Write-Host ">>> Importing $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--import $DistroName $DistroHome $DistroRootFs --version 2" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Installing ROS2 into $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName --user root -- bash -c 'chmod +x $ROSInstallScript && bash $ROSInstallScript'" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Exporting ROS2 WSL instance to $DistroRootFs ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--export $DistroName $DistroRootFs" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Unregistering temporary $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--unregister $DistroName"  | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

	} else {
	
		# Get total system memory in MB
		$memMB = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1MB
		$memGB = [math]::Round($memMB / 2048)  # Convert to GB and halve
		$swapGB = [math]::Round($memMB / 4096)  # Allocate 25% of total memory as swap

		# Get total logical processors
		$cpuCount = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
		$cpuCount = [math]::Floor($cpuCount / 2)

		# Build .wslconfig content		
		Write-Host ">>> Configuring WSL with optimizations for ROS ..."
		@(

			"[wsl2]",
			"memory=${memGB}GB",
			"processors=${cpuCount}",
			"swap=${swapGB}GB",
			"localhostForwarding=true"

		) -join "`r`n" | Set-Content -Path "$env:USERPROFILE\.wslconfig" -Force

		Write-Host ">>> Restarting WSL ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--shutdown" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Importing WSL Distro '$DistroName' from $DistroRootFs ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--import $DistroName $DistroHome $DistroRootFs --version 2" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		Write-Host ">>> Waiting for $DistroName WSL instance to be imported ..."
		Wait-DistroReady -DistroName $DistroName

		Write-Host ">>> Configure $DistroName WSL instance ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "-d $DistroName -u root -- bash -c 'echo -e `"[boot]`\nsystemd=true`" > /etc/wsl.conf'" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

        Write-Host ">>> Enforce $DistroName WSL instance to be the default ..."
		Invoke-CommandLine -Command 'wsl' -Arguments "--set-default $DistroName" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

		New-ToolsShortcut -DistroName $DistroName -ShortcutName "RViz2" -ShortcutCommand "rviz2"
		New-ToolsShortcut -DistroName $DistroName -ShortcutName "RQT" -ShortcutCommand "rqt"
		New-ToolsShortcut -DistroName $DistroName -ShortcutName "Foxglove Bridge" -ShortcutCommand "ros2 run foxglove_bridge foxglove_bridge"
		
		Write-Host ">>> Installing Foxglove Studio ..."
		Invoke-CommandLine -Command (Invoke-FileDownload -Url 'https://get.foxglove.dev/desktop/latest/foxglove-latest-win.exe') -Arguments "/S" | Select-Object -ExpandProperty Output

		$vscode = Get-Command 'code' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		if ($vscode) {

			Write-Host ">>> Installing the Robotics Developer Environment (RDE) extension into VSCode ..."
			Invoke-CommandLine -Command $vscode -Arguments "--install-extension ranch-hand-robotics.rde-pack" | Select-Object -ExpandProperty Output

			Write-Host ">>> Install VSCode server into $DistroName WSL instance ..."
			Invoke-CommandLine -Command $vscode -Arguments "--remote wsl+$DistroName ~" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

			Write-Host ">>> Terminate all VSCode instances temporarily created ..."
			Stop-Process -Name Code -Force | Out-Null
		}
	}

}