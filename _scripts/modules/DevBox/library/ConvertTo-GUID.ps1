function ConvertTo-GUID {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Value,
        [Parameter(Mandatory = $false)]
        [string] $Format = 'D',
        [switch] $Raw
    )

    Using-Object ($md5 = [System.Security.Cryptography.MD5]::Create()) {
        $buffer = $md5.ComputeHash([System.Text.Encoding]::Default.GetBytes($Value))
        $guid = [guid]::new($buffer)
        if ($Raw) { $guid; } else { $guid.ToString($Format); }
    }
}

Export-ModuleMember -Function ConvertTo-GUID