
locals {

    image = {

	  	name = "${var.imageName}"
  		version = "${var.imageVersion}"
		regions = [ "West Europe" ]

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-hipster-devbox"

		base = {

			publisher = "MicrosoftWindowsDesktop"
			offer = "windows-ent-cpc"
			sku = "win11-22h2-ent-cpc-os"
			version = "latest"
		}
    }

	gallery = {

		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		resourceGroup = "ORG-CarmadaRnD"
		name = "CarmadaRnD"
	}

    prePackageScripts = [
	    "${path.root}/../_scripts/Install-WSL2.ps1"
    ]

    packages = [

		# {
		# 	name = ""					< MANDATORY
		#  	scope = "[machine|user]" 	< MANDATORY
		# 	version = ""				< DFAULT: latest
		# 	source = ""					< DFAULT: winget
		# 	override = []
		# }

		{
			name = "Microsoft.PowerShell"
			scope = "machine"
		},

		{
			name = "Microsoft.VisualStudioCode"
			scope = "machine"
			override = [
				"/VERYSILENT",
				"/NORESTART",
				"/MERGETASKS=desktopicon,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath,!runcode"
			]
		},

		{
			name = "Git.Git"
			scope = "machine"
			override = [
				"/VERYSILENT",
				"/SUPPRESSMSGBOXES",
				"/NORESTART",
				"/NOCANCEL",
				"/SP-",
				"/WindowsTerminal",
				"/WindowsTerminalProfile",
				"/DefaultBranchName:main",
				"/Editor:VisualStudioCode"
			]
		},
		{
			name = "GitHub.cli"
			scope = "machine"
		},
		{
			name = "GitHub.GitHubDesktop"
			scope = "machine"
		},
		
		{
			name = "Docker.DockerDesktop"
			scope = "machine"
			override = [
				"install",
				"--quiet",
				"--accept-license"
			]
		},

		{
			name = "Microsoft.AzureCLI"
			scope = "machine"
		},

		{
			name = "Postman.Postman"
			scope = "user"
		},
		{
			name ="Google.Chrome"
			scope = "machine"
		},
		{
			name = "Mozilla.Firefox"
			scope = "machine"
		}
    ]

    postPackageScripts = [
    ]

}
