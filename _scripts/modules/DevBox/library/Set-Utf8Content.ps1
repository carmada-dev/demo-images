function Set-Utf8Content() {

    param (
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string] $Content,

        [switch] $Force, 
        [switch] $PassThru 
    )

    # Enforce the parent directory exists
    if ($Force) { New-Item -Path (Split-Path $Path -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

    # Write the content to the file with UTF-8 encoding (without BOM)
    [System.IO.File]::WriteAllLines($Path, $Content, (New-Object System.Text.UTF8Encoding $False))

    # Return the content if PassThru is specified
    if ($PassThru) { return $Content }
}

Export-ModuleMember -Function  Set-Utf8Content