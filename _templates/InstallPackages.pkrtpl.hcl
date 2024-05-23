Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-Packages.ps1' -Elevate
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function Has-Property {

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    return ($null -ne ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue))
}

function Get-PropertyValue {
    
	param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [string] $DefaultValue = [string]::Empty
    )

    $value = ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue)

    if ($value) { 
        if ($value -is [array]) { $value = $value -join " " } 
    } else { 
        $value = $DefaultValue 
    }

	return $value
}

function Get-PropertyArray {

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $value = ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue)

    if ($value) {
        
        if ($value -is [array]) {
            Write-Output -NoEnumerate $value
        } else {
            Write-Output -NoEnumerate @($value)
        }
    
    } else {

        Write-Output -NoEnumerate @()    
    }
}

function Install-WinGetPackage {

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
		[object] $Package
    )

	$nameTokens = $Package.name -split ':'
	$identifier = ("--id {0}" -f ($nameTokens | Select-Object -Last 1)) 

	switch (($nameTokens | Select-Object -First 1).ToLowerInvariant()) {
		'moniker' {
			$identifier = ("--moniker {0}" -f ($nameTokens | Select-Object -Last 1))
		}
		'name' {
			$identifier = ("--name {0}" -f ($nameTokens | Select-Object -Last 1))
		}
		# 'tag' {
		#   
		# 	CAUTION - THIS DOESN'T WORK !!!
		#	Tag is not supported by winget when installing packages. Need some 
		#	more investigation on how to work around this limitation.
		#
		# 	$identifier = ("--tag {0}" -f ($nameTokens | Select-Object -Last 1))
		# }
	}

	$arguments = @(
		"install", 
		$identifier,
		("--source {0}" -f ($Package | Get-PropertyValue -Name "source" -DefaultValue "winget")),
		"--exact",
		"--disable-interactivity",
		"--accept-package-agreements",
		"--accept-source-agreements",
		"--verbose-logs"
	)

	if (Test-IsPacker) {
		# CAUTION - THIS DOESN'T WORK !!!
		# passing a scope via argument enforces using this scope. as not every
		# package manifest supports scopes yet, this leads to a winget error.
		# instead rely on the install behaviour defined in the winget settings.
		# this should define machine as the preferredScope which means winget
		# falls back to user scope if the package doesn't support machine!
		# $arguments += "--scope machine"
	}

	if ($Package | Has-Property -Name "version") { 	
		$arguments += "--version {0}" -f $Package.version
	}
	
	if ($Package | Has-Property -Name "override") { 
		$arguments += "--override `"{0}`"" -f (($Package | Get-PropertyArray -Name "override") -join ' ' )
	} else { 
		$arguments += "--silent" 
	} 

	if ($Package | Has-Property -Name "options") { 
		$Package | Get-PropertyArray -Name "options" | ForEach-Object { $arguments += "$_" }
	}

	$result = Invoke-CommandLine -Command "winget.exe" -Arguments ($arguments -join ' ')
	
	$result.Output -split "\r?\n" | ForEach-Object {
		# remove progress output
		$_ -split "\r" | Select-Object -Last 1 | Write-Host
	}

	return $result.ExitCode
}

function Install-ChocoPackage {

	param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
		[object] $Package
    )

	$arguments = @(
		"install", 
		$Package.name,	
		"--yes",
		"--acceptlicense",
		"--nocolor",
		"--no-progress"
	)

	$result = Invoke-CommandLine -Command "choco" -Arguments ($arguments -join ' ')
	
	$result.Output -split "\r?\n" | ForEach-Object {
		# remove progress output
		$_ -split "\r" | Select-Object -Last 1 | Write-Host
	}

	return $result.ExitCode
}

[array] $packages = '${jsonencode(packages)}' | ConvertFrom-Json
$allowedScopes = ('all', (&{ if (Test-IsPacker) { 'machine' } else { 'user' } }))

Invoke-ScriptSection -Title "Packages" -ScriptBlock { 
	# dump the packages to the console	
	$packages | ConvertTo-Json | Write-Host 
}

# define success exit codes for winget
$successExitCodes_winget = @(
	-1978335189 # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE  
)

# define success exit codes for choco
$successExitCodes_choco = @(

)

$lastSuccessPackageFile = Join-Path $env:DEVBOX_HOME 'Package.info'
$lastSuccessPackageHash = Get-Content -Path $lastSuccessPackageFile -ErrorAction SilentlyContinue

foreach ($package in $packages) {

	# calculate the hash of the current package
	$currentPackageHash = $package | ConvertTo-Json -Compress | ConvertTo-GUID

	if ($lastSuccessPackageHash) {

		if ($currentPackageHash -eq $lastSuccessPackageHash) {
			# reset last package hash to enable install of the next package again
			$lastSuccessPackageHash = $null
		}

		# skip the package if it was already processed
		Write-Host ">>> Skipping $($package.name) - already installed"; continue

	}

	$package | Invoke-ScriptSection -Title "Install Package" -ScriptBlock {

		if ($allowedScopes -contains ($package | Get-PropertyValue -Name 'scope')) {

			$successExitCodes = @(0) + ($package | Get-PropertyArray -Name 'exitCodes')
			$source = $package | Get-PropertyValue -Name "source" -DefaultValue "winget"
			$exitCode = 0

			switch -exact ($source.ToLowerInvariant()) {

				'winget' {
					$successExitCodes = $successExitCodes + $successExitCodes_winget |  Select-Object -Unique | Sort-Object
					$exitCode = ($package | Install-WinGetPackage)
					Break
				}

				'msstore' {
					$successExitCodes = $successExitCodes + $successExitCodes_winget | Select-Object -Unique | Sort-Object
					$exitCode = ($package | Install-WinGetPackage)
					Break
				}

				'choco' {
					$successExitCodes = $successExitCodes + $successExitCodes_choco | Select-Object -Unique | Sort-Object
					$exitCode = ($package | Install-ChocoPackage)
					Break
				}
			}

			if ($successExitCodes -notcontains $exitCode) {
				# installation failed with an unexpected exit code
				Write-ErrorMessage "Installing $($package.name) failed with exit code '$exitCode'."; exit $exitCode
			} elseif ($exitCode -ne 0) {
				# installation failed with an expected exit code
				Write-ErrorMessage "Installing $($package.name) failed with exit code '$exitCode' but was ignored (SUCCESS EXIT CODES: $($successExitCodes -join ', '))"
			}
			
		} else {

			Write-Host "Installation skipped - package scope mismatch: $($package | Get-PropertyValue -Name 'scope')"
		}
	}
	
	# store the last successful package hash
	$currentPackageHash | Set-Content -Path $lastSuccessPackageFile -Force

	if ((Test-IsPacker) -and (Test-PendingReboot)) {
		Write-ErrorMessage ">>> Pending reboot detected after installing package $($package.name) - restarting the machine ..."
		shutdown /r /t 1 /f /d p:4:1 /c "Pending reboot after installing package $($package.name)"
		exit 3010
	}
}

# remove the last successful package file
Remove-Item -Path $lastSuccessPackageFile -Force -ErrorAction SilentlyContinue
