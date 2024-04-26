Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

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

$driveConfig = '${jsonencode(devDrive)}' | ConvertFrom-Json
$driveSizeGB = [int]($driveConfig | Get-PropertyValue -Name "sizeGB" -DefaultValue "0")
$drivePath = $null

if ((Test-IsPacker) -and ($driveSizeGB -gt 0)) {
    
    Invoke-ScriptSection -Title "Apply DevDrive Filter" -ScriptBlock {
        
        $filters = $driveConfig | Get-PropertyArray -Name "filters"

        if ($filters) {
            Invoke-CommandLine -Command "fsutil.exe" -Arguments "devdrv setfiltersallowed `"$($filters -join ', ')`"" | Select-Object -ExpandProperty Output | Write-Host
        } else {
            Write-Host "Skip - no filters defined (find common filters to apply here https://learn.microsoft.com/en-us/windows/dev-drive/#filters-for-common-scenarios)"         
        }
    }

    Invoke-ScriptSection -Title "Creating DevDrive" -ScriptBlock {

        if ($driveSizeGB -lt 50) {
            Write-Host ">>> Increasing DevDrive size to 50GB"
            $driveSizeGB = [Math]::Max($driveSizeGB, 50)
        }

        if (Test-FeatureEnabled -Name @( 'Microsoft-Hyper-V-Management-PowerShell' )) {

            $drivePath = Join-Path $env:DEVBOX_HOME 'DevDrive.vhdx'
            $driveDisk = $null

            if ((Test-Path $drivePath -PathType Leaf)) {

                Write-Host ">>> Using existing DevDrive VHDX ($drivePath)"
                $driveDisk = Get-VHD -Path $drivePath

            } else {

                $driveSize = $driveSizeGB * 1024 * 1024 * 1024
                $capacity = Get-Volume -DriveLetter C | Select-Object -ExpandProperty SizeRemaining

                if ($driveSize -lt $capacity) {
            
                    Write-Host ">>> Creating new DevDrive VHDX ($drivePath)"
                    $driveDisk = New-VHD -path $drivePath -SizeBytes $driveSize -Dynamic

                } else {
            
                    Write-Error "Unable to create DevDrive with size $driveSizeGB GB (free $([Math]::Ceiling($capacity / 1GB)) GB)"
                    exit 1
            
                }
            }


            if ($driveDisk) {
                
                if ($driveDisk.Attached) {
                    $driveDisk = Get-Disk | Where-Object { $_.Location -eq $drivePath } | Select-Object -First 1
                } else {
                    $driveDisk = $driveDisk | Mount-VHD -Passthru
                }

                if (-not($driveDisk.PartitionStyle)) {
                    Write-Host ">>> Initializing DevDrive Disk"
                    $driveDisk = $driveDisk | Initialize-Disk -PartitionStyle GPT -PassThru -ErrorAction SilentlyContinue
                }
                
                $drivePartition = $null

                if ($driveDisk.PartitionStyle -eq 'RAW') {
                    Write-Host ">>> Initializing partition on DevDrive"
                    $drivePartition = $driveDisk | New-Partition -AssignDriveLetter -UseMaximumSize
                } else {
                    $drivePartition = $driveDisk | Get-Partition | Where-Object { -not($_.IsHidden) } | Select-Object -First 1
                }

                $driveVolume = Get-Volume | Where-Object { $drivePartition.AccessPaths -contains $_.Path } | Select-Object -First 1

                if ($driveVolume.FileSystem -ne 'ReFS') {
                    Write-Host ">>> Formatting partition on DevDrive"
                    $driveVolume = $drivePartition | Format-Volume -DevDrive -Confirm:$false 
                }
            }

        } else {
            
            Write-Error "DevDrive requires Windows feature 'Microsoft-Hyper-V-Management-PowerShell' to be enabled."
            exit 1
        }
    }

    if ($drivePath -and (Test-Path -Path $drivePath -PathType Leaf)) {
        Invoke-ScriptSection -Title 'Enable DevDrive AutoMount' -ScriptBlock {

            $taskScriptSource = ({
                $cddl = Get-Volume | ? { $_.DriveType -eq 'CD-ROM' } | Select -First 1 -ExpandProperty DriveLetter
                if ($cddl) { Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = '$($cddl):'" | Set-CimInstance -Property @{DriveLetter = 'Z:'} }
                Mount-VHD -Path 'VHDPATH' -ErrorAction SilentlyContinue
                Get-Volume | ? { $_.FileSystemType -eq 'ReFS' -and $_.DriveLetter } | Sort { $_.DriveLetter } | % { $dc = [int]$_.DriveLetter; $dl = (67..[int]$dc | % { [char]($_) } | ? { -not((Get-Volume | % { $_.DriveLetter }) -contains "$_") } | select -First 1); if ($dl) { Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = '$($_.DriveLetter):'" | Set-CimInstance -Property @{ DriveLetter = "$([char]$dl):"; Label = "DevDrive" } } }
                Get-Volume | ? { $_.FileSystemType -eq 'ReFS' -and $_.FileSystemLabel -ne 'DevDrive' } | % { Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = '$($_.DriveLetter):'" | Set-CimInstance -Property @{ Label = "DevDrive" } }
                $ddl = Get-Volume | ? { $_.FileSystemType -eq 'ReFS' } | Sort { $_.DriveLetter } | Select -First 1 -ExpandProperty DriveLetter
                if ($ddl) {
                    Start-Process -FilePath fsutil -ArgumentList ('devdrv', 'trust', "$($ddl):") -ErrorAction SilentlyContinue
                    $pkgs = ni -Path "$($ddl):\packages" -ItemType Directory -Force | Select -ExpandProperty FullName
                    [Environment]::SetEnvironmentVariable("npm_config_cache", (ni -Path "$($pkgs)\npm" -ItemType Directory -Force | Select -ExpandProperty FullName), [System.EnvironmentVariableTarget]::Machine) 
                    [Environment]::SetEnvironmentVariable("NUGET_PACKAGES", (ni -Path "$($pkgs)\nuget" -ItemType Directory -Force | Select -ExpandProperty FullName), [System.EnvironmentVariableTarget]::Machine) 
                    [Environment]::SetEnvironmentVariable("VCPKG_DEFAULT_BINARY_CACHE ", (ni -Path "$($pkgs)\vcpkg" -ItemType Directory -Force | Select -ExpandProperty FullName), [System.EnvironmentVariableTarget]::Machine) 
                    [Environment]::SetEnvironmentVariable("PIP_CACHE_DIR", (ni -Path "$($pkgs)\pip" -ItemType Directory -Force | Select -ExpandProperty FullName), [System.EnvironmentVariableTarget]::Machine) 
                    [Environment]::SetEnvironmentVariable("CARGO_HOME", (ni -Path "$($pkgs)\cargo" -ItemType Directory -Force | Select -ExpandProperty FullName), [System.EnvironmentVariableTarget]::Machine) 
                    [Environment]::SetEnvironmentVariable("MAVEN_OPTS", "-Dmaven.repo.local=$(ni -Path "$($pkgs)\maven" -ItemType Directory -Force | Select -ExpandProperty FullName) %MAVEN_OPTS%", [System.EnvironmentVariableTarget]::Machine) 
                }
            } | Out-String -Width ([int]::MaxValue)) -creplace 'VHDPATH', "$drivePath"

            $taskScriptEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($taskScriptSource)))
            $taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -EncodedCommand $taskScriptEncoded"
            $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
            $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
            $taskTriggers = @( New-ScheduledTaskTrigger -AtStartup )
            Register-ScheduledTask -Force -TaskName 'DevDrive AutoMount' -TaskPath '\' -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal | Out-Null

            Write-Host "done"
        }
    }
}
