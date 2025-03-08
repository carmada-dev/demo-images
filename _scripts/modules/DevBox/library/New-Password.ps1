function New-Password {
    
    param(
        [Parameter(Mandatory = $false)]
        [int] $Length = 16
    )

    return (-join ((65..90) + (97..122) + (48..57) + (33..47) + (58..64) | Get-Random -Count $Length | ForEach-Object { [char]$_ }))

}

Export-ModuleMember -Function New-Password