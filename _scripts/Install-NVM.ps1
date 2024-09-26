Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-nvm.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not(Test-IsPacker)) {
    $url = Get-GitHubLatestReleaseDownloadUrl -Organization 'coreybutler' -Repository 'nvm-windows' -Asset "nvm-noinstall.zip"
    $downloadFolder = Invoke-FileDownload -Url $url -Name "nvm-noinstall.zip" -Expand

    # create env variables
    $nvm_home = "$($env:APPDATA)\nvm"
    [Environment]::SetEnvironmentVariable("NVM_HOME", $nvm_home, [System.EnvironmentVariableTarget]::User)
    [Environment]::SetEnvironmentVariable("NVM_SYMLINK","C:\Program Files\nodejs", [System.EnvironmentVariableTarget]::User)

    Move-Item -Path $downloadFolder -Destination "$nvm_home" -Force
    $USER_PATH = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
    [Environment]::SetEnvironmentVariable("PATH", "$USER_PATH$nvm_home;%NVM_SYMLINK%", [System.EnvironmentVariableTarget]::User)

$content = @"
root: $nvm_home 
path: C:\Program Files\nodejs 
arch: $(&{ if ([Environment]::Is64BitOperatingSystem) { '64' } else { '' } })
proxy: none
"@ # | Out-File -FilePath "$nvm_home/settings.txt" -Force -Encoding utf8

    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines("$nvm_home/settings.txt", $content, $Utf8NoBomEncoding)

    Write-Host ">>> Installed nvm into $nvm_home"
}