
locals {

    image = {

	  	name = "${var.imageName}"
  		version = "${var.imageVersion}"
		regions = [ "West Europe" ]

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-datascience-devbox"

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
			name = "Microsoft.VisualStudioCode"
			scope = "machine"
			override = [
				"/VERYSILENT",
				"/NORESTART",
				"/MERGETASKS=desktopicon,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath,!runcode"
			]
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

    postPackageScripts = [
    ]

}
