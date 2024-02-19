
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-datascience-devbox"
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

    ]

    packages = [

		# Please check out the package definition described
		# in the config.pkr.hcl file if you want to add new
		# packages to the image definition.

		{
			name = "Microsoft.VisualStudio.2022.Community"
			scope = "machine"
			override = [
				# https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-community
				"--add", "Microsoft.VisualStudio.Workload.CoreEditor", 
				"--add", "Microsoft.VisualStudio.Workload.Azure", 
				"--add", "Microsoft.VisualStudio.Workload.Data",
				"--add", "Microsoft.VisualStudio.Workload.DataScience",
				"--add", "Microsoft.VisualStudio.Workload.ManagedDesktop", 
				"--add", "Microsoft.VisualStudio.Workload.Node", 
				"--add", "Microsoft.VisualStudio.Workload.Python",
				"--includeRecommended",
				"--installWhileDownloading",
				"--quiet",
				"--norestart",
				"--force",
				"--wait",
				"--nocache"
			]
		},

		{
			name = "vscode"
			source = "alias"
		},

		{
			name = "JetBrains.PyCharm.Community"
			scope = "machine"
		},
		{
			name = "Microsoft.AzureDataStudio"
			scope = "machine"
		}


    ]

    configure = [
    ]

}
