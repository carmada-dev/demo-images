$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

Invoke-ScriptSection -Title 'Set DevBox access permissions' -ScriptBlock {
	
	if (-not(Get-Module -ListAvailable -Name NTFSSecurity))
	{
		Write-Host ">>> Installing NTFSSecurity Module"
		Install-Module -Name NTFSSecurity -Force
	}

	Write-Host ">>> Importing NTFSSecurity Module"
	Import-Module -Name NTFSSecurity

	Write-Host ">>> Enable NTFS access inheritance on '$($env:DEVBOX_HOME)' (recursive)"
	Get-ChildItem -Path $env:DEVBOX_HOME -Recurse | Enable-NTFSAccessInheritance
}

Invoke-ScriptSection -Title 'Enable Active Setup Tasks' -ScriptBlock {
	Enable-ActiveSetup
}

Invoke-ScriptSection -Title 'Remove APPX packages' -ScriptBlock {

	Get-AppxPackage | ForEach-Object {
		Write-Host "- $($_.PackageFullName)"
		Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue
	}
}

Invoke-ScriptSection -Title 'Cleanup Event Logs' -ScriptBlock {

	$logs = Get-EventLog -List | Select-Object -ExpandProperty Log

	Write-Host ">>> Enforce 'OverwriteAsNeeded' as OverflowAction for all logs"
	Limit-EventLog -LogName $logs -OverflowAction OverwriteAsNeeded 

	Write-Host ">>> Clear all logs"
	Clear-EventLog -LogName $logs
	
	Get-EventLog -List `
	| Format-Table	Log, `
		@{L='Current Size KB'; E={ [System.Math]::ceiling((Get-WmiObject -Class Win32_NTEventLogFile -filter "LogFileName = '$($_.Log)'").FileSize / 1KB) }}, `
		@{L='Maximum Size KB'; E={ $_.MaximumKilobytes }}, `
		@{L='Overflow Action'; E={ $_.OverflowAction }}
}

Invoke-ScriptSection -Title 'Optimize Windows Partition' -ScriptBlock {

	Write-Host ">>> Disable Windows reserved storage"
	Invoke-CommandLine -Command 'dism' -Arguments '/Online /Set-ReservedStorageState /State:Disabled' | Select-Object -ExpandProperty Output | Write-Host

	Write-Host ">>> Check Windows Component Store Health"
	Invoke-CommandLine -Command 'dism' -Arguments '/Online /Cleanup-Image /CheckHealth' | Select-Object -ExpandProperty Output | Write-Host

	if (Test-IsWindows11) {

		Write-Host ">>> Prepare Disk Cleanup Utility"
		Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches" | ForEach-Object { New-ItemProperty -Path "$($_.PSPath)" -Name StateFlags0000 -Value 2 -Type DWORD -Force | Out-Null }

		Write-Host ">>> Run Disk Cleanup Utility"
		Invoke-CommandLine -Command 'cleanmgr' -Arguments '/verylowdisk /sagerun:0' | Select-Object -ExpandProperty Output | Write-Host
	}

	Write-Host ">>> Run free space consolidation"
	Invoke-CommandLine -Command 'defrag' -Arguments 'c: /FreespaceConsolidate /Verbose'

	Write-Host ">>> Run boot optimization"
	Invoke-CommandLine -Command 'defrag' -Arguments 'c: /BootOptimize /Verbose'
}

Invoke-ScriptSection -Title 'Enable Defrag Schedule' -ScriptBlock {

	Get-ScheduledTask ScheduledDefrag | Enable-ScheduledTask | Out-String | Write-Host
}

Invoke-ScriptSection -Title 'Shrink System Partition' -ScriptBlock {

	$partition = Get-Partition | Where-Object { -not($_.IsHidden) } | Sort-Object { $_.DriveLetter } | Select-Object -First 1
	$partitionSize = Get-PartitionSupportedSize -DiskNumber ($partition.DiskNumber) -PartitionNumber ($partition.PartitionNumber)
	
	$devDriveUnused = Get-Volume | Where-Object { $_.DriveLetter -and ($_.FileSystemType -eq 'ReFS') } | Measure-Object -Property SizeRemaining -Sum | Select-Object -ExpandProperty Sum
	if (-not($devDriveUnused)) { $devDriveUnused = 0 }

	$targetSizes = @( 256GB, 512GB, 1024GB, 2048GB )
	$targetSize = $targetSizes | Where-Object { $_ -gt ($partitionSize.SizeMin + $devDriveUnused) } | Select-Object -First 1
	
	if ($targetSize) {
		Write-Host ">>> Resizing System Partition to $([Math]::Round($targetSize / 1GB,2)) GB" 
		Resize-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -Size $targetSize -ErrorAction SilentlyContinue
	} else {
		Write-Host ">>> Keeping System Partition Size ($([Math]::Round($partition.Size / 1GB,2)) GB)" 
	}
}

Invoke-ScriptSection -Title 'Disable AutoLogon' -ScriptBlock {
	$names = 'AutoAdminLogon', 'DefaultUsername', 'DefaultPassword'
	$names | ForEach-Object {
		Write-Host "- Removing key '$_' at HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
		Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name $_ -ErrorAction SilentlyContinue
	}
}

Invoke-ScriptSection -Title 'Enable User Access Control' -ScriptBlock {
	Write-Host "- Setting 'EnableLUA' at HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System to 1"
	Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1 -type DWord -ErrorAction SilentlyContinue
}

Invoke-ScriptSection -Title 'Waiting for Windows Services' -ScriptBlock {
	Write-Host '>>> RdAgent ...'
	while ((Get-Service RdAgent -ErrorAction SilentlyContinue) -and ((Get-Service RdAgent).Status -ne 'Running')) { Start-Sleep -s 5 }
	Write-Host '>>> WindowsAzureTelemetryService ...'
	while ((Get-Service WindowsAzureTelemetryService -ErrorAction SilentlyContinue) -and ((Get-Service WindowsAzureTelemetryService).Status -ne 'Running')) { Start-Sleep -s 5 }
	Write-Host '>>> WindowsAzureGuestAgent ...'
	while ((Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue) -and ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running')) { Start-Sleep -s 5 }
}

Invoke-ScriptSection -Title 'Generalizing System' -ScriptBlock {
	& $env:SystemRoot\System32\Sysprep\Sysprep.exe /generalize /oobe /mode:vm /quiet /quit
	Write-Host '>>> Waiting for generalized state ...'
	while($true) { 
		$imageState = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State | Select-Object -ExpandProperty ImageState
		if($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { 
			Write-Host $imageState
			break 
		} else { 
			Write-Host $imageState
			Start-Sleep -s 10  
		} 
	}
}