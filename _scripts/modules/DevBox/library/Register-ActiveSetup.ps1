function Grant-AuthenticatedUsersPermissions() {

    param(
        [Parameter(Mandatory = $true)]
        [string] $TaskName,
        [Parameter(Mandatory = $false)]
        [string] $TaskPath = "\"
    )

    $Scheduler = New-Object -ComObject "Schedule.Service"
    $Scheduler.Connect()

    $GetTask = $Scheduler.GetFolder($TaskPath).GetTask($TaskName)
    $GetSecurityDescriptor = $GetTask.GetSecurityDescriptor(0xF)

    if ($GetSecurityDescriptor -notmatch 'A;;0x1200a9;;;AU') {
        $GetSecurityDescriptor = $GetSecurityDescriptor + '(A;;GRGX;;;AU)'
        $GetTask.SetSecurityDescriptor($GetSecurityDescriptor, 0)
    }
}

function Register-ActiveSetup {

    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $false)]
        [string] $Name,

        [switch] $Enabled,
        [switch] $AsSystem
    )

    $Path = [System.IO.Path]::GetFullPath([System.Environment]::ExpandEnvironmentVariables($Path))

    $activeSetupFolder =  New-Item -Path (Join-Path $env:DEVBOX_HOME 'ActiveSetup') -ItemType Directory -Force | Select-Object -ExpandProperty FullName
    $activeSetupScript = Join-Path $activeSetupFolder (&{ if ($Name) { $Name } else { [System.IO.Path]::GetFileName($Path) } })
    $activeSetupId = $Path | ConvertTo-GUID 
    $activeSetupKeyPath = 'HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components'
    $activeSetupKeyEnabled = [int]$Enabled.ToBool()

    if (-not($Path.StartsWith($activeSetupFolder))) {
        # copy the script to the active setup folder
        $Path = Copy-Item -Path $Path -Destination $activeSetupScript -Force -PassThru | Select-Object -ExpandProperty Fullname
    }

    $taskName = "DevBox-$activeSetupId"
    $taskPath = '\'
    $taskAction = New-ScheduledTaskAction -Execute 'powershell' -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Path`""
    $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -Priority 0 -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -DontStopIfGoingOnBatteries -DontStopOnIdleEnd 
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn
    $taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
    
    if ($AsSystem) {
        # The task will be run as SYSTEM, so we need to set the principal to SYSTEM
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'System' -RunLevel Highest
    } 

    # delete any existing task with the same name
    Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    # register our newly defined task
    Register-ScheduledTask -Force -TaskName $taskName -TaskPath $taskPath -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -ErrorAction Stop | Out-Null

    # grant authenticated users permissions to run the task
    Grant-AuthenticatedUsersPermissions -TaskName $taskName -TaskPath $taskPath

    $activeSetupScript = Join-Path $env:DEVBOX_HOME "ActiveSetup\$taskName.log"
    $activeSetupLog = [System.IO.Path]::ChangeExtension($activeSetupScript, '.log')

    $activeSetupScript = {

        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
            Write-Host ">>> Importing PowerShell Module: $_"
            Import-Module -Name $_
        } 

        # ensure scheduled task service is running
        $service = Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue
        if (-not $service) { throw 'Could not find Scheduled Task service' }

        if ($service.Status -ne 'Running') {
            Write-Host ">>> Starting Scheduled Task service ..."
            Start-Service -Name 'Schedule' -ErrorAction SilentlyContinue | Out-Null
        }

        $task = Get-ScheduledTask -TaskName '[TaskName]' -TaskPath '[TaskPath]' -ErrorAction SilentlyContinue
        if (-not $task) { throw 'Could not find Scheduled Task [TaskPath][TaskName]'  }

        # NEVER delete the task after execution - scheduled tasks are not user specific !!!
        # So we need to keep the task alive for potential other users logging in
        $task | Wait-ScheduledTask -Start

    } | Convert-ScriptBlockToString -ScriptTokens @{ 'TaskName' = $taskName; 'TaskPath' = $taskPath } -Transcript $activeSetupLog

    $activeSetupCmd = "PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $($activeSetupScript | ConvertTo-Base64)"

    if ($activeSetupCmd.Length -gt 8192) {

        Write-Host ">>> ActiveSetup command is too long, using script '$activeSetupScript' instead"
        $activeSetupScript | Out-File -FilePath $activeSetupScript -Force -ErrorAction SilentlyContinue
        $activeSetupCmd = "PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$activeSetupScript`""
    }

    $activeSetupKey = Get-ChildItem -Path $activeSetupKeyPath `
        | ForEach-Object { Split-Path -Path ($_.Name) -Leaf } `
        | Where-Object { $_ -match "devbox-\d+-$activeSetupId" } `
        | Select-Object -First 1 -ErrorAction SilentlyContinue

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