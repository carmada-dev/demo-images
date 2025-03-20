function ConvertTo-Base64 {
    
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string] $Value
    )

    # the provided value is null or empty - passthru
    if (-not $Value) { return $Value}

    # convert a unicode byte buffer of the provided value
    $buffer = [System.Text.Encoding]::Unicode.GetBytes($Value)

    # convert the byte buffer to a base64 string
    return [Convert]::ToBase64String($buffer)
}

Export-ModuleMember -Function ConvertTo-Base64