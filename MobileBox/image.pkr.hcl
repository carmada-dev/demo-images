
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-mobile-devbox"
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
		compute = "general_i_8c32gb1024ssd_v2"
	}

	devDrive = {
		sizeGB = 0
	}

	features = [

	]

    prepare = [
	    "${path.root}/../_scripts/Install-WSL2.ps1"
    ]

    packages = [

		# Please check out the package definition described
		# in the config.pkr.hcl file if you want to add new
		# packages to the image definition.

		{
			name = "vscode"
			source = "alias"
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
			name = "git"
			source = "alias"
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
			name = "dockerDesktopWSL"
			source = "alias"
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

    configure = [
		"${path.root}/../_scripts/Install-FabulaTechUSBServer.ps1"
    ]

}
