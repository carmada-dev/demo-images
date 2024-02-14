function Invoke-CommandLine {

    param(
        [Parameter(Mandatory=$true)]
        [string] $Command,
        [Parameter(Mandatory=$false)]
        [string] $Arguments,
        [Parameter(Mandatory=$false)]
        [string] $WorkingDirectory = (Get-Location | Select-Object -ExpandProperty Path),
        [Parameter(Mandatory=$false)]
        [ValidateSet('StdOut', 'StdErr')]
		[string] $Capture = 'StdOut',
        [Parameter(Mandatory=$false)]
        [string[]] $Mask = @()
    )

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.EnvironmentVariables["__COMPAT_LAYER"] = "RUNASINVOKER"
    $processInfo.FileName = $Command
    $processInfo.RedirectStandardError = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.Arguments = $Arguments
    $processInfo.WorkingDirectory = $WorkingDirectory

    Using-Object ($process = New-Object System.Diagnostics.Process) {
    
        Write-Host "| EXEC $WorkingDirectory> $Command $($Arguments | ConvertTo-MaskedString -Mask $Mask)"

        $process.StartInfo = $processInfo
        $process.Start() | Out-Null

        $output = (&{ if ($Capture -eq 'StdOut') { $process.StandardOutput.ReadToEnd() } else { $process.StandardError.ReadToEnd() } })
        $errout = (&{ if ($Capture -eq 'StdErr') { $null } else { $process.StandardError.ReadToEnd() } })

        $process.WaitForExit()

        [PSCustomObject]@{
            Output 	 = [string] $output
            Error    = [string] $errout
            ExitCode = $process.ExitCode
        }

        # if (-not($process.ExitCode -eq 0)) {            
        #     Write-Error (&{ if ($Capture -eq 'StdErr') { $output } else { $errout } })
        # }
    }
}

Export-ModuleMember -Function Invoke-CommandLine