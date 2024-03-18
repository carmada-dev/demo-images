packer {
  required_plugins {

    # https://github.com/hashicorp/packer-plugin-azure
    azure = {
      version = "2.0.2" # "1.4.2"
      source  = "github.com/hashicorp/azure"
    }

    # https://github.com/rgl/packer-plugin-windows-update
    windows-update = {
      version = "0.15.0" # "0.14.1"
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
  vm_size                             = "Standard_D8s_v5"
  #vm_size                             = "Standard_D8d_v4" 
  #vm_size                             = "Standard_D4_v4"
  license_type                        = "Windows_Client"

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
  location                            = local.factory.region
  user_assigned_managed_identities    = local.factory.identities
  temp_resource_group_name            = "PKR-${upper(local.variables.imageName)}-${upper(local.variables.imageVersion)}${upper(local.variables.imageSuffix)}"

  # publish image to gallery
  shared_image_gallery_destination {
    subscription                      = local.image.gallery.subscription
    gallery_name                      = local.image.gallery.name
    resource_group                    = local.image.gallery.resourceGroup
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
  # Upload Artifacts
  # =============================================================================================

  provisioner "file" {
    source            = "${path.root}/../_scripts/modules/"
    destination       = "${local.path.devboxHome}/Modules/"
  }

  provisioner "file" {
    source            = "${path.root}/../_artifacts/"
    destination       = "${local.path.devboxHome}/Artifacts/"
  }

  provisioner "file" {
    source            = "${path.root}/artifacts/"
    destination       = "${local.path.devboxHome}/Artifacts/"
  }

  # =============================================================================================
  # Initialize VM 
  # =============================================================================================

  provisioner "powershell" {
    environment_vars = setunion(local.default.environmentVariables, [
      "ADMIN_USERNAME=${build.User}",
      "ADMIN_PASSWORD=${build.Password}"
    ])
    script            = "${path.root}/../_scripts/core/Initialize-VM.ps1"
  }

  provisioner "windows-restart" {
    # force restart 
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Enable Windows Features 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [templatefile("${path.root}/../_templates/InstallFeatures.pkrtpl.hcl", { features = local.resolved.features })]
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Install Windows Updates (1/2)
  # =============================================================================================

  provisioner "windows-update" {
    search_criteria = local.update.search
    filters = local.update.filters
  }

  # =============================================================================================
  # Install DevDrive 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [templatefile("${path.root}/../_templates/InstallDevDrive.pkrtpl.hcl", { devDrive = local.devDrive })]
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Install Package Managers 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    scripts           = setunion(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      fileset("${path.root}", "../_scripts/pkgs/*.ps1")
    ) 
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Prepare Sequence 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    scripts           = local.resolved.prepare
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Package Sequence
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [templatefile("${path.root}/../_templates/InstallPackages.pkrtpl.hcl", { packages = local.resolved.packages })]
    max_retries       = 5
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Configure sequence 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    scripts           = local.resolved.configure
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Install repositories 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [templatefile("${path.root}/../_templates/InstallRepositories.pkrtpl.hcl", { devDrive = local.image.devDrive })]
  }

  # =============================================================================================
  # Publish Image Capabilities 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    inline            = [templatefile("${path.root}/../_templates/CapabilitiesDocument.pkrtpl.hcl", { packages = local.resolved.packages })]
  }

  # =============================================================================================
  # Install Windows Updates (2/2)
  # =============================================================================================

  provisioner "windows-update" {
    search_criteria = local.update.search
    filters = local.update.filters
  }

  # =============================================================================================
  # Finalize Image by generalizing VM
  # =============================================================================================

  provisioner "powershell" {
	  elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    timeout           = "1h"
    script            = "${path.root}/../_scripts/core/Generalize-VM.ps1"
  }

  # =============================================================================================
  # On Error - Collect information from remote system
  # =============================================================================================

  error-cleanup-provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.default.environmentVariables
    scripts           = setunion(
      ["${path.root}/../_scripts/core/NOOP.ps1"],
      fileset("${path.root}", "../_scripts/error/*.ps1")
    ) 
  }
}
