function ConvertTo-MaskedString {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Value,
        [Parameter(Mandatory = $false)]
        [string[]] $Mask = @()
    )

    if ($Mask) { $Mask | Sort-Object -Descending { $_.length } | ForEach-Object { $Value = $Value -replace $_, ('*' * $_.Length) } } 
    $Value
}

Export-ModuleMember -Function ConvertTo-MaskedString