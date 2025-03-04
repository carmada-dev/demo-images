function Invoke-AsScheduledTask {

    param (
        [Parameter(Mandatory=$true)]
        [string] $TaskName,

        [Parameter(Mandatory=$false)]
        [string] $TaskPath = '\',

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [scriptblock] $ScriptBlock,
        
        [Parameter(Mandatory=$false)]
        [Hashtable] $ScriptTokens = @{},

        [Parameter(Mandatory=$false)]
        [System.Timespan] $Timeout = [System.TimeSpan]::FromMinutes(5)
    )

    $exitCode = 0

    $taskTranscript = Join-Path -Path $env:temp -ChildPath "$([System.Guid]::NewGuid()).log"
    $taskHeader = "Start-Transcript -Path '$taskTranscript' -Force"
    $taskFooter = "Stop-Transcript -ErrorAction SilentlyContinue"
    $taskFullname = Join-Path -Path $TaskPath -ChildPath $TaskName
    
    Write-Host ">>> Preparing script for Scheduled Task $taskFullname"

    # Convert the script block to a string
    $taskScript = $ScriptBlock.ToString()

    # Replace script tokens
    $ScriptTokens.Keys | ForEach-Object { $taskScript = $taskScript -replace "\[$_\]", $ScriptTokens[$_] }

    # Remove single-line comments (starting with #)
    $taskScript = $taskScript -replace '(?m)^\s*#.*$', ''   

    # Remove empty lines in the middle of the script and at the end
    $taskScript = $taskScript -replace '(?m)^(\s|\t)*\r?\n', '' -replace '\r?\n(\s|\t)*$', ''

    # Replace all indentation tabs with 4 spaces and remove the CRLF that comes with out-string
    $taskScript = ($taskScript -split "`r?`n" `
        | ForEach-Object { $_ -replace "`t", "    " } `
        | Out-String) -replace '\r?\n$', ''

    # Resolve the indentation size we can safely remove
    $indentationSize = ($taskScript -split "`r?`n" `
        | ForEach-Object { if ($_ -match '^\s*') { $Matches[0].Length } else { 0 } } `
        | Measure-Object -Minimum).Minimum

    # Remove the indentation size if possible (>0)
    if ($indentationSize -gt 0) { $taskScript = $taskScript -replace "(?m)^\s{$indentationSize}", '' }

    # merge header, script and footer
    $taskScript = ($taskHeader, $taskScript, $taskFooter) -join "`r`n"

    Write-Host '----------------------------------------------------------------------------------------------------------'
    Write-Host $taskScript
    Write-Host '----------------------------------------------------------------------------------------------------------'

    $taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($taskScript))))"
    $taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
    $taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn )
    
    Write-Host ">>> Registering Scheduled Task $taskFullname"
    $task = Register-ScheduledTask -Force -TaskName $taskName -TaskPath $taskPath -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal		

    Write-Host ">>> Executing Scheduled Task $taskFullname ($Timeout minutes timeout)"
    $task | Start-ScheduledTask -ErrorAction Stop | Out-Null

    $timeoutTimestamp = (Get-Date).Add($Timeout)
    $running = $false

    while ($true) {
    
        if ($timeoutTimestamp -lt (Get-Date)) { 
        
            # we ran into a timeout - blow it up				
            throw "Scheduled Task $taskFullname timed out after $Timeout minutes" 
        
        } else {

            # refresh the task to ensure we deal with the latest state         
            $task = Get-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue            
        
        }

        if (-not($task)) { 

            # the task does not exist anymore - blow it up
            throw "Scheduled Task $taskFullname does not exist anymore" 

        }
        elseif ($running) {

            if ($task.State -ne 'Running') { 

                $exitCode = $task | Get-ScheduledTaskInfo | Select-Object -ExpandProperty LastTaskResult
                Write-Host ">>> Scheduled Task $taskFullname finished with exit code $exitCode"
                
                break # exit the loop
            }

            Write-Host ">>> Waiting for Scheduled Task $taskFullname to finish ..."
            Start-Sleep -Seconds 5 # give the task some time to finish

        } else {

            $running = $running -or ($task.State -eq 'Running') # determine if we are in running state
            if ($running) { 
                Write-Host ">>> Scheduled Task $taskFullname starts running ..." 
            } else {
                Write-Host ">>> Scheduled Task $taskFullname is in state $($task.State) ..."
            }
        }
    }

    if (Test-Path -Path $taskTranscript -PathType Leaf) {

        $transcriptContent = Get-Content -Path $taskTranscript -Raw

        # cleanup transcript content - get only the actual content if possible
        if ($transcriptContent -match "(?s)^(?:.*?\*{22}.*?\r?\n){2}(.*?)(?:\*{22}.*?\r?\n|$)") { $transcriptContent = $Matches[1] }
        
        Write-Host '----------------------------------------------------------------------------------------------------------'
        Write-Host $transcriptContent
        Write-Host '----------------------------------------------------------------------------------------------------------'

        Write-Host ">>> Cleanup transcript of Scheduled Task $taskFullname"
        Remove-Item -Path $taskTranscript -Force -ErrorAction SilentlyContinue
    } 

    if ($task) {
        Write-Host ">>> Unregister Scheduled Task $taskFullname"
        $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    }

    Write-Host ">>> Returning Scheduled Task $taskFullname exit code $exitCode"
    return $exitCode
}

Export-ModuleMember -Function Invoke-AsScheduledTask