function New-AppIcon {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Executable,
        [Parameter(Mandatory = $false)]
        [string] $Path = $null,
        [switch] $Force
    )

    if (-not($Path)) {
        $Path = [System.IO.Path]::ChangeExtension($Executable, ".ico")
    }
    
    try {

        if ($Force -or -not(Test-Path -Path $Path -PathType Leaf)) {
            Using-Object ($stream = New-Object System.IO.MemoryStream) {
                Add-Type -Assembly System.Drawing -ErrorAction SilentlyContinue
                [System.Drawing.Icon]::ExtractAssociatedIcon($Executable).Save($stream)
                $stream.ToArray() | Set-Content -Path $Path -Encoding Byte -Force
            }
        }

    } catch {

        $Path = null
    }

    $Path
}

Export-ModuleMember -Function New-AppIcon