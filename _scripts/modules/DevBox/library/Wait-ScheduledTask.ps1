function Wait-ScheduledTask {

    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [CimInstance] $Task,
        [Parameter(Mandatory=$false)]
        [timespan] $Timeout = (New-TimeSpan -Minutes 5)
    )

    $taskFullname = "$($Task.Path)$($Task.TaskName)"
    $timeoutEnd = (Get-Date).Add($Timeout)
    $running = $false

    while ($true) {
    
        if ($timeoutEnd -lt (Get-Date)) { 
        
            # we ran into a timeout - blow it up				
            throw "Scheduled Task $taskFullname timed out after $Timeout minutes" 
        
        } else {

            # refresh the Task to ensure we deal with the latest state         
            $Task = Get-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction SilentlyContinue            
        
        }

        if (-not($Task)) { 

            # the Task does not exist anymore - blow it up
            throw "Scheduled Task $taskFullname does not exist anymore" 

        }
        elseif ($running) {

            if ($Task.State -ne 'Running') { 

                $exitCode = $Task | Get-ScheduledTaskInfo | Select-Object -ExpandProperty LastTaskResult
                Write-Host ">>> Scheduled Task $taskFullname finished with exit code $exitCode"
                
                break # exit the loop
            }

            Write-Host ">>> Waiting for Scheduled Task $taskFullname to finish ..."
            Start-Sleep -Seconds 5 # give the Task some time to finish

        } else {

            $running = $running -or ($Task.State -eq 'Running') # determine if we are in running state

            if ($running) { 
                Write-Host ">>> Scheduled Task $taskFullname starts running ..." 
            } else {
                Write-Host ">>> Scheduled Task $taskFullname is in state $($Task.State) ..."
            }
        }
    }

}

Export-ModuleMember -Function Wait-ScheduledTask