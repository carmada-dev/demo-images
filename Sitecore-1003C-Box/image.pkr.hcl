
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-sitecore-1003C-devbox"
		regions = [ "West Europe" ]

		base = {

			publisher = "MicrosoftVisualStudio"
			offer = "windowsplustools"
			sku = "base-win11-gen2"
			version = "latest"
		}
    }

	gallery = {

		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		resourceGroup = "ORG-CarmadaRnD"
		name = "CarmadaRnD"
	}

	archive = {

		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		resourceGroup = "ORG-CarmadaRnD"
		name = "" # auto create archive storage account
	}
		
	devCenter = {

		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		resourceGroup = "ORG-CarmadaRnD"
		name = "CarmadaRnD"

		storage = "ssd_1024gb"
		compute = "general_i_16c64gb1024ssd_v2"
	}

	devDrive = {
		sizeGB = 0
	}

	features = [

	]

    prepare = [
	    # "${path.root}/../_scripts/Install-WSL2.ps1",
	    # "${path.root}/../_scripts/Install-HyperV.ps1"
    ]

    packages = [

		# Please check out the package definition described
		# in the config.pkr.hcl file if you want to add new
		# packages to the image definition.

		# {
		# 	name = "Microsoft.DotNet.SDK.3_1"
		# 	scope = "machine"
		# },
		# {
		# 	name = "Microsoft.DotNet.SDK.5"
		# 	scope = "machine"
		# },
		# {
		# 	name = "Microsoft.DotNet.SDK.6"
		# 	scope = "machine"
		# },
		# {
		# 	name = "Microsoft.DotNet.SDK.7"
		# 	scope = "machine"
		# },

		{
			name = "dockerDesktopHyperV"
			source = "alias"
		},

		{
			name = "RedHat.Podman"
			scope = "machine"
		},		
		{
			name = "RedHat.Podman-Desktop"
			scope = "machine"
		}

		# {
		# 	name = "git"
		# 	source = "alias"
		# },
		# {
		# 	name = "GitHub.cli"
		# 	scope = "machine"
		# },
		# {
		# 	name = "GitHub.GitHubDesktop"
		# 	scope = "machine"
		# },

		# {
		# 	name = "vscode"
		# 	source = "alias"
		# },
		# {
		# 	name = "Microsoft.VisualStudio.2022.Enterprise"
		# 	scope = "machine"
		# 	override = [
		# 		# https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-enterprise
		# 		"--add", "Microsoft.VisualStudio.Workload.CoreEditor", 
		# 		"--add", "Microsoft.VisualStudio.Workload.Azure", 
		# 		"--add", "Microsoft.VisualStudio.Workload.NetCrossPlat",
		# 		"--add", "Microsoft.VisualStudio.Workload.NetWeb",
		# 		"--add", "Microsoft.VisualStudio.Workload.Node", 
		# 		"--add", "Microsoft.VisualStudio.Workload.Python",
		# 		"--add", "Microsoft.VisualStudio.Workload.ManagedDesktop", 
		# 		"--includeRecommended",
		# 		"--installWhileDownloading",
		# 		"--quiet",
		# 		"--norestart",
		# 		"--force",
		# 		"--wait",
		# 		"--nocache"
		# 	]
		# },
		# {
		# 	name = "Microsoft.SQLServerManagementStudio"
		# 	scope = "machine"
		# },


		# {
		# 	name = "Microsoft.AzureCLI"
		# 	scope = "machine"
		# },
		# {
		# 	name = "Microsoft.Azure.StorageExplorer"
		# 	scope = "machine"
		# },
		# {
		# 	name = "Microsoft.AzureDataStudio"
		# 	scope = "machine"
		# },

		# {
		# 	name ="Google.Chrome"
		# 	scope = "machine"
		# },
		# {
		# 	name = "Mozilla.Firefox"
		# 	scope = "machine"
		# }

    ]

    configure = [
		"${path.root}/../_scripts/Install-SitecoreXP0-1003C.ps1"
    ]

}
