# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=========================================================================================================="
Write-Host " Appx Log:"
Write-Host "----------------------------------------------------------------------------------------------------------"
Get-AppxLog -All | Where-Object { $_.TimeCreated -gt (Get-Date).AddDays(-1) }
Write-Host "=========================================================================================================="
