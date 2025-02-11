function Invoke-ScriptSection {
    param(
        [Parameter(Mandatory = $true)]
        [String] $Title,
        
        [Parameter(Mandatory = $true)]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        $Info        
    )

    $failed = $false
    $started = Get-Date
    $dblLine = "=========================================================================================================="
    $sglLine = "----------------------------------------------------------------------------------------------------------"

    try
    {        
        @(
            $dblLine, 
            $Title, 
            $sglLine
        ) | Write-Host 

        if ($Info -and ($Info -is [hashtable] -or $Info -is [object] -or $Info -is [string])) {
            if ($Info -is [hashtable]) { 
                ($Info | Format-Table -HideTableHeaders -AutoSize -Wrap | Out-String).Trim() | Write-Host
            } elseif ($Info -is [object]) { 
                ($Info | ConvertTo-Hashtable | Format-Table -HideTableHeaders -AutoSize -Wrap | Out-String).Trim() | Write-Host
            } else {
                $Info | Write-Host
            }
            $sglLine | Write-Host 
        }

        $measure = Measure-Command -Expression { . $ScriptBlock }    
    }
    catch
    {
        Write-Host $sglLine
        Write-Error $_        

        $failed = $true
    }
    finally
    {
        if (-not($measure)) { 
            # no command measure available - do some manual calculation
            $measure = New-TimeSpan -Start $started -End (Get-Date) 
        }

        @(
            $sglLine, 
            "Finished after $($measure.ToString("hh\:mm\:ss\.fff")) as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) $(&{ if (Test-IsElevated -ErrorAction SilentlyContinue) { '(elevated)' } else { '' } }) - PSVersion $($PSVersionTable.PSVersion.ToString())", 
            $dblLine
        ) | Write-Host
    }

    if ($failed) { 
        $exitCode = [System.Math]::Max($LASTEXITCODE, 1)
        exit $exitCode
    }
}

Export-ModuleMember -Function Invoke-ScriptSection