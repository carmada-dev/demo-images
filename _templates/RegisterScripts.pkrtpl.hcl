
function Register-ActiveSetup() {

    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

	$activeSetupKey = "HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components\$prefix$([guid]::NewGuid().ToString('B'))"
	$activeSetupDesc = [System.IO.Path]::GetFileNameWithoutExtension($Path)
	$activeSetupCmd = "powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -Command `"& '$Path'`""
	$activeSetupVer = (Get-Date -Format 'yyMM,ddHH,mmss').ToString()

	if ( -NOT (Test-Path $activeSetupKey)) {
		New-Item -Path $activeSetupKey -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name '(Default)' -Value $activeSetupDesc -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name 'StubPath' -Value $activeSetupCmd -PropertyType 'ExpandString' -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name 'Version' -Value $activeSetupVer -ErrorAction SilentlyContinue | Out-Null
		New-ItemProperty -Path $activeSetupKey -Name 'IsInstalled' -Value 1 -PropertyType 'DWord' -ErrorAction SilentlyContinue | Out-Null
	}
}

$scripts = '${jsonencode(scripts)}' | ConvertFrom-Json
$prefix = '${try(prefix, "")}'

foreach ($script in $scripts) {

	Register-ActiveSetup -Path $script
}
