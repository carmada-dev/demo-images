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

        Invoke-ScriptSection -Title "Configure git" -ScriptBlock {
            
            Write-Host ">>> Ensure git user name" 

            $gitUserName = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.name' | Select-Object -ExpandProperty Output) -split "\r?\n") `
                | Where-Object { $_ } `
                | Select-Object -First 1 `
                | Out-String

            if (-not($gitUserName)) { 
                Invoke-CommandLine -Command 'git' -Arguments "config --global user.name `"Packer`"" | Select-Object -ExpandProperty Output | Write-Host
            }

            Write-Host ">>> Ensure git user email" 
            
            $gitUserEmail = ((Invoke-CommandLine -Command 'git' -Arguments 'config user.email' | Select-Object -ExpandProperty Output) -split "\r?\n") `
                | Where-Object { $_ } `
                | Select-Object -First 1 `
                | Out-String

            if (-not($gitUserEmail)) { 
                Invoke-CommandLine -Command 'git' -Arguments "config --global user.email `"packer@microsoft.com`"" | Select-Object -ExpandProperty Output | Write-Host
            }

        }
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

        Invoke-ScriptSection -Title "Cloning repositories" -ScriptBlock {

            $ddl = Get-Volume | ? { $_.FileSystemType -eq 'ReFS' } | Sort { $_.DriveLetter } | Select -First 1 -ExpandProperty DriveLetter
            $repoHome = New-Item -Path "$($ddl):\\repositories" -ItemType Directory -Force -ErrorAction SilentlyContinue | Select -ExpandProperty FullName 

            @( 'Az.Accounts' ) `
            | ForEach-Object { 
                if (Get-Module -ListAvailable -Name $_) {
                    Write-Host ">>> Upgrading Powershell Module: $_ module";
                    Update-Module -Name $_ -AcceptLicense -Force -WarningAction SilentlyContinue -ErrorAction Stop
                } else {
                    Write-Host ">>> Installing Powershell Module: $_ module";
                    Install-Module -Name $_ -AcceptLicense -Repository PSGallery -Force -AllowClobber -WarningAction SilentlyContinue -ErrorAction Stop
                }
            }
        
            Write-Host ">>> Connect Azure"
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null

            $repositories | Where-Object { $_ } | ForEach-Object {

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
