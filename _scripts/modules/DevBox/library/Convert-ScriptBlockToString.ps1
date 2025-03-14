function Convert-ScriptBlockToString {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [scriptblock] $ScriptBlock,
        [Parameter(Mandatory=$false)]
        [Hashtable] $ScriptTokens = @{},
        [Parameter(Mandatory = $false)]
        [string] $Transcript,
        [Parameter(Mandatory = $false)]
        [switch] $EncodeBase64
    )    

    
    # Convert the script block to a string
    $script = $ScriptBlock.ToString()

    # Replace script tokens
    $ScriptTokens.Keys | ForEach-Object { 
        $script = $script -replace "\[$_\]", $ScriptTokens[$_] 
    }

    # Remove single-line comments (starting with #)
    $script = $script -replace '(?m)^\s*#.*$', ''   

    # Remove empty lines in the middle of the script and at the end
    $script = $script -replace '(?m)^(\s|\t)*\r?\n', '' -replace '\r?\n(\s|\t)*$', ''

    # Replace all indentation tabs with 4 spaces and remove the CRLF that comes with out-string
    $script = ($script -split "`r?`n" `
        | ForEach-Object { $_ -replace "`t", "    " } `
        | Out-String) -replace '\r?\n$', ''

    # Resolve the indentation size we can safely remove
    $indentationSize = ($script -split "`r?`n" `
        | ForEach-Object { if ($_ -match '^\s*') { $Matches[0].Length } else { 0 } } `
        | Measure-Object -Minimum).Minimum

    # Remove the indentation size if possible (>0)
    if ($indentationSize -gt 0) { 
        $script = $script -replace "(?m)^\s{$indentationSize}", '' 
    }

    if ($Transcript) {
        $scriptHeader = "Start-Transcript -Path '$Transcript' -Force; try { "
        $scriptFooter = "} finally { Stop-Transcript -ErrorAction SilentlyContinue }"
        $script = ($scriptHeader, $script, $scriptFooter) -join "`r`n"
    }

    if ($EncodeBase64) {
        $script = $script | Convert-ToBase64
    } 

    return $script
}

Export-ModuleMember -Function Convert-ScriptBlockToString