function Get-SoftwareInfo {

	param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
		[string] $Name
	)

	Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" | `
		Where-Object { $_.GetValue('DisplayName') -like $Name } | `
		Select-Object -First 1 `
			@{ Label='Name'; Expression={$_.GetValue('DisplayName')} }, `
			@{ Label='Version'; Expression={$_.GetValue('DisplayVersion')} }, `
			@{ Label='Publisher'; Expression={$_.GetValue('Publisher')} }, `
			@{ Label='Location'; Expression={$_.GetValue('InstallLocation')} }
}

Export-ModuleMember -Function Get-SoftwareInfo