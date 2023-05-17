# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ErrorActionPreference = "SilentlyContinue"

$diagnosticInfo = @(winget --info) | Where-Object { $_.StartsWith('Logs:') } | Select-Object -First 1
$diagnosticPath = $diagnosticInfo.Split(':') | Select-Object -Last 1 
$diagnosticPath = [Environment]::ExpandEnvironmentVariables($diagnosticPath.Trim())

Get-ChildItem -Path $diagnosticPath -Filter *.log -File | ? { $_.Length -gt 0 } | Sort-Object LastWriteTime | % {

	Write-Host "=========================================================================================================="
	Write-Host " WinGet Log: $_"
	Write-Host "=========================================================================================================="
	Get-Content -Raw -Path $_
	Write-Host "=========================================================================================================="
}
