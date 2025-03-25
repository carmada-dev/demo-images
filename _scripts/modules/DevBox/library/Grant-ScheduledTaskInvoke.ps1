function Grant-ScheduledTaskInvoke {

    [Cmdletbinding(defaultParameterSetName='ByName')]

    param (

        [Parameter(ParameterSetName='ByName', Mandatory=$true, ValueFromPipeline=$true)]
        [string] $TaskName,

        [Parameter(ParameterSetName='ByName')]
        [string] $TaskPath = '\',

        [Parameter(ParameterSetName='ByTask', Mandatory=$true, ValueFromPipeline=$true)]
        [CimInstance] $Task
    )

    switch ($psCmdlet.ParameterSetName) {

        'ByName' {

            $Task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
            if (-not $Task) { throw "Scheduled Task '$TaskName' under '$TaskPath' does not exist" }

            $Task | Grant-ScheduledTaskInvoke

        }

        'ByTask' {
            
            $Scheduler = New-Object -ComObject "Schedule.Service"
            $Scheduler.Connect()
        
            $GetTask = $Scheduler.GetFolder($Task.TaskPath).GetTask($Task.TaskName)
            $GetSecurityDescriptor = $GetTask.GetSecurityDescriptor(0xF)
        
            if ($GetSecurityDescriptor -notmatch 'A;;0x1200a9;;;AU') {

                $GetSecurityDescriptor = $GetSecurityDescriptor + '(A;;GRGX;;;AU)'
                $GetTask.SetSecurityDescriptor($GetSecurityDescriptor, 0)
            }

        }
    }
    
    return $Task
}

Export-ModuleMember -Function Grant-ScheduledTaskInvoke