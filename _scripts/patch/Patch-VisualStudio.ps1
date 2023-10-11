# # Copyright (c) Microsoft Corporation.
# # Licensed under the MIT License.

param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = [boolean]($env:PACKER_BUILD_NAME)
)

$ProgressPreference = 'SilentlyContinue'	# hide any progress output

function Using-Object
{
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [Object] $InputObject,
 
        [Parameter(Mandatory = $true)]
        [scriptblock] $ScriptBlock
    )
 
    try
    {
        . $ScriptBlock
    }
    finally
    {
        if ($null -ne $InputObject -and $InputObject -is [System.IDisposable])
        {
            $InputObject.Dispose()
        }
    }
}

function Invoke-CommandLine() {

    param(
        [Parameter(Mandatory=$true)]
        [string] $Command,
        [Parameter(Mandatory=$false)]
        [string] $Arguments,
        [Parameter(Mandatory=$false)]
        [string] $WorkingDirectory = $pwd.Path,

		[switch] $IgnoreStdOut,
        [switch] $IgnoreStdErr
    )

    try
    {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $Command
        $processInfo.RedirectStandardError = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.Arguments = $Arguments
        $processInfo.WorkingDirectory = $WorkingDirectory

        Using-Object ($process = New-Object System.Diagnostics.Process) {
        
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null

            $stdOut = (&{ if ($IgnoreStdOut) { $null } else { $process.StandardOutput.ReadToEnd() } })
            $stdErr = (&{ if ($IgnoreStdErr) { $null } else { $process.StandardError.ReadToEnd() } })

            $process.WaitForExit()

            [PSCustomObject]@{
                StdOut 	 = [string] $stdOut
                StdErr   = [string] $stdErr
                ExitCode = $process.ExitCode
            }
        }
    }
    catch
    {
        exit
    }
}

function Register-ActiveSetup() {

    param (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $false)]
        [string] $Key = ($Path | ConvertTo-GUID)
    )

	$activeSetupKey = "HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components\>$($Key | ConvertTo-GUID -Format 'B')"
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

function Invoke-VSIXInstaller() {

	param (
		[Parameter(Mandatory = $true)]
		[string] $Edition,
		[Parameter(Mandatory = $true)]
		[string] $Installer
	)

	$ErrorActionPreference = 'SilentlyContinue'

	$visxFolder = Join-Path -Path $env:DEVBOX_HOME -ChildPath "Artifacts/$Edition"
	if (Test-Path -Path $vsixHome -PathType Container) {
		Get-ChildItem -Path $visxFolder -Filter '*.visx' | Select-Object -ExpandProperty FullName | ForEach-Object -Begin { Write-Host ">>> $Edition" } -Process {

			try
			{
				Write-Host "- Installing VisualStudio Extension: $_"
				Invoke-CommandLine -Command $Installer -Argument "$(if ($Packer) { '/a' }) /q `"$visx`"".Trim() | Select-Object -ExpandProperty StdOut
			}
			catch
			{
				# swallow and resume
			}
		}
	}
}

if (-not($Packer)) {

	Write-Host ">>> Starting transcript ..."
	Start-Transcript -Path ([System.IO.Path]::ChangeExtension($MyInvocation.MyCommand.Path, 'log')) -Append | Out-Null
}

$vswhereExe = Get-ChildItem -Path $env:LOCALAPPDATA -Filter 'vswhere.exe' -Recurse | Select-Object -First 1 -ExpandProperty Fullname
if ($vswhereExe) {

	Invoke-CommandLine -Command $vswhereExe -Arguments '-all -prerelease -utf8 -format json' | Select-Object -ExpandProperty StdOut | ConvertFrom-Json | ForEach-Object { 
		Invoke-VSIXInstaller -Edition "$($_.displayName) $(if ($_.isPrerelease) {'PRE'} else {''})".Trim() -Installer (Join-Path $_.enginePath 'VSIXInstaller.exe')
	}

	if ($Packer) {
		Write-Host ">>> Register Patch-VisualStudio via ActiveSetup"
		Register-ActiveSetup -Path (Copy-Item -Path $MyInvocation.MyCommand.Path -Destination (Join-Path -Path $env:DEVBOX_HOME -ChildPath 'ActiveSetup/Patch-VisualStudio.ps1') -Force -PassThru | Select-Object -ExpandProperty Fullname)
	}
	
} else {

	throw "Could not find 'vswhere.exe'"
}
