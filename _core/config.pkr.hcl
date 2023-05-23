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
			"PACKER=true",
			"DEVBOX_HOME=${local.path.devboxHome}",
			"DEVBOX_IMAGENAME=${local.variables.imageName}",
			"DEVBOX_IMAGEVERSION=${local.variables.imageVersion}"
		]
	}

	factory = {
		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		location = "${try(local.image.regions[0], "West Europe")}"
	}
}