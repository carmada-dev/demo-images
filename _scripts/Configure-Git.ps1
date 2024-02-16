param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

if ( -not(Get-Command 'git') ) {
    Write-ErrorMessage '!!! Docker could not be found.'
    exit 1
}

if ($Packer) {
    
    Invoke-ScriptSection -Title "Configure Git (PACKER)" -ScriptBlock {
        
        Write-Host ">>> Ensure git user name" 

        $gitUserName = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.name' | Select-Object -ExpandProperty Output) -split "\r?\n") `
            | Where-Object { $_ } `
            | Select-Object -First 1 `
            | Out-String

        if (-not($gitUserName)) { 
            Invoke-CommandLine -Command 'git' -Arguments "config --global user.name `"Packer`"" | Select-Object -ExpandProperty Output | Write-Host
        }

        Write-Host ">>> Ensure git user email" 
        
        $gitUserEmail = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.email' | Select-Object -ExpandProperty Output) -split "\r?\n") `
            | Where-Object { $_ } `
            | Select-Object -First 1 `
            | Out-String

        if (-not($gitUserEmail)) { 
            Invoke-CommandLine -Command 'git' -Arguments "config --global user.email `"packer@microsoft.com`"" | Select-Object -ExpandProperty Output | Write-Host
        }

    }

    Invoke-ScriptSection -Title "Configure Git (USER)" -ScriptBlock {

        # To configure git for the user, we need to run the script block in the user context. As we need to ensure that the user is logged in, 
        # we register a scheduled task to run the script block at logon. A random delay is used to give OneDrive a chance to establish the user context.
        # This user context is required to retrieve the user name and email from the OneDrive registry settings.

        $scriptBlock = {
    
            Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
                Write-Host ">>> Importing PowerShell Module: $_"
                Import-Module -Name $_
            } 

            $started = Get-Date
            $timeout = New-TimeSpan -Minutes 5

            do {
                
                Write-Host ">>> Ensure git user name" 

                $gitUserName = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.name' | Select-Object -ExpandProperty Output) -split "\r?\n") `
                    | Where-Object { $_ } `
                    | Select-Object -First 1 `
                    | Out-String

                if (-not($gitUserName)) { 
                    $gitUserName = Get-ChildItem -Path HKCU:\Software\Microsoft\OneDrive\Accounts -Recurse | Get-ItemPropertyValue -Name UserName -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($gitUserName) { Invoke-CommandLine -Command 'git' -Arguments "config --global user.name `"$gitUserName`"" | Select-Object -ExpandProperty Output | Write-Host }
                }

                Write-Host ">>> Ensure git user email" 
                
                $gitUserEmail = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.email' | Select-Object -ExpandProperty Output) -split "\r?\n") `
                    | Where-Object { $_ } `
                    | Select-Object -First 1 `
                    | Out-String

                if (-not($gitUserEmail)) { 
                    $gitUserEmail = Get-ChildItem -Path HKCU:\Software\Microsoft\OneDrive\Accounts -Recurse | Get-ItemPropertyValue -Name UserEmail -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($gitUserEmail) { Invoke-CommandLine -Command 'git' -Arguments "config --global user.email `"$gitUserEmail`"" | Select-Object -ExpandProperty Output | Write-Host }
                }

            } until ( (($gitUserName) -and ($gitUserEmail)) -or ((New-TimeSpan -Start $started -End (Get-Date)) -gt $timeout) )

        }

        Write-Host ">>> Register scheduled task to configure git"

        $taskScriptSource = $scriptBlock | Out-String -Width ([int]::MaxValue)
        $taskScriptEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($taskScriptSource)))
        $taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $taskScriptEncoded"
        $taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
        $taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn -RandomDelay (New-TimeSpan -Minutes 5) )

        Register-ScheduledTask -Force -TaskName 'Configure Git' -TaskPath '\' -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal | Out-Null
    } 
}