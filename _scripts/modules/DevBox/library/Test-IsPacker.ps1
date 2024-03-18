function Test-IsPacker {
    return ($env:USERNAME -eq 'packer')
}

Export-ModuleMember -Function Test-IsPacker
