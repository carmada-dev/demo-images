function Clear-DockerProgress {

    param (
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
        [string] $DockerOutput
    )
    
    if ($DockerOutput) { $DockerOutput = $DockerOutput -split "`r?`n" | Where-Object { "$_" -notmatch '\[=*>\s+\]' } | Select-Object -Unique | Out-String }

    return $DockerOutput
}

Export-ModuleMember -Function Clear-DockerProgress