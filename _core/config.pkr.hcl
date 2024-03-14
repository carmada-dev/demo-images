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
		# This section wraps the variables defined in the config file to ensure each of them has a acceptable value.
		# Whenever you make changes to the Packer files in this repo, you should always reference these locals and
		# never the original variables defined in the top of this file!
		imageName = "${length(trimspace(var.imageName)) == 0 ? basename(abspath(path.root)) : var.imageName}"
		imageSuffix = "${length(trimspace(var.imageSuffix)) == 0 ? "" : "-${var.imageSuffix}"}"
		imageVersion = "${length(trimspace(var.imageVersion)) == 0 ? formatdate("YYYY.MMDD.hhmm", timestamp()) : var.imageVersion}"
	}

	factory = {
		# The ID of the Azure subscription that should be used as the image factory.
		subscription = "f9fcf631-fa8d-4ea2-8298-61b43220a3d1"
		# The Azure region that should be used to create factory (temporary) resources.
		location = "${try(local.image.regions[0], "West Europe")}"
		# User definied managed identities that should be assigned to temp VMs (resource id)
		identities = [
			"/subscriptions/bffe1654-7f9a-4630-b7b9-d24759a76222/resourceGroups/BLD-Carmada/providers/Microsoft.ManagedIdentity/userAssignedIdentities/Carmada"
		]
	}

	update = {
		# Configuration values for Windows Update -> more https://github.com/rgl/packer-plugin-windows-update
		
		# Important
		# ----------------------------------------------
		# search = "AutoSelectOnWebSites=1 and IsInstalled=0" 
		# filters = [
		# 	"exclude:$_.Title -like '*Preview*'",
		# 	"include:$true"
		# ]

		# Recommended
		# ----------------------------------------------
		# search = "BrowseOnly=0 and IsInstalled=0" 
		# filters = [
		# 	"exclude:$_.Title -like '*Preview*'",
		# 	"include:$true"
		# ]

		# All Updates
		# ----------------------------------------------
		# search = "BrowseOnly=0 and IsInstalled=0" 
		# filters = [
		# 	"exclude:$_.Title -like '*Preview*'",
		# 	"include:$true"
		# ]

		# None Updates
		# ----------------------------------------------
		search = "BrowseOnly=0 and IsInstalled=0" 
		filters = [
			"exclude:$true",
			"include:$false"
		]
	}

	path = {
		# The folder that is created in each image to persist DevBox scripts and other artifacts.
		devboxHome = "C:\\DevBox"
	}

  	default = {	
		
		# A set of environment variables that will be set on the temporary VM each time a provisioning script
		# is remotely executed. If an environment variable starts with DEVBOX_ the variable is persisted on
		# the machine level and will make it into the image!
		environmentVariables = [ 
			"DEVBOX_HOME=${local.path.devboxHome}",
			"DEVBOX_IMAGENAME=${local.variables.imageName}",
			"DEVBOX_IMAGEVERSION=${local.variables.imageVersion}"
		]

		# A set of Windows Optional Features enabled on all images.
		features = [

		]

		# A set of scripts always executed during the image prepare phase.
		prepare = [
			"${path.root}/../_scripts/Install-BGInfo.ps1"
		]

		# A set of scripts always executed during the image configure phase.
		configure = [
			"${path.root}/../_scripts/Configure-VisualStudio.ps1",
			"${path.root}/../_scripts/Configure-VisualStudioCode.ps1"
		]

		# This array contains packages that should be installed on each image based this configuration. The package
		# definition is equal to the package definition used in the image definiton file. So it's easy to move those
		# packages definitions around.
		packages = [

			# {
			# 	name = ""						< MANDATORY
			#  	scope = "[machine|user|all]"	< MANDATORY (OPTIONAL if source == 'alias')
			# 	version = ""					< DEFAULT: latest 
			# 	source = ""						< DEFAULT: winget [ winget, msstore, alias ]
			# 	options = []					< DEFAULT: [] >> array of strings used as additional package manager arguments
			# 	override = []					< DEFAULT: [] >> array of strings used to override installer arguments
			#	exitCodes = []					< DEFAULT: [] >> array of numbers that should be treated like success exit codes
			#   features = []					< DEFAULT: [] >> array of optional windows features required by this package
			#	prepare = []					< DEFAULT: [] >> array of prepare scripts to run before the package is installed
			#	configure = []					< DEFAULT: [] >> array of configuration scripts to run after the package was installed
  			# }

			{
				name = "Microsoft.PowerShell"
				scope = "machine"
			},

			{
				name = "git"
				source = "alias"
			},

			{
				# this package is a dependency of the Microsoft.DevHome
				# package and must be installed in machine scope
				name = "Microsoft.WindowsAppRuntime.1.4"		
			 	scope = "machine"
			},

			{
				# https://github.com/microsoft/devhome
				name = "Microsoft.DevHome"		
			 	scope = "user"
				options = [
					# dependencies must be installed in the machine scope during
					# image building as permission elevation (admin) is required 
					"--skip-dependencies"
				]
			},

			{
				# https://github.com/microsoft/vswhere
				name = "Microsoft.VisualStudio.Locator"
				scope = "all"
			},

			{
				# https://github.com/microsoft/terminal
				name = "Microsoft.WindowsTerminal"		
			 	scope = "user"
			}			

		]

		# A map of package aliases to simplify package installation when you need to override installer arguments!
		# To reference a package alias in you image definition just add a package definition with the alias defined 
		# here as name and 'alias' as source.
		packageAlias = {

			git = {
				name = "Git.Git"
				scope = "machine"
				override = [
					"/VERYSILENT",
					"/SUPPRESSMSGBOXES",
					"/NORESTART",
					"/NOCANCEL",
					"/SP-",
					"/WindowsTerminal",
					"/WindowsTerminalProfile",
					"/DefaultBranchName:main",
					"/Editor:VisualStudioCode"
				]
				configure = [
					"${path.root}/../_scripts/Configure-Git.ps1"
				]
			}

			vscode = {
				name = "Microsoft.VisualStudioCode"
				scope = "machine"
				override = [
					"/VERYSILENT",
					"/NORESTART",
					"/MERGETASKS=desktopicon,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath,!runcode"
				]
			}

			dockerDesktopWSL = {
				name = "Docker.DockerDesktop"
				scope = "machine"
				override = [
					"install",
					"--quiet",
					"--accept-license",
					"--backend=wsl-2",
					"--always-run-service"
				]
				features = [
					"Microsoft-Windows-Subsystem-Linux",
					"VirtualMachinePlatform",
					"Containers"
				]
				prepare = [
					"${path.root}/../_scripts/Install-WSL2.ps1"
				]
				configure = [
					"${path.root}/../_scripts/Configure-DockerDesktop.ps1"
				]
			}

			dockerDesktopHyperV = {
				name = "Docker.DockerDesktop"
				scope = "machine"
				override = [
					"install",
					"--quiet",
					"--accept-license",
					"--backend=hyper-v",
					"--always-run-service"
				]
				features = [
					"Microsoft-Windows-Subsystem-Linux",
					"VirtualMachinePlatform",
					"Containers",
					"Microsoft-Hyper-V-All"
				]
				prepare = [
					"${path.root}/../_scripts/Install-WSL2.ps1"
				]
				configure = [
					"${path.root}/../_scripts/Configure-DockerDesktop.ps1"
				]
			}
		}
	}

	# This section provides simplified access to some calculated values. This way it
	# becomes easier to document heavier calculations and aggregations, but also reduces
	# complexity in the image build definition.
	resolved = {

		# Get a list of all packages to install. This includes packages definied in the image definition, 
		# but also those form the main configuration. Furthermore; alias packages are resolved and replaced
		# by their real definition.
		packages = concat(
			[ for p in concat(local.default.packages, local.packages): p if try(p.source != "alias", true) ], 
			[ for p in concat(local.default.packages, local.packages): lookup(local.default.packageAlias, p.name, p) if try(p.source == "alias", false) ]
		)

		# Get a list of all features to enable. This includes features definied in the default configuration, 
		# the image definition, and all resolved packages.
		features = distinct(concat(
			try(local.default.features, []),
			try(local.devDrive.sizeGB, 0) == 0 ? [] : ["Microsoft-Hyper-V-All"],
			flatten([ for p in concat(
				[ for p in concat(local.default.packages, local.packages): p if try(p.source != "alias", true) ], 
				[ for p in concat(local.default.packages, local.packages): lookup(local.default.packageAlias, p.name, p) if try(p.source == "alias", false) ]
			): try(p.features, []) ]),
			try(local.features, [])
		))

		# Get a list of all prepare scripts to apply. This includes prepare scripts definied in the 
		# default configuration, the image definition, and all resolved packages.
		prepare = distinct(concat(
			["${path.root}/../_scripts/core/NOOP.ps1"],
			try(local.default.prepare, []),
			flatten([ for p in concat(
				[ for p in concat(local.default.packages, local.packages): p if try(p.source != "alias", true) ], 
				[ for p in concat(local.default.packages, local.packages): lookup(local.default.packageAlias, p.name, p) if try(p.source == "alias", false) ]
			): try(p.prepare, []) ]),
			try(local.prepare, [])
		))

		# Get a list of all configure scripts to apply. This includes configure scripts definied in the 
		# default configuration, the image definition, and all resolved packages.
		configure = distinct(concat(
			["${path.root}/../_scripts/core/NOOP.ps1"],
			try(local.default.configure, []),
			flatten([ for p in concat(
				[ for p in concat(local.default.packages, local.packages): p if try(p.source != "alias", true) ], 
				[ for p in concat(local.default.packages, local.packages): lookup(local.default.packageAlias, p.name, p) if try(p.source == "alias", false) ]
			): try(p.configure, []) ]),
			try(local.configure, [])
		))
	}
}