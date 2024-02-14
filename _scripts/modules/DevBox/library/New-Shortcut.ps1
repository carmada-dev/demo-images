function New-Shortcut {
    
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Target,
        [Parameter(Mandatory = $false)]
        [string] $Arguments = '',
        [Parameter(Mandatory = $false)]
        [string] $Icon = '',
        [switch] $Force
    )

    if (-not($Icon) -and ([IO.Path]::GetExtension($Target) -eq '.exe') ) {
        $Icon = $Target | New-AppIcon
    }
    if ($Force) {
        Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
    }

	$Shell = New-Object -ComObject ("WScript.Shell")
	$Shortcut = $Shell.CreateShortcut($Path)
	$Shortcut.TargetPath = "`"$Target`""
	$Shortcut.Arguments = $Arguments
    $Shortcut.IconLocation = $Icon
	$Shortcut.Save()

    $Path
}

Export-ModuleMember -Function New-Shortcut