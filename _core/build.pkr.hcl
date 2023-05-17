packer {
  required_plugins {
    # https://github.com/rgl/packer-plugin-windows-update
    windows-update = {
      version = "0.14.1"
      source  = "github.com/rgl/windows-update"
    }
  }
}

locals {
  defaultEnvironmentVariables = [ "PACKER=true" ]
}

source "azure-arm" "vm" {

  skip_create_image                   = false
  async_resourcegroup_delete          = true
  secure_boot_enabled                 = true
  vm_size                             = "Standard_D8d_v4" # default is Standard_A1

  # winrm options
  communicator                        = "winrm"
  winrm_username                      = "packer"
  winrm_insecure                      = true
  winrm_use_ssl                       = true
  os_type                             = "Windows"
  os_disk_size_gb                     = 1024
  
  # base image options (Azure Marketplace Images only)
  image_publisher                     = local.image.base.publisher
  image_offer                         = local.image.base.offer
  image_sku                           = local.image.base.sku
  image_version                       = local.image.base.version
  use_azure_cli_auth                  = true

  # packer creates a temporary resource group
  subscription_id                     = local.factory.subscription
  location                            = local.factory.location
  temp_resource_group_name            = "PKR-${local.image.name}-${local.image.version}"

  # publish image to gallery
  shared_image_gallery_destination {
    subscription                      = local.gallery.subscription
    gallery_name                      = local.gallery.name
    resource_group                    = local.gallery.resourceGroup
    image_name                        = local.image.name
    image_version                     = local.image.version
    replication_regions               = local.image.regions
    storage_account_type              = "Premium_LRS" # default is Standard_LRS
  }
}

build {

  sources = ["source.azure-arm.vm"]

  # =============================================================================================
  # Ensure Gallery Image Definition  
  # =============================================================================================

  provisioner "shell-local" {
    command = "az sig image-definition create --subscription ${local.gallery.subscription} --resource-group ${local.gallery.resourceGroup} --gallery-name ${local.gallery.name} --gallery-image-definition ${local.image.name} --publisher ${local.image.publisher} --offer ${local.image.offer} --sku ${local.image.sku} --os-type Windows --os-state Generalized --hyper-v-generation V2 --features 'SecurityType=TrustedLaunch' --only-show-errors; exit 0"
  }

  # =============================================================================================
  # Initialize VM 
  # =============================================================================================

  provisioner "powershell" {
    environment_vars = setunion(local.defaultEnvironmentVariables, [
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
  # PRE Package Section 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.defaultEnvironmentVariables
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
  # Install Package Managers 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.defaultEnvironmentVariables
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
  # Install Image Packages 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.defaultEnvironmentVariables
    inline = [templatefile("${path.root}/../_templates/InstallPackages.pkrtpl.hcl", { packages = [ for p in local.packages: p if try(p.scope == "machine", false) ] })]
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
    environment_vars = local.defaultEnvironmentVariables
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
    environment_vars = local.defaultEnvironmentVariables
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
    environment_vars  = local.defaultEnvironmentVariables
    inline            = [ "New-Item -ItemType Directory -Force -Path '${ local.activeSetup.directory }' | Out-Null" ]
  }

  provisioner "file" {
    sources = fileset("${path.root}", "../_scripts/pkgs/*.ps1")
    destination = local.activeSetup.directory
  }

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.defaultEnvironmentVariables
    inline            = [ templatefile("${path.root}/../_templates/RegisterScripts.pkrtpl.hcl", { prefix = "", scripts = [ for f in fileset("${path.root}", "../_scripts/pkgs/*.ps1"): "${local.activeSetup.directory}${basename(f)}" ] }) ]
  }

  provisioner "file" {
    content = templatefile("${path.root}/../_templates/InstallPackages.pkrtpl.hcl", { packages = [ for p in local.packages: p if try(p.scope == "user", false) ] }) 
    destination = "${ local.activeSetup.directory }/Install-Packages.ps1"
  }

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.defaultEnvironmentVariables
    inline            = [ templatefile("${path.root}/../_templates/RegisterScripts.pkrtpl.hcl", { prefix = ">", scripts = [ "${local.activeSetup.directory}Install-Packages.ps1" ] }) ]
  }

  # =============================================================================================
  # Finalize Image by generalizing VM
  # =============================================================================================

  provisioner "powershell" {
	  elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.defaultEnvironmentVariables
    timeout = "1h"
    script  = "${path.root}/../_scripts/core/Generalize-VM.ps1"
  }

  # =============================================================================================
  # On Error - Collect information from remote system
  # =============================================================================================

  error-cleanup-provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars = local.defaultEnvironmentVariables
    scripts = setunion(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      fileset("${path.root}", "../_scripts/error/*.ps1")
    ) 
  }
}
