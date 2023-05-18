variable "imageName" {
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
		imageVersion = "${length(trimspace(var.imageVersion)) == 0 ? formatdate("YYYY.MMDD.hhmm", timestamp()) : var.imageVersion}"
	}

  	default = {
		environmentVariables = [ "PACKER=true" ]
	}

	factory = {
		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		location = "${try(local.image.regions[0], "West Europe")}"
	}

	activeSetup = {
		directory = "c:/DevBox/"
	}

}