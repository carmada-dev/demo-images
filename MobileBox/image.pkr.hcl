
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-mobile-devbox"
		regions = [ "West Europe" ]

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
	
	devCenter = {

		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		resourceGroup = "ORG-CarmadaRnD"
		name = "CarmadaRnD"

		storage = "ssd_1024gb"
		compute = "general_a_8c32gb_v1"
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
			name = "Microsoft.VisualStudio.2022.Enterprise"
			scope = "machine"
			override = [
				# https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-enterprise
				"--add", "Microsoft.VisualStudio.Workload.CoreEditor", 
				"--add", "Microsoft.VisualStudio.Workload.NetCrossPlat",
				"--includeRecommended",
				"--includeOptional",
				"--installWhileDownloading",
				"--quiet",
				"--norestart",
				"--force",
				"--wait",
				"--nocache"
			]
		},
		{
			name = "Google.AndroidStudio"
			scope = "machine"
		},
		{
			name = "Wondershare.MirrorGo"
			scope = "machine"
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
		},

		{
			name = "Microsoft.Bicep"
			scope = "machine"
		},
		{
			name = "Microsoft.AzureCLI"
			scope = "machine"
		},
		{
			name = "Microsoft.Azure.StorageExplorer"
			scope = "machine"
		},

		{
			name = "Google.Chrome"
			scope = "machine"
		},
		{
			name = "Mozilla.Firefox"
			scope = "machine"
		}
    ]

    postPackageScripts = [
		"${path.root}/../_scripts/Install-FabulaTechUSBServer.ps1"
    ]

}
