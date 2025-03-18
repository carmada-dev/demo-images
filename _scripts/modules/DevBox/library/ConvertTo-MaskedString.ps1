function ConvertTo-MaskedString {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Value,
        [Parameter(Mandatory = $false)]
        [string[]] $Mask = @()
    )

    if ($Value -and $Mask -and $Mask.Count -gt 0) {
        # replace all mask values with asterisks - we start with the longest mask first to ensure that we do not mask a part of a longer mask 
        $Mask | Sort-Object -Descending { $_.length } | ForEach-Object { $Value = $Value -replace $_, ('*' * $_.Length) } 
    } 

    return $Value
}

Export-ModuleMember -Function ConvertTo-MaskedString