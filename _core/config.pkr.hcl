variable "imageName" {
	type =  string
	default = ""
}

variable "imageSuffix" {
	type =  string
	default = ""
}

variable "imageVersion" {
	type =  string
	default = ""
}

locals {

	variables = {
		imageName = "${length(trimspace(var.imageName)) == 0 ? basename(abspath(path.root)) : var.imageName}"
		imageSuffix = "${length(trimspace(var.imageSuffix)) == 0 ? "" : "-${var.imageSuffix}"}"
		imageVersion = "${length(trimspace(var.imageVersion)) == 0 ? formatdate("YYYY.MMDD.hhmm", timestamp()) : var.imageVersion}"
	}

	path = {
		devboxHome = "C:\\DevBox"
	}

  	default = {	
		
		environmentVariables = [ 
			"DEVBOX_HOME=${local.path.devboxHome}",
			"DEVBOX_IMAGENAME=${local.variables.imageName}",
			"DEVBOX_IMAGEVERSION=${local.variables.imageVersion}"
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
				#https://apps.microsoft.com/store/detail/dev-home-preview/9N8MHTPHNGVV
				name = "9N8MHTPHNGVV"		
			 	scope = "user"
				source = "msstore"
			},
			{
				#https://www.marticliment.com/wingetui/
				name = "SomePythonThings.WingetUIStore"		
			 	scope = "machine"
			}
		]
	}

	factory = {
		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		location = "${try(local.image.regions[0], "West Europe")}"
	}
}