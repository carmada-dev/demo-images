$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$git = Get-Command 'git.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path

if (-not $git) {
    Write-Host ">>> Not applicable: Git not installed"
    exit 0
}

# ==============================================================================

if (Test-IsPacker) {
    
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

        $taskScriptEncoded = $scriptBlock | Convert-ScriptBlockToString -EncodeBase64

        Write-Host ">>> Register scheduled task to configure git"
        Register-ScheduledTask -Force -TaskName 'Configure Git' -TaskPath '\' `
            -Action (New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $taskScriptEncoded") `
            -Trigger @(New-ScheduledTaskTrigger -AtLogOn -RandomDelay (New-TimeSpan -Minutes 5)) `
            -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew) `
            -Principal (New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest) | Out-Null
    } 
}