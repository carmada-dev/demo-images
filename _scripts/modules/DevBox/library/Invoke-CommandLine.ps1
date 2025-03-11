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
        [string[]] $Mask = @(),
        [Parameter(Mandatory=$false)]
        [switch] $AsSystem,
        [Parameter(Mandatory=$false)]
        [switch] $Silent,
        [Parameter(Mandatory=$false)]
        [switch] $NoWait
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

    if ($AsSystem) {

        if (-not(Test-IsElevated)) {
            throw "This command requires administrative privileges."
        }

        $psexec = Join-Path $Env:DEVBOX_HOME "Tools\PsExec$(&{ if ([Environment]::Is64BitOperatingSystem) { '64' } else { '' } }).exe"

        if (-not(Test-Path $psexec)) {
            throw "PsExec executable not found at $psexec."
        }

        $processInfo.FileName = $psexec
        $processInfo.Arguments = "-accepteula -nobanner -s $Command $Arguments"

        if (-not $Silent) {
            Write-Host "| EXEC $WorkingDirectory> $psexec -accepteula -nobanner -s $Command $($Arguments | ConvertTo-MaskedString -Mask $Mask)"
        }

    } elseif (-not $Silent) {

        Write-Host "| EXEC $WorkingDirectory> $Command $($Arguments | ConvertTo-MaskedString -Mask $Mask)"
    }

    Using-Object ($process = New-Object System.Diagnostics.Process) {        

        $process.StartInfo = $processInfo
        $process.Start() | Out-Null

        if (-not $NoWait) {

            $output = (&{ if ($Capture -eq 'StdOut') { $process.StandardOutput.ReadToEnd() } else { $process.StandardError.ReadToEnd() } })
            $errout = (&{ if ($Capture -eq 'StdErr') { $null } else { $process.StandardError.ReadToEnd() } })

            $process.WaitForExit()

            [PSCustomObject]@{
                Output 	 = [string] $output
                Error    = [string] $errout
                ExitCode = $process.ExitCode
            }
        }
    }
}

Export-ModuleMember -Function Invoke-CommandLine