
function Get-GitHubLatestReleaseDownloadUrl {

    param(
		[Parameter(Mandatory=$true)]
        [string] $Organization,
		[Parameter(Mandatory=$true)]
        [string] $Repository,
		[Parameter(Mandatory=$false)]
        [string] $Release,		
		[Parameter(Mandatory=$false)]
        [string] $Asset		
	)

	$uri = "https://api.github.com/repos/$Organization/$Repository/releases"
    if (-not($Release)) { $uri += '/latest' }

	$get = Invoke-RestMethod -uri $uri -Method Get -ErrorAction Stop
    $rel = $get | Where-Object { -not($Release) -or ($_.name -Match $Release) } | Select-Object -First 1

    if ($Asset) {
        return ($rel.assets | Where-Object name -Match $Asset | Select-Object -First 1).browser_download_url
    } else {
        return ($rel.assets | Select-Object -First 1).browser_download_url
    }
}

Export-ModuleMember -Function Get-GitHubLatestReleaseDownloadUrl