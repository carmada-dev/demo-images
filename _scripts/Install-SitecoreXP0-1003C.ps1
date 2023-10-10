# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = [boolean]($env:PACKER_BUILD_NAME)
)

$ProgressPreference = 'SilentlyContinue'	# hide any progress output

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-FileDownload() {
	param(
		[Parameter(Mandatory=$true)][string] $url,
		[Parameter(Mandatory=$false)][string] $name,
		[Parameter(Mandatory=$false)][boolean] $expand		
	)

	$path = Join-Path -path $env:temp -ChildPath (Split-Path $url -leaf)
	if ($name) { $path = Join-Path -path $env:temp -ChildPath $name }
	
	Write-Host ">>> Downloading $url > $path"
	Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
	
	if ($expand) {
		$arch = Join-Path -path $env:temp -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($path))

        Write-Host ">>> Expanding $path > $arch"
		Expand-Archive -Path $path -DestinationPath $arch -Force

		return $arch
	}
	
	return $path
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

function Get-LatestLink($releaseMatch, $assetMatch) {

	$uri = "https://api.github.com/repos/Sitecore/container-deployment/releases"
	$get = Invoke-RestMethod -uri $uri -Method Get -ErrorAction stop
    $release = $get | Where-Object name -Match $releaseMatch | Select-Object -First 1
	$asset = $release.assets | Where-Object name -Match $assetMatch | Select-Object -First 1
	return $asset.browser_download_url

}

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

function ConvertTo-GUID {
    
    param (
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

$scd = 'C:\Sitecore'
$tar = Join-Path $scd 'images.tar'

$dockerExe = Get-ChildItem -Path (Join-Path $env:ProgramFiles "Docker") -Filter "docker.exe" -Recurse | Select-Object -First 1 -ExpandProperty Fullname
$dockerComposeExe = Get-ChildItem -Path (Join-Path $env:ProgramFiles "Docker") -Filter "docker-compose.exe" -Recurse | Select-Object -First 1 -ExpandProperty Fullname
$dockerDaemonExe = Get-ChildItem -Path (Join-Path $env:ProgramFiles "Docker") -Filter "dockerd.exe" -Recurse | Select-Object -First 1 -ExpandProperty Fullname

if ($dockerDaemonExe) { 
	Write-Host ">>> Register Docker Daemon"
	Invoke-CommandLine -Command $dockerDaemonExe -Arguments "--register-service" | Select-Object -ExpandProperty StdErr
} else {
	throw "Could not find Docker Daemon - please install Docker Desktop"
}

Write-Host ">>> Starting Docker services "
Start-Service *docker* 

Write-Host ">>> Docker service overview"
Get-Service *docker*

$path = Join-Path $env:APPDATA "Docker/settings.json" 
if (Test-Path $path -PathType Leaf) {

    $json = Get-Content -Path $path -Raw | ConvertFrom-Json
    if (-not($json.useWindowsContainers)) {

        Write-Host ">>> Enabling Windows Container in Docker"
        $json.useWindowsContainers = $true
        $json | ConvertTo-Json | Set-Content -Path $path

        Write-Host ">>> Restarting Docker services"
        Restart-Service *docker* -Force 
    }
}

if ($Packer) {
	
	Write-Host "================================================================================="
	Write-Host "= Initializing Sitecore Container Deployment (Packer Mode)"
	Write-Host "================================================================================="

	$url = Get-LatestLink -ReleaseMatch "SXP Sitecore Container Deployment 10.3..*" -AssetMatch "SitecoreContainerDeployment.*.zip"
	$tmp = Invoke-FileDownload -url $url -name "SitecoreContainerDeployment.zip" -expand $true

	Write-Host ">>> Assemble Sitecore Container Deployment files into $scd"
	Remove-Item $scd -Recurse -Force -ErrorAction SilentlyContinue
	$xp0 = Get-ChildItem -Path "$tmp\compose\*\xp0" -Directory | Select-Object -Last 1 -ExpandProperty FullName
	Copy-Item -Path $xp0 -Destination "$scd\" -Recurse -Force | Select-Object -expand FullName
	$lic = Join-Path -Path $env:DEVBOX_HOME -ChildPath 'Artifacts/Sitecore/license.zip'
	Expand-Archive -Path $lic -DestinationPath $scd -Force

	Write-Host ">>> Register Sitecore restore via ActiveSetup"
	Register-ActiveSetup -Path (Copy-Item -Path $MyInvocation.MyCommand.Definition -Destination "$scd/sitecore.ps1" -Force -PassThru | Select-Object -ExpandProperty Fullname)

	Write-Host ">>> Switching context to $scd"
	Push-Location $scd 

	try
	{
		Write-Host ">>> Prepare Docker Compose deployment"
		& '.\compose-init.ps1' -LicenseXmlPath (Join-Path $scd 'license.xml')

		Write-Host ">>> Pulling Docker Images"
		Invoke-CommandLine -Command $dockerComposeExe -Arguments "pull --ignore-pull-failures --include-deps" -WorkingDirectory $scd -IgnoreStdOut | Select-Object -ExpandProperty StdErr

		$images = [string[]] (Invoke-CommandLine -Command $dockerExe -Arguments "image ls --all --format `"{{ .ID }}`"" | Select-Object -ExpandProperty StdOut)
		if ($images.Count -gt 0) {

			Write-Host ">>> Saving Docker Images to archive"
			$images | ForEach-Object { Write-Host "Saving image ID: $_" }
			Invoke-CommandLine -Command $dockerExe -Arguments "save $($images -join " ") --output $tar" | Select-Object -ExpandProperty StdOut
		}
	}
	finally
	{
		Pop-Location
	}

} elseif (Test-Path $tar -PathType Leaf) {

	Write-Host "================================================================================="
	Write-Host "= Restoring Sitecore Container Deployment"
	Write-Host "================================================================================="

	Write-Host ">>> Switching context to $scd"
	Push-Location $scd 

	try
	{
		Write-Host ">>> Run Docker Compose DOWN"
		Invoke-CommandLine -Command $dockerComposeExe -Arguments "down --rmi all" -WorkingDirectory $scd -IgnoreStdOut | Select-Object -ExpandProperty StdErr

		$containers = [string[]] (Invoke-CommandLine -Command $dockerExe -Arguments "container ls --all --format `"{{ .ID }}`"" | Select-Object -ExpandProperty StdOut)
		if ($containers.Count -gt 0) {

			Write-Host ">>> Deleting Docker Containers"
			$containers | ForEach-Object { Write-Host "Deleting container ID: $_" }
			Invoke-CommandLine -Command $dockerExe -Arguments "container rm $($containers -join " ")" | Select-Object -ExpandProperty StdOut
		}

		$images = [string[]] (Invoke-CommandLine -Command $dockerExe -Arguments "image ls --all --format `"{{ .ID }}`"" | Select-Object -ExpandProperty StdOut)
		if ($images.Count -gt 0) {
		
			Write-Host ">>> Deleting Docker Images"
			$images | ForEach-Object { Write-Host "Deleting image ID: $_" }
			Invoke-CommandLine -Command $dockerExe -Arguments "image rm $($images -join " ")" | Select-Object -ExpandProperty StdOut
		}

		Write-Host ">>> Loading Docker Images"
		Invoke-CommandLine -Command $dockerExe -Arguments "load --input $tar" | Select-Object -ExpandProperty StdOut

		Write-Host ">>> Run Docker Compose UP"
		Invoke-CommandLine -Command $dockerComposeExe -Arguments "up --detach" -WorkingDirectory $scd -IgnoreStdOut | Select-Object -ExpandProperty StdErr
	}
	finally
	{
		Pop-Location
	}

} elseif ($MyInvocation) {

	$script = $MyInvocation.MyCommand.Definition

	& "$script" -Packer $true

	if (Test-Path $tar -PathType Leaf) {
		& "$script"
	}
}

