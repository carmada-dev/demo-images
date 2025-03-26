function Set-Utf8Content() {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string] $Content,

        [switch] $Force, 
        [switch] $PassThru 
    )

    try {

        # Enforce the parent directory exists
        if ($Force) { New-Item -Path (Split-Path $Path -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }

        # Write the content to the file with UTF-8 encoding (without BOM)
        [System.IO.File]::WriteAllLines($Path, $Content, (New-Object System.Text.UTF8Encoding $False))

        # Return the content if PassThru is specified
        if ($PassThru) { return $Content }

    } catch {

        Write-Error "!!! Failed to write content to $Path: $($_.Exception.Message)" -ErrorAction $ErrorActionPreference
    }
}

Export-ModuleMember -Function  Set-Utf8Content