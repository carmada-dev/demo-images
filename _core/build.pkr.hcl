packer {
  required_plugins {

    # https://github.com/hashicorp/packer-plugin-azure
    azure = {
      version = "1.4.2"
      source  = "github.com/hashicorp/azure"
    }

    # https://github.com/rgl/packer-plugin-windows-update
    windows-update = {
      version = "0.14.1"
      source  = "github.com/rgl/windows-update"
    }
  }
}

source "azure-arm" "vm" {

  # general settings
  skip_create_image                   = false
  async_resourcegroup_delete          = true
  secure_boot_enabled                 = true
  use_azure_cli_auth                  = true
  vm_size                             = "Standard_D8d_v4" 

  # winrm options
  communicator                        = "winrm"
  winrm_username                      = "packer"
  winrm_insecure                      = true
  winrm_use_ssl                       = true

  # os settings
  os_type                             = "Windows"
  os_disk_size_gb                     = 1024
  
  # base image options (Azure Marketplace Images only)
  image_publisher                     = local.image.base.publisher
  image_offer                         = local.image.base.offer
  image_sku                           = local.image.base.sku
  image_version                       = local.image.base.version

  # temporary resource location
  subscription_id                     = local.factory.subscription
  location                            = local.factory.location
  temp_resource_group_name            = "PKR-${upper(local.variables.imageName)}-${upper(local.variables.imageVersion)}${upper(local.variables.imageSuffix)}"

  # publish image to gallery
  shared_image_gallery_destination {
    subscription                      = local.gallery.subscription
    gallery_name                      = local.gallery.name
    resource_group                    = local.gallery.resourceGroup
    image_name                        = local.variables.imageName
    image_version                     = local.variables.imageVersion
    replication_regions               = local.image.regions
    storage_account_type              = "Premium_LRS" # default is Standard_LRS
  }

  # new image version are excluded from latest to support staging
  shared_gallery_image_version_exclude_from_latest = true
}

build {

  sources = ["source.azure-arm.vm"]

  # =============================================================================================
  # Initialize VM 
  # =============================================================================================

  provisioner "powershell" {
    environment_vars = setunion(local.default.environmentVariables, [
      "ADMIN_USERNAME=${build.User}",
      "ADMIN_PASSWORD=${build.Password}"
    ])
    script = "${path.root}/../_scripts/core/Prepare-VM.ps1"
  }

  provisioner "windows-restart" {
    # force restart 
    restart_timeout = "30m"
  }

  # =============================================================================================
  # Upload Artifacts
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [ "New-Item -ItemType Directory -Force -Path '${local.path.devboxHome}/Artifacts' | Out-Null" ]
  }

  provisioner "file" {
    source = "${path.root}/../_artifacts/"
    destination = "${local.path.devboxHome}/Artifacts/"
  }

  # =============================================================================================
  # Install Package Managers 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.default.environmentVariables
    scripts = setunion(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      fileset("${path.root}", "../_scripts/pkgs/*.ps1")
    ) 
  }

  provisioner "windows-restart" {
    check_registry = true
    restart_timeout = "30m"
  }
  
  # =============================================================================================
  # PRE Package Section 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.default.environmentVariables
    scripts = setunion(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      local.prePackageScripts
    )
  }

  provisioner "windows-restart" {
    check_registry = true
    restart_timeout = "30m"
  }

  # =============================================================================================
  # Install Image Packages 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.default.environmentVariables
    inline = [templatefile("${path.root}/../_templates/InstallPackages.pkrtpl.hcl", { packages = [ for p in local.resolved.packages: p if try(p.scope == "machine", false) ] })]
  }

  provisioner "windows-restart" {
    check_registry = true
    restart_timeout = "30m"
  }

  # =============================================================================================
  # POST Package Section 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.default.environmentVariables
    scripts = concat(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      local.postPackageScripts
    )
  }

  provisioner "windows-restart" {
    check_registry = true
    restart_timeout = "30m"
  }

  # =============================================================================================
  # PATCH Script Section 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.default.environmentVariables
    scripts = setunion(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      fileset("${path.root}", "../_scripts/patch/*.ps1")
    ) 
  }

  provisioner "windows-restart" {
    check_registry = true
    restart_timeout = "30m"
  }

  # =============================================================================================
  # Installing Windows Updates 
  # =============================================================================================

  provisioner "windows-update" {
    # https://github.com/rgl/packer-plugin-windows-update
  }

  provisioner "windows-restart" {
    check_registry = true
    restart_timeout = "30m"
  }

  # =============================================================================================
  # Prepare Active Setup 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [ "New-Item -ItemType Directory -Force -Path '${local.path.devboxHome}/ActiveSetup' | Out-Null" ]
  }

  provisioner "file" {
    sources = fileset("${path.root}", "../_scripts/pkgs/*.ps1")
    destination = "${local.path.devboxHome}/ActiveSetup/"
  }

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [ templatefile("${path.root}/../_templates/RegisterScripts.pkrtpl.hcl", { prefix = "", scripts = [ for f in fileset("${path.root}", "../_scripts/pkgs/*.ps1"): "${local.path.devboxHome}/ActiveSetup/${basename(f)}" ] }) ]
  }

  provisioner "file" {
    content = templatefile("${path.root}/../_templates/InstallPackages.pkrtpl.hcl", { packages = [ for p in local.resolved.packages: p if try(p.scope == "user", false) ] }) 
    destination = "${local.path.devboxHome}/ActiveSetup/Install-Packages.ps1"
  }

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [ templatefile("${path.root}/../_templates/RegisterScripts.pkrtpl.hcl", { prefix = ">", scripts = [ "${local.path.devboxHome}/ActiveSetup/Install-Packages.ps1" ] }) ]
  }

  # =============================================================================================
  # Finalize Image by generalizing VM
  # =============================================================================================

  provisioner "powershell" {
	  elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.default.environmentVariables
    timeout = "1h"
    script  = "${path.root}/../_scripts/core/Generalize-VM.ps1"
  }

  # =============================================================================================
  # On Error - Collect information from remote system
  # =============================================================================================

  error-cleanup-provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.default.environmentVariables
    scripts = setunion(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      fileset("${path.root}", "../_scripts/error/*.ps1")
    ) 
  }
}
