
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-hipster-devbox"
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

		# Please check out the package definition described
		# in the config.pkr.hcl file if you want to add new
		# packages to the image definition.

		{
			name = "vscode"
			source = "alias"
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
			name = "dockerDesktop"
			source = "alias"
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

			# to avoid broken build because of unanounced installer updates by Google
			# we suppress the exit code -1978335215 indicating a install hash mismatch
			exitCodes = [ -1978335215 ] 
		},
		{
			name = "Mozilla.Firefox"
			scope = "machine"
		}
    ]

    postPackageScripts = [
		"${path.root}/../_scripts/Install-WuTCOMRedirector.ps1",
		"${path.root}/../_scripts/Install-WuTUSBRedirector.ps1"
    ]

}
