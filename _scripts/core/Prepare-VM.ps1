# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ErrorActionPreference = "SilentlyContinue"

If ([string]::IsNullOrEmpty($Env:ADMIN_USERNAME)) { Throw "Env:ADMIN_USERNAME must be set" }
If ([string]::IsNullOrEmpty($Env:ADMIN_PASSWORD)) { Throw "Env:ADMIN_PASSWORD must be set" }

Write-Host ">>> Setting DevBox environment variables ..."
[Environment]::SetEnvironmentVariable("DEVBOX_HOME", $devboxHome, [System.EnvironmentVariableTarget]::Machine)
Get-ChildItem -Path Env:DEVBOX_* | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $_.Value, [System.EnvironmentVariableTarget]::Machine) }

Write-Host ">>> Enabling AutoLogon for elevated task processing ..."
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value 1 -type String
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUsername -Value "$Env:ADMIN_USERNAME" -type String
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -Value "$Env:ADMIN_PASSWORD" -type String

Write-Host ">>> Disabling User Access Control ..."
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 0 -type DWord

Write-Host ">>> Removing existing SysPrep logs ..."
Remove-Item -Path $env:SystemRoot\Panther -Recurse -Force | Out-Null
Remove-Item -Path $env:SystemRoot\System32\Sysprep\Panther -Recurse -Force | Out-Null
Remove-Item -Path $Env:SystemRoot\System32\Sysprep\unattend.xml -Force | Out-Null

Write-Host ">>> Enabling Windows Developer Mode ..."
$DevModeRegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
if (-not(Test-Path -Path $DevModeRegKeyPath)) { New-Item -Path $RegistryKeyPath -ItemType Directory -Force }
New-ItemProperty -Path $DevModeRegKeyPath -Name AllowDevelopmentWithoutDevLicense -PropertyType DWORD -Value 1 -Force

Write-Host ">>> Enabling DevBox Hibernate Support ..."
Enable-WindowsOptionalFeature -FeatureName "VirtualMachinePlatform" -Online -All -NoRestart | Out-null
$HypervisorEnforcedCodeIntegrityPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
if (-not(Test-Path -Path $HypervisorEnforcedCodeIntegrityPath)) { New-Item -Path $HypervisorEnforcedCodeIntegrityPath -ItemType Directory -Force }
New-ItemProperty -Path $HypervisorEnforcedCodeIntegrityPath -Name Enabled -PropertyType DWORD -Value 0 -Force
