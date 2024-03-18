
locals {

    image = {

		publisher = "CarmadaRnD"
		offer = "CarmadaDev"
		sku = "win11-dockerdesktop-wsl-devbox"
		regions = [ "West Europe" ]

		base = {

			publisher = "MicrosoftVisualStudio"
			offer = "windowsplustools"
			sku = "base-win11-gen2"
			version = "latest"
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

		]

		packages = [

			# Please check out the package definition described
			# in the config.pkr.hcl file if you want to add new
			# packages to the image definition.

			{
				name = "dockerDesktopWSL"
				source = "alias"
			}

		]

		configure = [

		]
	}
}
