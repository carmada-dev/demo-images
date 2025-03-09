function Set-Utf8Content() {

    param (
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string] $Content,

        [parameter(Mandatory=$false)]
        [switch] $PassThru 
    )

    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($Path, $Content, $Utf8NoBomEncoding)

    if ($PassThru) { return $Content }
}

Export-ModuleMember -Function  Set-Utf8Content