function Write-ErrorMessage {
    
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Message
    )

    try
    {
        [Console]::ForegroundColor = 'red'
        [Console]::Error.WriteLine($Message)
    }
    finally
    {
        [Console]::ResetColor()
    }
}

Export-ModuleMember -Function Write-ErrorMessage