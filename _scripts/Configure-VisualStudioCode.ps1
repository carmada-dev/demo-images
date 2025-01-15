Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup  -Path $MyInvocation.MyCommand.Path -Name 'Configure-VisualStudioCode.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

$vscode = Get-Command 'code' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if ($vscode) {

	$extFolder = Join-Path $env:DEVBOX_HOME 'Artifacts\VisualStudioCode\extensions'
	$extOffline = Join-Path $env:DEVBOX_HOME 'Artifacts\VisualStudioCode\extensions.offline'
	$extOnline = Join-Path $env:DEVBOX_HOME 'Artifacts\VisualStudioCode\extensions.online'
	
	if (Test-IsPacker) {

			Invoke-ScriptSection -Title "Downloading offline extensions" -ScriptBlock {
				if (Test-Path -Path $extOffline -PathType Leaf) {

					Write-Host ">>> Ensure extensions folder exists: $extFolder"
					New-Item -Path $extFolder -ItemType Directory -Force | Out-Null

					Get-Content -Path $extOffline -ErrorAction SilentlyContinue | Where-Object { -not([System.String]::IsNullOrWhiteSpace($extOffline)) } | ForEach-Object {

						Write-Host ">>> Downloading extension: $_"

						$tokens = "$_".Split('.')
						$publisher = $tokens[0]
						$package = $tokens[1]

						$url = "https://$publisher.gallery.vsassets.io/_apis/public/gallery/publisher/$publisher/extension/$package/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
						$extVsix = Join-Path -Path $extFolder -ChildPath "$publisher.$package.vsix"
						$extTemp = Invoke-FileDownload -url $url -name "$publisher.$package.vsix"

						Write-Host ">>> Moving extension to $extVsix"
						Move-Item -Path $extTemp -Destination $extVsix -Force | Out-Null
					}

				} else {

					Write-Host ">>> Extension list not found: $extOffline"
				}
			}

	} else {

		Invoke-ScriptSection -Title "Installing online extensions" -ScriptBlock {
			if (Test-Path -Path $extOnline -PathType Leaf) {

				Get-Content -Path $extOnline -ErrorAction SilentlyContinue | Where-Object { -not([System.String]::IsNullOrWhiteSpace($_)) } | ForEach-Object {

					Write-Host ">>> Installing extension: $_"
					Invoke-CommandLine -Command $vscode -Arguments "--install-extension $_" | Select-Object -ExpandProperty Output
				}

			} else {
				
				Write-Host ">>> Extension list not found: $extOnline"
			}
		}

		Invoke-ScriptSection -Title "Installing offline extensions" -ScriptBlock {
			if (Test-Path -Path $extFolder -PathType Container) {

				Get-ChildItem -Path $extFolder -Filter '*.vsix' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | ForEach-Object {

					Write-Host ">>> Installing extension: $_"
					Invoke-CommandLine -Command $vscode -Arguments "--install-extension $_" | Select-Object -ExpandProperty Output
				}

			} else {
				
				Write-Host ">>> Extension folder not found: $extFolder"
			}
		}

	}

} else {

	Write-Host ">>> Visual Studio Code is not installed"
}