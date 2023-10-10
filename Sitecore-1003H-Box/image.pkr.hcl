
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-sitecore-1003-devbox"
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

    prePackageScripts = [
	    "${path.root}/../_scripts/Install-WSL2.ps1"
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
		
		{
			name = "Microsoft.SQLServer.2019.Developer"
			scope = "machine"
		},
		{		
			name = "Microsoft.CLRTypesSQLServer.2019"
			scope = "machine"
		},
		{
			name = "Microsoft.SQLServerManagementStudio"
			scope = "machine"
		},

		# {
		# 	name = "dockerDesktop"
		# 	source = "alias"
		# },

		# {
		# 	name = "Microsoft.Bicep"
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
		# "${path.root}/../_scripts/Install-SitecoreVSIX.ps1",
		# "${path.root}/../_scripts/Install-SitecoreXP0-1003.ps1"
    ]

}
