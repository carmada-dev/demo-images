param(
    [Parameter(Mandatory=$false)]
    [boolean] $Packer = ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0)
)

Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

function Get-PropertyValue {
    
	param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [object] $DefaultValue 
    )

    $value = ($InputObject | Select -ExpandProperty $Name -ErrorAction SilentlyContinue)

    if (-not($value)) { 
        $value = $DefaultValue 
    }

	return $value
}

$driveConfig = '${jsonencode(devDrive)}' | ConvertFrom-Json
$repositories = [array]($driveConfig | Get-PropertyValue -Name "repositories" -DefaultValue @())

if ($Packer) {

    if (Get-Command 'git') {

        $configureGit = {
            
            Write-Host ">>> Ensure git user name" 

            $gitUserName = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.name' | Select-Object -ExpandProperty Output) -split "\r?\n") `
                | Where-Object { $_ } `
                | Select-Object -First 1 `
                | Out-String

            if (-not($gitUserName)) { 

                if ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0) {
                    $gitUserName = 'Packer'
                } else {
                    $gitUserName = Get-ChildItem -Path HKCU:\Software\Microsoft\OneDrive\Accounts -Recurse | Get-ItemPropertyValue -Name UserName -ErrorAction SilentlyContinue | Select-Object -First 1
                }

                if ($gitUserName) { Invoke-CommandLine -Command 'git' -Arguments "config --global user.name `"$gitUserName`"" | Select-Object -ExpandProperty Output | Write-Host }
            }

            Write-Host ">>> Ensure git user email" 
            
            $gitUserEmail = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.email' | Select-Object -ExpandProperty Output) -split "\r?\n") `
                | Where-Object { $_ } `
                | Select-Object -First 1 `
                | Out-String

            if (-not($gitUserEmail)) { 

                if ((Get-ChildItem env:packer_* | Measure-Object).Count -gt 0) {
                    $gitUserEmail = 'packer@microsoft.com'
                } else {
                    $gitUserEmail = Get-ChildItem -Path HKCU:\Software\Microsoft\OneDrive\Accounts -Recurse | Get-ItemPropertyValue -Name UserEmail -ErrorAction SilentlyContinue | Select-Object -First 1
                }
                
                if ($gitUserEmail) { Invoke-CommandLine -Command 'git' -Arguments "config --global user.email `"$gitUserEmail`"" | Select-Object -ExpandProperty Output | Write-Host }
            }

        }

        Invoke-ScriptSection -Title "Configure git" -ScriptBlock $configureGit

        $taskScriptSource = $configureGit | Out-String -Width ([int]::MaxValue)
        $taskScriptEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($taskScriptSource)))
        $taskAction = New-ScheduledTaskAction -Execute 'PowerShell' -Argument "-NoLogo -NoProfile -NonInteractive -EncodedCommand $taskScriptEncoded"
        $taskPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew 
        $taskTriggers = @( New-ScheduledTaskTrigger -AtLogOn -RandomDelay (New-TimeSpan -Minutes 5) )

        Register-ScheduledTask -Force -TaskName 'Configure Git' -TaskPath '\' -Action $taskAction -Trigger $taskTriggers -Settings $taskSettings -Principal $taskPrincipal | Out-Null
    } 

    if ($repositories) {

        if (-not(Get-Volume | ? { $_.FileSystemType -eq 'ReFS' })) { 
            Write-Error "Could not find DevDrive"
            exist 1
        } 

        if (-not(Get-Command 'git')) {
            Write-Error "The 'git' command could not be found."
            exist 1
        }

        if ($repositories | Where-Object { ($_) -and ($_ | Get-PropertyValue -Name "repoUrl" -DefaultValue '') }) {
            Invoke-ScriptSection -Title "Connecting Azure" -ScriptBlock {

                @( 'Az.Accounts' ) `
                | Where-Object { -not(Get-Module -ListAvailable -Name $_) } `
                | ForEach-Object { 
                    Write-Host ">>> Installing $_ module";
                    Install-Module -Name $_ -Repository PSGallery -Force -AllowClobber 
                }
            
                Write-Host ">>> Connect Azure"
                Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
            }
        }

        Invoke-ScriptSection -Title "Cloning repositories" -ScriptBlock {

            [string] $repoHome = $null

            $repositories | ForEach-Object -Begin {

                $ddl = Get-Volume | ? { $_.FileSystemType -eq 'ReFS' } | Sort { $_.DriveLetter } | Select -First 1 -ExpandProperty DriveLetter
                if ($ddl) { $repoHome = New-Item -Path "$($ddl):\\repositories" -ItemType Directory -Force | Select -ExpandProperty FullName }

            } -Process {

                if ($_) {

                    $repoUrl = $_ | Get-PropertyValue -Name "repoUrl" -DefaultValue ''

                    if ($repoUrl) {

                        Write-Host ">>> Cloning $repoUrl"

                        $repoTokenUrl = $_ | Get-PropertyValue -Name "tokenUrl" -DefaultValue ''
                        $repoToken = $null

                        if ($repoTokenUrl) {

                            $keyVaultEndpoint = (Get-AzEnvironment -Name AzureCloud | Select-Object -ExpandProperty AzureKeyVaultServiceEndpointResourceId)
                            $keyVaultToken = Get-AzAccessToken -ResourceUrl $keyVaultEndpoint -ErrorAction Stop
                            $keyVaultHeaders = @{"Authorization" = "Bearer $($keyVaultToken.Token)"}
                            $keyVaultResponse = Invoke-RestMethod -Uri "$($repoTokenUrl)?api-version=7.1" -Headers $KeyVaultHeaders -ErrorAction Stop

                            $repoToken = $keyVaultResponse.value
                        }

                        if ($repoToken) {
                            
                            $uriBuilder = new-object System.UriBuilder -ArgumentList $repoUrl
                            $uriBuilder.UserName = ($uriBuilder.Host.Split('.', [StringSplitOptions]::RemoveEmptyEntries)[0])
                            $uriBuilder.Password = $repoToken

                            $repoUrl = $uriBuilder.Uri.ToString()
                        }

                        Invoke-CommandLine -Command 'git' -Arguments "clone --quiet $repoUrl" -WorkingDirectory $repoHome -Mask @( $repoToken ) `
                            | Select-Object -ExpandProperty Output `
                            | Write-Host
                    }
                }
            }
        }
    }
}
