function Test-IsElevated {

    if (Test-IsSystem) { 
        return $true 
    } elseif (Test-IsLocalAdmin -ErrorAction SilentlyContinue) {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    return $false
}

Export-ModuleMember -Function Test-IsElevated