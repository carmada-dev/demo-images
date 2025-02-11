function Test-IsSystem {
    return ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.value -eq 'S-1-5-18')
}

Export-ModuleMember -Function Test-IsSystem
