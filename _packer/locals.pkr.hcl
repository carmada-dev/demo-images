locals {

	# Load the aliases, default, and factory configuration from the _config folder. 
	aliases = jsondecode(replace(file("${path.root}/../_config/aliases.json"), "[IMAGEROOT]", local.path.imageRoot))
	default = jsondecode(replace(file("${path.root}/../_config/default.json"), "[IMAGEROOT]", local.path.imageRoot))
	factory = jsondecode(replace(file("${path.root}/../_config/factory.json"), "[IMAGEROOT]", local.path.imageRoot))

	# Load the image configuration from the image.json file. This configuration is used to define the image specific configuration.
	image = jsondecode(replace(file(local.variables.imageDefinition), "[IMAGEROOT]", local.path.imageRoot))

	variables = {
		# This section wraps the variables defined in the config file to ensure each of them has a acceptable value.
		# Whenever you make changes to the Packer files in this repo, you should always reference these locals and
		# never the original variables defined in the top of this file!
		imageName = "${length(trimspace(var.imageName)) == 0 ? basename(abspath(path.cwd)) : var.imageName}"
		imageSuffix = "${length(trimspace(var.imageSuffix)) == 0 ? "" : "-${trimprefix(var.imageSuffix, "-")}"}"
		imageVersion = "${length(trimspace(var.imageVersion)) == 0 ? formatdate("YYYY.MMDD.hhmm", timestamp()) : var.imageVersion}"
		imageDefinition = "${abspath(var.imageDefinition)}"
	}

	# Configuration values for Windows Update -> more https://github.com/rgl/packer-plugin-windows-update
	# By default all available updates are installed. You can change this behavior by setting the updates 
	# variable in the image.json file. The following options are available:
	# - none: No updates are installed.
	# - recommended: Only recommended updates are installed.
	# - important: Only important updates are installed.
	update = lookup({
		none = {
			search = "BrowseOnly=0 and IsInstalled=0" 
			filters = [
				"exclude:$true",
				"include:$false"
			]
		}	
		recommended = {
			search = "BrowseOnly=0 and IsInstalled=0" 
			filters = [
				"exclude:$_.Title -like '*Preview*'",
				"include:$true"
			]
		}
		important = {
			search = "AutoSelectOnWebSites=1 and IsInstalled=0" 
			filters = [
				"exclude:$_.Title -like '*Preview*'",
				"include:$true"
			]
		}
	},
	try(local.image.updates, "all"),
	{
		search = "BrowseOnly=0 and IsInstalled=0" 
		filters = [
			"exclude:$_.Title -like '*Preview*'",
			"include:$true"
		]
	})		

	path = {
		# The folder that is created in each image to persist DevBox scripts and other artifacts.
		devboxHome = "C:\\DevBox"
		# The folder that contains the image definition file.
		imageRoot = trimsuffix(dirname(abspath(var.imageDefinition)), "/")
	}

	environment = [ 
		"DEVBOX_HOME=${local.path.devboxHome}",
		"DEVBOX_IMAGENAME=${local.variables.imageName}",
		"DEVBOX_IMAGEVERSION=${local.variables.imageVersion}"
	]

	# This section provides simplified access to some calculated values. This way it
	# becomes easier to document heavier calculations and aggregations, but also reduces
	# complexity in the image build definition.
	resolved = {

		# Get a list of all packages to install. This includes packages definied in the image definition, 
		# but also those form the main configuration. Furthermore; alias packages are resolved and replaced
		# by their real definition.
		packages = flatten(concat(
			[ for p in concat(local.default.packages, local.image.packages): p if try(p.source != "alias", true) ], 
			[ for p in concat(local.default.packages, local.image.packages): lookup(local.aliases, p.name, p) if try(p.source == "alias", false) ]
		))

		# Get a list of all features to enable. This includes features definied in the default configuration, 
		# the image definition, and all resolved packages.
		features = distinct(concat(
			try(local.default.features, []),
			try(local.image.devDrive.sizeGB, 0) == 0 ? [] : ["Microsoft-Hyper-V-All"],
				flatten([ for p in flatten(concat(
					[ for p in concat(local.default.packages, local.image.packages): p if try(p.source != "alias", true) ], 
					[ for p in concat(local.default.packages, local.image.packages): lookup(local.aliases, p.name, p) if try(p.source == "alias", false) ]
				)): try(p.features, []) ]),
			try(local.image.features, [])
		))

		# Get a list of all prepare scripts to apply. This includes prepare scripts definied in the 
		# default configuration, the image definition, and all resolved packages.
		prepare = distinct(concat(
			["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
			try(local.default.prepare, []),
				flatten([ for p in flatten(concat(
					[ for p in concat(local.default.packages, local.image.packages): p if try(p.source != "alias", true) ], 
					[ for p in concat(local.default.packages, local.image.packages): lookup(local.aliases, p.name, p) if try(p.source == "alias", false) ]
				)): try(p.prepare, []) ]),
			try(local.image.prepare, [])
		))

		# Get a list of all configure scripts to apply. This includes configure scripts definied in the 
		# default configuration, the image definition, and all resolved packages.
		configure = distinct(concat(
			["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
			try(local.default.configure, []),
				flatten([ for p in flatten(concat(
					[ for p in concat(local.default.packages, local.image.packages): p if try(p.source != "alias", true) ], 
					[ for p in concat(local.default.packages, local.image.packages): lookup(local.aliases, p.name, p) if try(p.source == "alias", false) ]
				)): try(p.configure, []) ]),
			try(local.image.configure, [])
		))
	}
}