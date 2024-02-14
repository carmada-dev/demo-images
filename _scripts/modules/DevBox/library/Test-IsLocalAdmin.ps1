function Test-IsLocalAdmin {

    param(
        [Parameter(Mandatory = $false)]
        [string] $Username = "$(whoami)"
    )

    $adminGroupSid = 'S-1-5-32-544'
    $adminGroupName = Get-LocalGroup -SID $adminGroupSid | Select-Object -ExpandProperty Name 
    $adminMembers = Get-LocalGroupMember -Name $adminGroupName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty name    
    
    if (-not($adminMembers)) {
        # this is a fallback to cover a bug in Get-LocalGroupMember on Windows 11
        $adminMembers = ([ADSI]"WinNT://$env:COMPUTERNAME/$adminGroupName").Invoke('Members') | Foreach-Object { "$(Split-Path (Split-Path ([ADSI]$_).path) -Leaf)\$(Split-Path (([ADSI]$_).path) -Leaf)"  }
    }
    
    $adminMembers -contains $Username
}

Export-ModuleMember -Function Test-IsLocalAdmin