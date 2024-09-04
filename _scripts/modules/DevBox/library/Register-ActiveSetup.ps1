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
        [switch] $Elevate
    )

    $Path = [System.IO.Path]::GetFullPath([System.Environment]::ExpandEnvironmentVariables($Path))

    $activeSetupFolder = Join-Path $env:DEVBOX_HOME 'ActiveSetup'
    $activeSetupScript = Join-Path $activeSetupFolder (&{ if ($Name) { $Name } else { [System.IO.Path]::GetFileName($Path) } })
    $activeSetupElevator = Join-Path $activeSetupFolder 'Elevate-Script.ps1'
    
    if (-not($Path.StartsWith($activeSetupFolder))) {
        New-Item -Path $activeSetupFolder -ItemType Directory -Force | Out-Null # ensure active setup root folder exists
        $Path = Copy-Item -Path $Path -Destination $activeSetupScript -Force -PassThru | Select-Object -ExpandProperty Fullname
    }

    $activeSetupId = $Path | ConvertTo-GUID 
    $activeSetupKeyPath = 'HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components'
    $activeSetupKeyEnabled = [int]$Enabled.ToBool()
    
    if ($Elevate) {

        ({
            param(
                [Parameter(Mandatory = $true)]
                [string] $ScriptKey
            )

            # Enforce the console window to be hidden - somehow the scheduled task does not handle script execution with windowstate hidden prperly
            # The ShowWindow function is used to hide the current console window: 0 = SW_HIDE, 1 = SW_SHOWNORMAL, 2 = SW_SHOWMINIMIZED, 3 = SW_SHOWMAXIMIZED, 4 = SW_SHOWNOACTIVATE, 5 = SW_SHOW, 6 = SW_MINIMIZE, 7 = SW_SHOWMINNOACTIVE, 8 = SW_SHOWNA, 9 = SW_RESTORE, 10 = SW_SHOWDEFAULT, 11 = SW_FORCEMINIMIZE, 12 = SW_MAX
            Add-Type -Name ConsoleUtils -Namespace DevBox -MemberDefinition ('[DllImport("Kernel32.dll")]{0}public static extern IntPtr GetConsoleWindow();{0}[DllImport("User32.dll")]{0}public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);' -f [Environment]::NewLine)
            $hWnd = [DevBox.ConsoleUtils]::GetConsoleWindow() 
            if ($hWnd) { [DevBox.ConsoleUtils]::ShowWindow($hWnd, 0) } 

            Write-Host ">>> Initializing transcript"
            Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 

            Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
                Write-Host ">>> Importing PowerShell Module: $_"
                Import-Module -Name $_
            } 
            
            try {
                
                $taskName = "$ScriptKey-$(if (Test-IsLocalAdmin) { 'ADMIN' } else { 'SYSTEM' })"
                $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue

                if ($task) {

                    Write-Host ">>> Executing task $taskName ..."
                    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
                    
                    $timeout = (Get-Date).AddMinutes(30) # wait for the task to finish for a
                    $running = $false

                    while ($true) {
                    
                        if ($timeout -lt (Get-Date)) { Throw "Timeout waiting for $taskName to finish" }
                        $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
                        
                        if (-not($task)) { 
                            
                            Throw "Scheduled task $taskName does not exist anymore"
                        
                        } elseif ($running) {

                            if ($task.State -ne 'Running') { break }

                            Write-Host ">>> Waiting for $taskName to finish ..."
                            Start-Sleep -Seconds 5

                        } else {

                            $running = $running -or ($task.State -eq 'Running')
                            if ($running) { Write-Host ">>> Task $taskName starts running ..." }
                        }
                    }
                    
                    Write-Host ">>> Executing task $taskName completed"

                } else {

                    Throw "Could not find scheduled task by script key '$ScriptKey' ($taskName)"
                }

            } finally {

                Write-Host ">>> Unregistering scheduled tasks related to script key '$ScriptKey' ..."
                Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName.StartsWith("$ScriptKey-") } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
            }

        } | Out-String -Width ([int]::MaxValue)) | Out-File -FilePath $activeSetupElevator -Encoding 'UTF8' -Force
        
        $taskAction = New-ScheduledTaskAction -Execute '%comspec%' -Argument "/min /c `"PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Path`"`""
        $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -Priority 0 -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -Hidden

        $taskPrincipalSystem = New-ScheduledTaskPrincipal -UserId 'System' -RunLevel Highest
        Register-ScheduledTask -Force -TaskName "$activeSetupId-SYSTEM" -TaskPath '\' -Action $taskAction -Settings $taskSettings -Principal $taskPrincipalSystem | Out-Null
        Grant-AuthenticatedUsersPermissions -TaskName "$activeSetupId-SYSTEM" -TaskPath '\'

        $taskPrincipalAdmin = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Administrators' -RunLevel Highest
        Register-ScheduledTask -Force -TaskName "$activeSetupId-ADMIN" -TaskPath '\' -Action $taskAction -Settings $taskSettings -Principal $taskPrincipalAdmin | Out-Null
        Grant-AuthenticatedUsersPermissions -TaskName "$activeSetupId-ADMIN" -TaskPath '\'

        $activeSetupCmd = "cmd /min /c `"PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$activeSetupElevator`" $activeSetupId`""

    } else {

        # Setting __COMPAT_LAYER to RunAsInvoker does not actually give you administrator privileges if you do not have them; 
        # it simply prevents the UAC pop-up from appearing and then runs the program as whatever user called it. 
        # As such, it is safe to use this since you are not magically obtaining admin rights.

        $activeSetupCmd = "cmd /min /c `"set __COMPAT_LAYER=RUNASINVOKER && PowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Path`"`""
    }

    if (-not($activeSetupCmd)) {
        Throw "Failed to create ActiveSetup command for $Path"
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