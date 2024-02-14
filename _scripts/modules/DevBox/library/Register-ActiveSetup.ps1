function Register-ActiveSetup {

    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $false)]
        [string] $Name,

        [switch] $Elevate,
        [switch] $Enabled
    )

    $Path = [System.IO.Path]::GetFullPath([System.Environment]::ExpandEnvironmentVariables($Path))

    $activeSetupFolder = Join-Path $env:DEVBOX_HOME 'ActiveSetup'
    $activeSetupScript = Join-Path $activeSetupFolder (&{ if ($Name) { $Name } else { [System.IO.Path]::GetFileName($Path) } })
    
    if (-not($Path.StartsWith($activeSetupFolder))) {
        New-Item -Path $activeSetupFolder -ItemType Directory -Force | Out-Null # ensure active setup root folder exists
        $Path = Copy-Item -Path $Path -Destination $activeSetupScript -Force -PassThru | Select-Object -ExpandProperty Fullname
    }

    $activeSetupId = $Path | ConvertTo-GUID 
    $activeSetupCmd = "cmd /min /c `"set __COMPAT_LAYER=RUNASINVOKER && PowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Maximized -File `"$Path`"`""
    $activeSetupKeyPath = 'HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components'
    $activeSetupKeyEnabled = [int]$Enabled.ToBool()
    
    $activeSetupKey = Get-ChildItem -Path $activeSetupKeyPath `
        | Select-Object { Split-Path $_.Name -Leaf } `
        | Where-Object { $_ -match "devbox-\d+-$activeSetupId" } `
        | Select-Object -First 1

    if ($activeSetupKey) {

        Write-Host "- Update ActiveSetup Task: $activeSetupKey"

        Set-ItemProperty -Path $activeSetupKey -Name 'StubPath' -Value $activeSetupCmd -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $activeSetupKey -Name 'IsInstalled' -Value $activeSetupKeyEnabled -ErrorAction SilentlyContinue | Out-Null

    } else {

        $activeSetupTimestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
        $activeSetupKey = Join-Path $activeSetupKeyPath "devbox-$activeSetupTimestamp-$activeSetupId"

        Write-Host "- Register ActiveSetup Task: $activeSetupKey"

        New-Item -Path $activeSetupKey -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name '(Default)' -Value ([System.IO.Path]::GetFileNameWithoutExtension($Path)) -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name 'StubPath' -Value $activeSetupCmd -PropertyType 'ExpandString' -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name 'Version' -Value ((Get-Date -Format 'yyyy,MMdd,HHmm').ToString()) -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name 'IsInstalled' -Value $activeSetupKeyEnabled -PropertyType 'DWord' -ErrorAction SilentlyContinue | Out-Null

    }
}

Export-ModuleMember -Function Register-ActiveSetup