function Test-SoftwareInstalled {

    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]] $Name
    )

    $missing = $false
    $Name | Foreach-Object { $missing = -not([boolean](Get-SoftwareInfo -Name $_)) -or $missing }

    return -not($missing)
}

Export-ModuleMember -Function Test-SoftwareInstalled