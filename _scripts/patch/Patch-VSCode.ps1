# # Copyright (c) Microsoft Corporation.
# # Licensed under the MIT License.

# $ProgressPreference = 'SilentlyContinue'	# hide any progress output

# $extensions = (
# 	"eamodio.gitlens",
# 	"telesoho.vscode-markdown-paste-images",
# 	"ms-azuretools.vscode-bicep",
# 	"ms-azuretools.vscode-docker",
# 	"ms-vscode-remote.remote-containers",
# 	"ms-vscode-remote.remote-ssh",
# 	"ms-vscode-remote.remote-wsl",
# 	"ms-vscode.azurecli",
# 	"ms-vscode.powershell"
# )

# $process = Start-Process code -ArgumentList "--version" -NoNewWindow -Wait -PassThru

# if ($process.ExitCode -eq 0) {
# 	$extensions | ForEach-Object -Begin { Write-Host ">>> Installing VSCode extensions ..." } -Process {
# 		Write-Host "- $_"
# 		$process = Start-Process code -ArgumentList ("--install-extension", $_) -NoNewWindow -Wait -PassThru -RedirectStandardOutput "NUL"
# 		if ($process.ExitCode -ne 0) { exit $process.ExitCode }
# 	}
# }

# exit $process.ExitCode