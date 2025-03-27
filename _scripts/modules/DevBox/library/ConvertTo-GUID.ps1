function ConvertTo-GUID {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Value,
        [Parameter(Mandatory = $false)]
        [string] $Format = 'D',
        [switch] $Invariant,
        [switch] $Raw
    )

    Using-Object ($md5 = [System.Security.Cryptography.MD5]::Create()) {
        $source = "$(&{ if ($Invariant) { $Value.ToUpperInvariant() } else { $Value } })"
        $buffer = $md5.ComputeHash([System.Text.Encoding]::Default.GetBytes($source))
        $guid = [guid]::new($buffer)
        if ($Raw) { $guid; } else { $guid.ToString($Format); }
    }
}

Export-ModuleMember -Function ConvertTo-GUID