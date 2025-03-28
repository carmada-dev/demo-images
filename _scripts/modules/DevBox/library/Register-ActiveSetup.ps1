function Register-ActiveSetup {

    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $false)]
        [string] $Name,

        [switch] $Enabled,
        [switch] $Direct,
        [switch] $AsSystem
    )

    $Path = [System.IO.Path]::GetFullPath([System.Environment]::ExpandEnvironmentVariables($Path)).Trim()

    $activeSetupFolder =  New-Item -Path (Join-Path $env:DEVBOX_HOME 'ActiveSetup') -ItemType Directory -Force | Select-Object -ExpandProperty FullName
    $activeSetupScript = Join-Path $activeSetupFolder (&{ if ($Name) { $Name } else { [System.IO.Path]::GetFileName($Path) } })
    $activeSetupId = $Path | ConvertTo-GUID -Invariant
    $activeSetupKeyPath = 'HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components'
    $activeSetupKeyEnabled = [int]$Enabled.ToBool()

    if (-not($Path.StartsWith($activeSetupFolder))) {
        # copy the script to the active setup folder and create a new ID based on the new path
        $Path = Copy-Item -Path $Path -Destination $activeSetupScript -Force -PassThru | Select-Object -ExpandProperty Fullname
        $activeSetupId = $Path | ConvertTo-GUID -Invariant
    }

    $activeSetupCmd = "PowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Path`""

    if (-not $Direct) {

        $taskName = "DevBox-$activeSetupId"
        $taskPath = '\'

        $taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
        if ($AsSystem) { $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'System' -RunLevel Highest } 

        # delete any existing task with the same name
        Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

        # register our newly defined task
        Register-ScheduledTask -Force -TaskName $taskName -TaskPath $taskPath `
            -Action (New-ScheduledTaskAction -Execute 'powershell' -Argument "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Path`"") `
            -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -Priority 0 -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -DontStopIfGoingOnBatteries -DontStopOnIdleEnd) `
            -Principal $taskPrincipal `
            -ErrorAction Stop | Out-Null

        # grant authenticated users permissions to run the task
        Grant-ScheduledTaskInvoke -TaskName $taskName -TaskPath $taskPath | Out-Null

        $activeSetupScript = {
            Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object { Import-Module -Name $_ } 
            Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue | Start-Service -ErrorAction SilentlyContinue | Out-Null 
            exit (Invoke-ScheduledTask -TaskName '[TaskName]' -TaskPath '[TaskPath]')
        } 
        
        $activeSetupTokens = @{
            'TaskName' = $taskName
            'TaskPath' = $taskPath
        }

        $activeSetupTasks = New-Item -Path (Join-Path $env:DEVBOX_HOME "ActiveSetup\Tasks") -ItemType Directory -Force | Select-Object -ExpandProperty FullName
        $activeSetupTaskScript = Join-Path $activeSetupTasks "$taskName.ps1"
        $activeSetupTaskLog = [System.IO.Path]::ChangeExtension($activeSetupTaskScript, '.log')

        $activeSetupScript | Convert-ScriptBlockToString -ScriptTokens $activeSetupTokens -Transcript $activeSetupTaskLog | Out-File -FilePath $activeSetupTaskScript -Force -ErrorAction SilentlyContinue
        $activeSetupCmd = "PowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$activeSetupTaskScript`""
    }

    # By default we assume the ActiveSetup task is already registered and we need to update it.
    # Therefore we check if the task is already registered by its naming pattern. If not found,
    # we switch to registration mode and create a new task with a new ID.

    # The task name follows the pattern "devbox-[UnixTimestamp]-[ScriptHashAsGUID]".
    # UnixTimestamp - used to ensure the task is executed in the order of its registration.
    # ScriptHashAsGUID - used to identify the script to ensure a script is executed only once.
    
    # CAUTION: If the same script is registered multiple times, we only create one task! 
    # All subsequent registrations will only update the version information of the existing task. 

    $activeSetupAction = 'Updating'
    $activeSetupKey = Get-ChildItem -Path $activeSetupKeyPath `
        | ForEach-Object { Split-Path -Path ($_.Name) -Leaf } `
        | Where-Object { $_ -match "devbox-\d+-$activeSetupId" } `
        | Select-Object -First 1 -ErrorAction SilentlyContinue

    if (-not $activeSetupKey) {
        $activeSetupAction = 'Registering'
        $activeSetupKey = "devbox-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString())-$activeSetupId"
    }

    Write-Host "- $activeSetupAction ActiveSetup Task: $activeSetupKey"
    $registryKey = New-Item -Path $activeSetupKeyPath -Name $activeSetupKey -Force -ErrorAction SilentlyContinue
    $registryKey | New-ItemProperty -Force -Name '(Default)' -Value ([System.IO.Path]::GetFileNameWithoutExtension($Path)) -ErrorAction SilentlyContinue | Out-Null
    $registryKey | New-ItemProperty -Force -Name 'StubPath' -Value $activeSetupCmd -PropertyType 'ExpandString' -ErrorAction SilentlyContinue | Out-Null
    $registryKey | New-ItemProperty -Force -Name 'Version' -Value ((Get-Date -Format 'yyyy,MMdd,HHmm').ToString()) -ErrorAction SilentlyContinue | Out-Null
    $registryKey | New-ItemProperty -Force -Name 'IsInstalled' -Value $activeSetupKeyEnabled -PropertyType 'DWord' -ErrorAction SilentlyContinue | Out-Null
}

Export-ModuleMember -Function Register-ActiveSetup