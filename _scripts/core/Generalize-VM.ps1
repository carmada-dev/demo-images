# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$volumeCachePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
$volumeCacheKey = "StateFlags0042"

try {
	Get-ChildItem -Path $volumeCachePath -Name | ForEach-Object {
		# set state flags for clean-up run
		New-ItemProperty -Path $volumeCachePath\$_ -Name $volumeCacheKey -PropertyType DWord -Value 2 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-null
	}
	
	Write-Host ">>> Cleaning up system drive ..."
	Start-Process cleanmgr -ArgumentList "/sagerun:42" -Wait -NoNewWindow -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
		
}
finally {

	Get-ChildItem -Path $volumeCachePath -Name | ForEach-Object {
		# remove state flags set before
		Remove-ItemProperty -Path $volumeCachePath\$_ -Name $volumeCacheKey -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-null
	}
}

Write-Host ">>> Disable AutoLogon for elevated task processing ..."
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUsername
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword

Write-Host ">>> Enable User Access Control ..."
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1 -type DWord

Write-Host '>>> Remove APPX packages ...'
Get-AppxPackage | % {
	Write-Host "- $($_.PackageFullName)"
	Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue
}

Write-Host '>>> Waiting for GA Service (RdAgent) to start ...'
while ((Get-Service RdAgent -ErrorAction SilentlyContinue) -and ((Get-Service RdAgent).Status -ne 'Running')) { Start-Sleep -s 5 }

Write-Host '>>> Waiting for GA Service (WindowsAzureTelemetryService) to start ...'
while ((Get-Service WindowsAzureTelemetryService -ErrorAction SilentlyContinue) -and ((Get-Service WindowsAzureTelemetryService).Status -ne 'Running')) { Start-Sleep -s 5 }

Write-Host '>>> Waiting for GA Service (WindowsAzureGuestAgent) to start ...'
while ((Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue) -and ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running')) { Start-Sleep -s 5 }

Write-Host '>>> Sysprepping VM ...'
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /generalize /oobe /mode:vm /quiet /quit

while($true) { 
	$imageState = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State | Select ImageState
	if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { 
		Write-Host $imageState.ImageState
		Start-Sleep -s 10  
	} else { 
		break 
	} 
}
