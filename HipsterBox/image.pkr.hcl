
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-hipster-devbox"
		regions = [ "West Europe" ]

		base = {

			# publisher = "MicrosoftWindowsDesktop"
			# offer = "windows-ent-cpc"
			# sku = "win11-22h2-ent-cpc-os"
			# version = "latest"

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
		sizeGB = 250
		repositories = [
			{
				repoUrl = "https://github.com/kubernetes/kubernetes.git"
			},
			{
				repoUrl = "https://github.com/dotnet-architecture/eShopOnWeb.git"
			},
			{
				repoUrl = "https://github.com/markusheiliger/courier.git"
				tokenUrl = "https://carmada.vault.azure.net/secrets/GitHub/"
			}
		]
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
		# 	name = "dockerDesktopWSL"
		# 	source = "alias"
		# },

		# {
		# 	name = "Microsoft.AzureCLI"
		# 	scope = "machine"
		# },

		{
			name = "Postman.Postman"
			scope = "user"
		}
		
		# {
		# 	name ="Google.Chrome"
		# 	scope = "machine"
		# },
		# {
		# 	name = "Mozilla.Firefox"
		# 	scope = "machine"
		# },

		# {
		# 	name = "Wiesemann-Theis.USB-Redirector"
		# 	scope = "machine"
		# }
    ]

    configure = [

    ]

}
