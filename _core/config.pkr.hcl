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

		# This array contains packages that should be installed on each image based this configuration. The package
		# definition is equal to the package definition used in the image definiton file. So it's easy to move those
		# packages definitions around.
		packages = [

			# {
			# 	name = ""					< MANDATORY
			#  	scope = "[machine|user]" 	< MANDATORY (OPTIONAL if source == 'alias')
			# 	version = ""				< DEFAULT: latest 
			# 	source = ""					< DEFAULT: winget [ winget, msstore, alias ]
			# 	override = []				< DEFAULT: [] >> array of strings used to override installer arguments
			#	exitCodes = []				< DEFAULT: [] >> array of numbers that should be treated like success exit codes
			# }

			{
				#https://github.com/microsoft/devhome
				name = "Microsoft.DevHome"		
			 	scope = "user"
				source = "winget"
			},

			{
				#https://github.com/microsoft/terminal
				name = "Microsoft.WindowsTerminal"		
			 	scope = "user"
				source = "winget"
			},
			
			{
				#https://www.marticliment.com/wingetui/
				name = "SomePythonThings.WingetUIStore"		
			 	scope = "user"
			},

			{
				name = "Microsoft.PowerShell"
				scope = "machine"
			}
		]

		# A map of package aliases to simplify package installation when you need to override installer arguments!
		# To reference a package alias in you image definition just add a package definition with the alias defined 
		# here as name and 'alias' as the source.
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

			dockerDesktop = {
				name = "Docker.DockerDesktop"
				scope = "machine"
				override = [
					"install",
					"--quiet",
					"--accept-license"
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
	}
}