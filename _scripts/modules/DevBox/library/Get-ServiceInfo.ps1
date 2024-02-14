function Get-ServiceInfo {

	param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
		[string] $Name
	)

    Get-WmiObject win32_service | Where-Object { $_.Name -eq $Name } | Select-Object -First 1 Name, DisplayName, State, PathName
}

Export-ModuleMember -Function Get-ServiceInfo