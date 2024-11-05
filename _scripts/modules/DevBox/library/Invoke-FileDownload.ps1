function Invoke-FileDownload {

	param(
		[Parameter(Mandatory=$true)]
        [string] $Url,
		[Parameter(Mandatory=$false)]
        [string] $Name,
		[Parameter(Mandatory=$false)]
        [uint32] $Retries = 0,
        [switch] $Expand		
	)

	
    $path = Join-Path -path $env:temp -ChildPath (Split-Path $Url -leaf)
	if ($Name) { $path = Join-Path -Path $env:temp -ChildPath $Name }
	
    if (-not(Test-Path -Path $path -PathType Leaf)) {
    
        [uint32] $retryCount = 0
    
        while($true) {
            try {
                Write-Host ">>> Downloading $Url > $path $(&{ if ($retryCount -gt 0) { " (Retry: $retryCount of $Retries)" } else { '' } })".Trim() 
                Invoke-WebRequest -Uri $Url -OutFile $path; break
            }
            catch {
                $retryCount = $retryCount + 1
                if ($retryCount -gt $Retries) { throw }
            }
        }
    }

    if (Test-Path -Path $path -PathType Leaf) { 
    
        Write-Host ">>> Unblock $path"
        Unblock-File $path -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    }

	if ($Expand) {

		$archive = Join-Path -path $env:temp -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($path))
        
        if (-not(Test-Path -Path $archive -PathType Container)) {

            Write-Host ">>> Expanding $path > $archive"
		    Expand-Archive -Path $path -DestinationPath $archive -Force

            Get-ChildItem -Path $archive -Recurse -File -Filter '*.*' | ForEach-Object {
                Write-Host ">>> Unblock: $($_.FullName)"
                Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            }
        }

		return $archive
	}
	
	return $path
}

Export-ModuleMember -Function Invoke-FileDownload