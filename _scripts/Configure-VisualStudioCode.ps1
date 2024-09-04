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

Invoke-ScriptSection -Title "Configure Visual Studio Code" -ScriptBlock {

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

}