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
        # copy the script to the active setup folder and create a new ID based on the new path
        $Path = Copy-Item -Path $Path -Destination $activeSetupScript -Force -PassThru | Select-Object -ExpandProperty Fullname
        $activeSetupId = $Path | ConvertTo-GUID
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

    $activeSetupPS1 = Join-Path $env:DEVBOX_HOME "ActiveSetup\$taskName.ps1"
    $activeSetupLog = [System.IO.Path]::ChangeExtension($activeSetupPS1, '.log')

    $activeSetupScript = {

        Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object { Import-Module -Name $_ } 
        $service = Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Running') { Start-Service -Name 'Schedule' -ErrorAction SilentlyContinue | Out-Null }
        $task = Get-ScheduledTask -TaskName '[TaskName]' -TaskPath '[TaskPath]' -ErrorAction SilentlyContinue
        if ($task) { $task | Wait-ScheduledTask -Start }

    } | Convert-ScriptBlockToString -ScriptTokens @{ 'TaskName' = $taskName; 'TaskPath' = $taskPath } -Transcript $activeSetupLog -Ugly

    $activeSetupCmd = "PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $($activeSetupScript | ConvertTo-Base64)"

    if ($activeSetupCmd.Length -gt 8192) {
        Write-Host ">>> ActiveSetup command is too long, using script '$activeSetupScript' instead"
        $activeSetupScript | Out-File -FilePath $activeSetupScript -Force -ErrorAction SilentlyContinue
        $activeSetupCmd = "PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$activeSetupPS1`""
    }

    $activeSetupKey = Get-ChildItem -Path $activeSetupKeyPath `
        | ForEach-Object { Split-Path -Path ($_.Name) -Leaf } `
        | Where-Object { $_ -match "devbox-\d+-$activeSetupId" } `
        | Select-Object -First 1 -ErrorAction SilentlyContinue

    if ($activeSetupKey) {
        
        Write-Host "- Updating ActiveSetup Task: $activeSetupKey"

    } else {

        # create a new key for the active setup task (combination of timestamp - to keep execution order - and ID)
        $activeSetupTimestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
        $activeSetupKey = Join-Path $activeSetupKeyPath "devbox-$activeSetupTimestamp-$activeSetupId"
        
        Write-Host "- Registering ActiveSetup Task: $activeSetupKey"
    }

    $registryKey = New-Item -Path $activeSetupKey -Force -ErrorAction SilentlyContinue
    $registryKey | New-ItemProperty -Force -Name '(Default)' -Value ([System.IO.Path]::GetFileNameWithoutExtension($Path)) -ErrorAction SilentlyContinue | Out-Null
    $registryKey | New-ItemProperty -Force -Name 'StubPath' -Value $activeSetupCmd -PropertyType 'ExpandString' -ErrorAction SilentlyContinue | Out-Null
    $registryKey | New-ItemProperty -Force -Name 'Version' -Value ((Get-Date -Format 'yyyy,MMdd,HHmm').ToString()) -ErrorAction SilentlyContinue | Out-Null
    $registryKey | New-ItemProperty -Force -Name 'IsInstalled' -Value $activeSetupKeyEnabled -PropertyType 'DWord' -ErrorAction SilentlyContinue | Out-Null
}

Export-ModuleMember -Function Register-ActiveSetup