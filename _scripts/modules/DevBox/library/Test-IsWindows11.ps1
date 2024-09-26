function Test-IsWindows11 {

    return (Get-WmiObject Win32_OperatingSystem | Select-Object -ExpandProperty Caption) -match 'Windows 11'
}

Export-ModuleMember -Function Test-IsWindows11