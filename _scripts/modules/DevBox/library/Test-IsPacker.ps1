function Test-IsPacker {
    return ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
}

Export-ModuleMember -Function Test-IsPacker
