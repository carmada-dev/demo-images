Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Install-WSL2.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function Clear-WslOutput() {

    param (
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
        [string] $Output
    )

    if ($Output) {
        return ($Output -replace "`r`n?", "`r`n" -replace "`0", "" -split "`r?`n" | Where-Object { -not ([System.String]::IsNullOrWhiteSpace($_)) } | Out-String) -replace "`r?`n$", ''
    } else {
        return $Output
    }
}

Invoke-ScriptSection -Title "Installing WSL2" -ScriptBlock {

	if (-not(Get-Command wsl -ErrorAction SilentlyContinue)) {
		Write-Host "Could not find wsl.exe"
		exit 1
	}

	if (Test-IsPacker) {

		Write-Host ">>> Downloading WSL2 kernel update ..."
		$installer = Invoke-FileDownload -url "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"

		Write-Host ">>> Installing WSL2 kernel update ..."
		Invoke-CommandLine -Command 'msiexec' -Arguments "/I $installer /quiet /norestart" | Select-Object -ExpandProperty Output | Write-Host
	}

	Write-Host ">>> Installing WSL2 ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--install" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

	Write-Host ">>> Setting default WSL version to 2 ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--set-default-version 2" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

	Write-Host ">>> Enforcing WSL update ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--update --web-download" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

	Write-Host ">>> WSL status ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--status" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host

    # Fetching list of installed distributions
    $distros = (Invoke-CommandLine -Command 'wsl' -Arguments "--list --quiet" -Silent | Select-Object -ExpandProperty Output | Clear-WslOutput) -split "\r?\n"

	if ($distros -notcontains 'Ubuntu') {

		Write-Host ">>> Installing WSL default distribution (Ubuntu) ..."
		Invoke-CommandLine -command 'wsl' -arguments "--install --distribution Ubuntu --no-launch" | select-object -expandproperty output | Clear-WslOutput | Write-Host

        # Updating list of installed distributions
        $distros = (Invoke-CommandLine -Command 'wsl' -Arguments "--list --quiet" -Silent | Select-Object -ExpandProperty Output | Clear-WslOutput) -split "\r?\n"
	}

    $distros | ForEach-Object {

		# determine if the distribution is running or not - we try to ensure that every distribution is running
        $running = ((Invoke-CommandLine -Command 'wsl' -Arguments "--list --verbose" -Silent | Select-Object -ExpandProperty Output | Clear-WslOutput) -split "\r?\n" | Select-String -Pattern $_) -match 'Running'

        if (-not $running) {

            Write-Host ">>> Starting WSL distribution '$_' ..."
            Invoke-CommandLine -Command 'wsl' -Arguments "--distribution $_ --exec /bin/sh -c `"exit`"" | Out-Null
        }
    }

	Write-Host ">>> WSL distributions overview ..."
	Invoke-CommandLine -Command 'wsl' -Arguments "--list --verbose" | Select-Object -ExpandProperty Output | Clear-WslOutput | Write-Host	
}