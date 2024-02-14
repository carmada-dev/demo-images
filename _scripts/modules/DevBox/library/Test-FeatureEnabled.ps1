function Test-FeatureEnabled {

    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]] $Name
    )

    if (Test-IsElevated) {

        $enabled = $true
    
        $Name | Foreach-Object {
            $feature = Get-WindowsOptionalFeature -FeatureName $_ -Online -ErrorAction SilentlyContinue 
            if ( -not($feature) ) {
                Write-Error "Windows optional feature '$_' does not exist."
                exit 1
            } 
            $state = ($feature | Select-Object -ExpandProperty State | Out-String) -replace '\r?\n' , ''
            if ( $state -ne "Enabled" ) {
                Write-Host "!!! Windows optional feature '$_' is not enabled (current state: $state)."
                $enabled = $false
            }
        }

        return $enabled

    } else {

        Write-Error "The requested operation requires elevation."
        exit 1
    }
}

Export-ModuleMember -Function Test-FeatureEnabled