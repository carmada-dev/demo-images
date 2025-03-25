function Grant-AuthenticatedUsersPermissions() {

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Task
    )

    $Scheduler = New-Object -ComObject "Schedule.Service"
    $Scheduler.Connect()

    $GetTask = $Scheduler.GetFolder($Task.TaskPath).GetTask($Task.TaskName)
    $GetSecurityDescriptor = $GetTask.GetSecurityDescriptor(0xF)

    if ($GetSecurityDescriptor -notmatch 'A;;0x1200a9;;;AU') {
        $GetSecurityDescriptor = $GetSecurityDescriptor + '(A;;GRGX;;;AU)'
        $GetTask.SetSecurityDescriptor($GetSecurityDescriptor, 0)
    }

    return $Task
}

function Invoke-ScheduledTask {

    [Cmdletbinding(defaultParameterSetName='ByName')]

    param (
        [Parameter(ParameterSetName='ByName', Mandatory=$true, ValueFromPipeline=$true)]
        [string] $TaskName,

        [Parameter(ParameterSetName='ByName')]
        [string] $TaskPath = '\',

        [Parameter(ParameterSetName='ByTask', Mandatory=$true, ValueFromPipeline=$true)]
        [CimInstance] $Task,

        [Parameter(ParameterSetName='ByScript', Mandatory=$true, ValueFromPipeline=$true)]
        [scriptblock] $ScriptBlock,
        
        [Parameter(ParameterSetName='ByScript')]
        [Hashtable] $ScriptTokens = @{},

        [Parameter(ParameterSetName='ByName')]
        [Parameter(ParameterSetName='ByTask')]
        [Parameter(ParameterSetName='ByScript')]
        [System.Timespan] $Timeout = [System.TimeSpan]::FromMinutes(5)
    )

    $exitCode = 0

    # ensure the Task Scheduler service is running
    Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue | Start-Service -ErrorAction SilentlyContinue | Out-Null

    try {

        switch ($PSCmdlet.ParameterSetName) {

            'ByName' {

                $Task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
                if (-not $Task) { throw "Scheduled Task '$TaskName' under '$TaskPath' does not exist" }
                
                $exitCode = $Task | Invoke-ScheduledTask -Timeout $Timeout
            }

            'ByTask' {
                        
                $Task | Start-ScheduledTask -ErrorAction Stop 
                $TaskName = $Task.TaskName
                $TaskPath = $Task.TaskPath

                $taskTimeout = (Get-Date).Add($Timeout)
                $taskRunning = $false

                Write-Host ">>> Starting Scheduled Task '$TaskName' under '$TaskPath' ($Timeout minutes timeout)"
                $Task | Start-ScheduledTask -ErrorAction Stop 

                while ($true) {
                    if ($taskTimeout -lt (Get-Date)) { 
                
                        throw "Scheduled Task '$TaskName' under '$TaskPath' timed out" 
                
                    } else {
                
                        $Task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue                    
                    }

                    if (-not($Task)) { 
                
                        throw "Scheduled Task '$TaskName' under '$TaskPath' does not exist anymore" 
                
                    } else {
                
                        Write-Host ">>> Scheduled Task '$TaskName' under '$TaskPath' is in state $($Task.State) ..."
                        $taskRunning = $taskRunning -or ($Task.State -eq 'Running') 

                        if ($taskRunning -and ($Task.State -ne 'Running')) { 
                            $exitCode = $Task | Get-ScheduledTaskInfo | Select-Object -ExpandProperty LastTaskResult
                            break
                        } 
                        
                        # give the Task some time to do its work
                        Start-Sleep -Seconds 1                     
                    }
                }
            }

            'ByScript' {
                
                $TaskName = "$([System.Guid]::NewGuid())"
                $TaskPath = '/'

                Write-Host ">>> Preparing Scheduled Task '$TaskName' under '$TaskPath'"
                $taskTranscript = Join-Path $env:temp "$taskName.log"
                $taskScript = $ScriptBlock | Convert-ScriptBlockToString -ScriptTokens $ScriptTokens -Transcript $taskTranscript
            
                Write-Host '----------------------------------------------------------------------------------------------------------'
                Write-Host $taskScript
                Write-Host '----------------------------------------------------------------------------------------------------------'

                $taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $($taskScript | ConvertTo-Base64)"
                $taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
                $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
                
                Write-Host ">>> Registering Scheduled Task '$TaskName' under '$TaskPath'"
                $task = Register-ScheduledTask -Force -TaskName $taskName -TaskPath $taskPath -Action $taskAction -Settings $taskSettings -Principal $taskPrincipal		

                try {

                    $exitCode = $task | Grant-AuthenticatedUsersPermissions | Invoke-ScheduledTask -Timeout $Timeout

                } finally {

                    if (Test-Path $taskTranscript -ErrorAction SilentlyContinue) {

                        Write-Host ">>> Reading transcript of Scheduled Task '$TaskName' under '$TaskPath'"
                        $transcriptContent = Get-Content -Path $taskTranscript -Raw -ErrorAction SilentlyContinue
            
                        if ($transcriptContent) {
            
                            # cleanup transcript content - get only the actual content if possible
                            if ($transcriptContent -match "(?s)^(?:.*?\*{22}.*?\r?\n){2}(.*?)(?:\*{22}.*?\r?\n|$)") { $transcriptContent = $Matches[1] }
            
                            Write-Host '----------------------------------------------------------------------------------------------------------'
                            Write-Host $transcriptContent
                            Write-Host '----------------------------------------------------------------------------------------------------------'
                        }
            
                        Write-Host ">>> Cleanup transcript of Scheduled Task '$TaskName' under '$TaskPath'"
                        Remove-Item -Path $taskTranscript -Force -ErrorAction SilentlyContinue
            
                    }

                    if ($task) {

                        Write-Host ">>> Unregister Scheduled Task '$TaskName' under '$TaskPath'"
                        $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }
        }

    } catch {

        $exitCode = 1
        $taskError = $_.Exception.Message

        Write-Host "Invoking Scheduled Task failed: $taskError"

    } 

    return $exitCode
}

Export-ModuleMember -Function Invoke-ScheduledTask