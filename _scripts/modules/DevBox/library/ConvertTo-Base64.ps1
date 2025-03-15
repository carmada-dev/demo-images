function ConvertTo-Base64 {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Value
    )

    $buffer = [System.Text.Encoding]::Unicode.GetBytes($Value)

    return [Convert]::ToBase64String($buffer)
}

Export-ModuleMember -Function ConvertTo-Base64