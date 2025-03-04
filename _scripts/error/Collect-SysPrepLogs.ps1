# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

@( "$Env:SystemRoot\System32\Sysprep", "$Env:SystemRoot\Panther" ) | Where-Object { Test-Path $_ -PathType Container } | ForEach-Object { 
	Get-ChildItem -Path $_ -Filter '*.log' -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | ForEach-Object { 
		Write-Host "=========================================================================================================="
		Write-Host " SysPrep Log: $_"
		Write-Host "----------------------------------------------------------------------------------------------------------"
		Get-Content -Raw -Path $_
		Write-Host "=========================================================================================================="
	}
}
