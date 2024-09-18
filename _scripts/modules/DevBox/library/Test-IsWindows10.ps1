function Test-IsWindows10 {

    return (Get-WmiObject Win32_OperatingSystem | Select-Object -ExpandProperty Caption) -match 'Windows 10'
}

Export-ModuleMember -Function Test-IsWindows10