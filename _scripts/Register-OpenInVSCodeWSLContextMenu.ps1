Get-ChildItem -Path (Join-Path $env:DEVBOX_HOME 'Modules') -Directory | Select-Object -ExpandProperty FullName | ForEach-Object {
	Write-Host ">>> Importing PowerShell Module: $_"
	Import-Module -Name $_
} 

if (Test-IsPacker) {
	Write-Host ">>> Register ActiveSetup"
	Register-ActiveSetup -Path $MyInvocation.MyCommand.Path -Name 'Register-OpenInVSCodeWSLContextMenu.ps1'
} else { 
    Write-Host ">>> Initializing transcript"
    Start-Transcript -Path ([system.io.path]::ChangeExtension($MyInvocation.MyCommand.Path, ".log")) -Append -Force -IncludeInvocationHeader; 
}

$ProgressPreference = 'SilentlyContinue'	# hide any progress output
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==============================================================================

if (Test-IsPacker) {
    Write-Host ">>> Skipping context menu registration in Packer mode."
    exit 0
}

$menuItems = @(
    @{ 
        Name = "Open in VS Code (WSL)"
        Keys = @(
            @{ Path = "HKCU:\Software\Classes\Directory\shell\Open in VS Code (WSL)"; Arg = '%1' },
            @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\Open in VS Code (WSL)"; Arg = '%V' }
        )
        UseDefault = $false
    },
    @{ 
        Name = "Open in VS Code (WSL - Default)"
        Keys = @(
            @{ Path = "HKCU:\Software\Classes\Directory\shell\Open in VS Code (WSL - Default)"; Arg = '%1' },
            @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\Open in VS Code (WSL - Default)"; Arg = '%V' }
        )
        UseDefault = $true
    }
)

# Check if WSL is available
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host "WSL is not installed or not available in PATH. Exiting."
    exit 0
}

# Check if VS Code is available
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host "VS Code is not installed or not available in PATH. Exiting."
    exit 0
} 

# Resolve code.exe from code.cmd
$codePath = Get-Command code -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if ([System.IO.Path]::GetExtension($codePath) -ne '.exe') {
    $codePath = Join-Path (Split-Path $codePath -Parent) '..\code.exe'
    $codePath = [System.IO.Path]::GetFullPath($codePath)
}

$utilsHome = New-Item -Path "$env:USERPROFILE\.utils" -ItemType Directory -Force | Select-Object -ExpandProperty FullName
$utilsScriptPath = Join-Path $utilsHome "wsl-vscode-open.ps1"
$utilsHiddenPath = Join-Path $utilsHome "wsl-vscode-hidden.vbs"

@"
param(
    [Parameter(Mandatory)]
    [string]`$Path,
    [switch]`$Default
)

Start-Transcript -Path ([System.IO.Path]::ChangeExtension(`$MyInvocation.MyCommand.Path, '.log')) -ErrorAction SilentlyContinue

function Show-RadioSelectorDialog {
    param (
        [string[]]`$Options,
        [string]`$Title = "Choose an Option",
        [string]`$Preselect = `$null
    )

    Add-Type -AssemblyName System.Windows.Forms | Out-Null

    `$form = New-Object System.Windows.Forms.Form
    `$form.Text = `$Title
    `$form.FormBorderStyle = 'FixedDialog'
    `$form.StartPosition = 'CenterScreen'
    `$form.Size = '300,400'
    `$form.MaximizeBox = `$false
    `$form.MinimizeBox = `$false
    `$form.ShowIcon = `$false
    `$form.Topmost = `$true

    `$panel = New-Object System.Windows.Forms.Panel
    `$panel.Location = '10,10'
    `$panel.Size = '260,300'
    `$panel.AutoScroll = `$true
    `$form.Controls.Add(`$panel) | Out-Null

    `$radioButtons = @()
    for (`$i = 0; `$i -lt `$Options.Count; `$i++) {
        `$rb = New-Object System.Windows.Forms.RadioButton
        `$rb.Text = `$Options[`$i]
        `$rb.Location = "10,`$(`$i * 25)"
        `$rb.AutoSize = `$true
        `$rb.TabIndex = `$i
        `$rb.Checked = (`$Options[`$i] -eq `$Preselect)
        `$panel.Controls.Add(`$rb) | Out-Null
        `$radioButtons += `$rb
    }

    if (`$radioButtons.Count -gt 0) {
        # If no radioButton is preselected, select the first one by default
        if (-not (`$radioButtons | Where-Object { `$_.Checked -eq `$true })) {            
            # assigning to `$null to suppress pipeline output
            `$null = `$radioButtons[0].Checked = `$true
        }
        # Focus first radio button
        `$radioButtons[0].Focus() | Out-Null
    }

    # Separator line
    `$separator = New-Object System.Windows.Forms.Label
    `$separator.BorderStyle = 'Fixed3D'
    `$separator.AutoSize = `$false
    `$separator.Height = 2
    `$separator.Width = 260
    `$separator.Location = '10,315'
    `$form.Controls.Add(`$separator) | Out-Null

    `$okButton = New-Object System.Windows.Forms.Button
    `$okButton.Text = 'OK'
    `$okButton.Location = '110,325'
    `$okButton.Size = '75,30'
    `$okButton.TabIndex = `$Options.Count
    `$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    `$form.Controls.Add(`$okButton) | Out-Null

    `$cancelButton = New-Object System.Windows.Forms.Button
    `$cancelButton.Text = 'Cancel'
    `$cancelButton.Location = '195,325'
    `$cancelButton.Size = '75,30'
    `$cancelButton.TabIndex = `$Options.Count + 1
    `$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    `$form.Controls.Add(`$cancelButton) | Out-Null

    `$form.AcceptButton = `$okButton
    `$form.CancelButton = `$cancelButton

    `$dialogResult = `$form.ShowDialog() | Out-Null
    `$dialogResult = `$form.DialogResult
    `$dialogSelected = `$null

    if (`$dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        # Get the text of the selected radio button
        `$dialogSelected = `$radioButtons | Where-Object { `$_.Checked -eq `$true } | Select-Object -First 1 -ExpandProperty Text
    } 

    return `$dialogSelected
}

function Quote-String {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = `$true, ValueFromPipeline = `$true)]
        [string]`$InputString,
        [switch]`$UseSingleQuotes
    )

    `$quoteChar = if (`$UseSingleQuotes) { "'" } else { '"' }
    return @(`$quoteChar, `$InputString, `$quoteChar) -join ''
}

function Invoke-WSL {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = `$true)]
        [string[]]`$Arguments,
        [Parameter(Mandatory = `$false)]
        [string]`$Distro = `$null,
        [switch]`$NoWait
    )

    # Build argument string
    `$argString = "`$(if (`$Distro) { "-d `$Distro" } else { '' }) `$(`$Arguments -join ' ')".Trim()

    # Configure process start info
    `$psi = New-Object System.Diagnostics.ProcessStartInfo
    `$psi.FileName = "wsl"
    `$psi.Arguments = `$argString
    `$psi.RedirectStandardOutput = `$true
    `$psi.UseShellExecute = `$false
    `$psi.StandardOutputEncoding = if (`$Distro) { [System.Text.Encoding]::UTF8 } else { [System.Text.Encoding]::Unicode }

    # Start process
    `$proc = [System.Diagnostics.Process]::Start(`$psi)

    if (-not `$NoWait) {

        # Capture output
        `$output = `$proc.StandardOutput.ReadToEnd()
        `$proc.WaitForExit()

        # Emit clean lines
        return `$output -split "`\r?`\n" | ForEach-Object { `$_.Trim() } | Where-Object { `$_ -ne "" }
    }
}

# Check if WSL is available
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host "WSL is not installed or not available in PATH. Exiting."
    exit 1
}

# Check if VS Code is available
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host "VS Code is not installed or not available in PATH. Exiting."
    exit 1
}

# Fetch default WSL distro
`$distros = Invoke-WSL -Arguments @('-l', '-q') | Where-Object { `$_ -ne 'docker-desktop' }
`$distro = `$distros | Select-Object -First 1

if (-not `$distros) {

    Write-Host "No WSL distributions found!"
    exit 1

} elseif ((-not `$Default) -and (`$distros.Count -gt 1)) {

    `$distro = Show-RadioSelectorDialog -Options `$distros -Title "Select WSL Distribution" -Preselect `$distro
    if (-not `$distro) { exit 1 }
}

# Convert Windows path to WSL path
`$wslPath = Invoke-WSL -Distro `$distro -Arguments @('wslpath', (`$Path | Quote-String)) 

# Open VS Code with remoting into WSL
& code --remote "wsl+`$distro" "`$wslPath"

# Export all locally install extsions
code --list-extensions | Where-Object { -not [string]::IsNullOrWhiteSpace("`$_") } | ForEach-Object {
    Write-Host "Installing extension '`$_' into WSL distro '`$distro'"
    Invoke-WSL -Distro `$distro -Arguments @('--', 'bash', '-c', ("code --install-extension `$_ --force" | Quote-String -UseSingleQuotes)) -NoWait
}

"@ | Set-Content -Path $utilsScriptPath -Force

@"
Set objShell = CreateObject("WScript.Shell")
Set objArgs = WScript.Arguments
If objArgs.Count > 0 Then
    targetPath = objArgs(0)
    objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$utilsScriptPath"" """ & targetPath & """ -Default", 0, False
End If
"@ | Set-Content -Path $utilsHiddenPath -Force

foreach ($menuItem in $menuItems) {
    
    foreach ($entry in $menuItem.Keys) {

        $menuPath = $entry.Path
        $argToken = $entry.Arg
        $commandPath = "$menuPath\command"

        # Create shell and command keys
        New-Item -Path $menuPath -Force | Out-Null
        New-Item -Path $commandPath -Force | Out-Null

        # Set icon if valid
        if (Test-Path $codePath -PathType Leaf) {
            Set-ItemProperty -Path $menuPath -Name "Icon" -Value "$codePath,0"
        } else {
            Remove-ItemProperty -Path $menuPath -Name "Icon" -Force -ErrorAction SilentlyContinue
        }

        # Build command with -Default switch if needed
        if ($menuItem.UseDefault) {
            $command = "wscript.exe `"$utilsHiddenPath`" `"$argToken`""
        } else {
            $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$utilsScriptPath`" `"$argToken`""
        }
        
        Set-ItemProperty -Path $commandPath -Name "(default)" -Value $command       
    }
}