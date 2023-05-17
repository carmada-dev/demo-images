# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ErrorActionPreference = "SilentlyContinue"

$logFiles = @(
	"$Env:SystemRoot\System32\Sysprep\Panther\setupact.log",
	"$Env:SystemRoot\System32\Sysprep\Panther\setuperr.log",

	"$Env:SystemRoot\System32\Sysprep\setupact.log",
	"$Env:SystemRoot\System32\Sysprep\setuperr.log",

	"$Env:SystemRoot\Panther\UnattendGC\setupact.log",
	"$Env:SystemRoot\Panther\UnattendGC\setuperr.log",

	"$Env:SystemRoot\Panther\setupact.log",
	"$Env:SystemRoot\Panther\setuperr.log"
)

$logFiles | ? { (Test-Path $_) -and ($_.Length -gt 0) } | % {

	Write-Host "=========================================================================================================="
	Write-Host " SysPrep Log: $_"
	Write-Host "=========================================================================================================="
	Get-Content -Raw -Path $_
	Write-Host "=========================================================================================================="
}
