function Enable-ActiveSetup {

    $activeSetupKeyPath = 'HKLM:SOFTWARE\Microsoft\Active Setup\Installed Components'
    
    Get-ChildItem -Path $activeSetupKeyPath | Where-Object { (Split-Path $_.Name -Leaf) -match "^devbox-\d+-[0-9A-Fa-f]{8}[-]?[0-9A-Fa-f]{4}[-]?[0-9A-Fa-f]{4}[-]?[0-9A-Fa-f]{4}[-]?[0-9A-Fa-f]{12}$" } | Foreach-Object {
        Write-Host "- Enabling ActiveSetup Task: $(Split-Path $_.Name -Leaf)"
        $_ | Set-ItemProperty -Name 'IsInstalled' -Value 1
    }
        
}

Export-ModuleMember -Function Enable-ActiveSetup