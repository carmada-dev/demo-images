# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ErrorActionPreference = "SilentlyContinue"

$logFiles = @(
	"$Env:SystemRoot\System32\LogFiles\setupcln\setupact.log",
	"$Env:SystemRoot\System32\LogFiles\setupcln\setuperr.log"
)

$logFiles | ? { (Test-Path $_) -and ($_.Length -gt 0) } | % {

	Write-Host "=========================================================================================================="
	Write-Host " SysPrep Log: $_"
	Write-Host "----------------------------------------------------------------------------------------------------------"
	Get-Content -Raw -Path $_
	Write-Host "=========================================================================================================="
}
