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
    $taskFullname = Join-Path -Path $TaskPath -ChildPath $TaskName

    Write-Host ">>> Preparing Scheduled Task command / script ..."
    $taskScript = $ScriptBlock | Convert-ScriptBlockToString -ScriptTokens $ScriptTokens -Transcript $taskTranscript

    Write-Host '----------------------------------------------------------------------------------------------------------'
    Write-Host $taskScript
    Write-Host '----------------------------------------------------------------------------------------------------------'

    $taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $($taskScript | ConvertTo-Base64)"
    $taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
    $taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn )
    
    Write-Host ">>> Registering Scheduled Task $taskFullname"
    $task = Register-ScheduledTask -Force -TaskName $taskName -TaskPath $taskPath -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal		

    try {

        Write-Host ">>> Executing Scheduled Task $taskFullname ($Timeout minutes timeout)"
        $exitCode = $task | Wait-ScheduledTask -Start

    } finally {

        Write-Host ">>> Reading transcript of Scheduled Task $taskFullname ($taskTranscript)"
        $transcriptContent = Get-Content -Path $taskTranscript -Raw -ErrorAction SilentlyContinue

        if ($transcriptContent) {

            Write-Host '----------------------------------------------------------------------------------------------------------'
            Write-Host $transcriptContent
            Write-Host '----------------------------------------------------------------------------------------------------------'
        }

        Write-Host ">>> Cleanup transcript of Scheduled Task $taskFullname ($taskTranscript)"
        Remove-Item -Path $taskTranscript -Force -ErrorAction SilentlyContinue

        if ($task) {

            Write-Host ">>> Unregister Scheduled Task $taskFullname"
            $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    return $exitCode
}

Export-ModuleMember -Function Invoke-AsScheduledTask