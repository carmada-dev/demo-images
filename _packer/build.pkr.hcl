build {

  sources = ["source.azure-arm.vm"]

  provisioner "windows-update" {
    search_criteria = local.update.search
    filters = local.update.filters
  }
  
  # =============================================================================================
  # Upload Artifacts
  # =============================================================================================

  provisioner "file" {
    source            = "${local.path.imageRoot}/../_scripts/modules/"
    destination       = "${local.path.devboxHome}/Modules/"
  }

  provisioner "file" {
    source            = "${local.path.imageRoot}/../_artifacts/"
    destination       = "${local.path.devboxHome}/Artifacts/"
  }

  provisioner "file" {
    source            = "${local.path.imageRoot}/artifacts/"
    destination       = "${local.path.devboxHome}/Artifacts/"
  }

  # =============================================================================================
  # Initialize VM 
  # =============================================================================================

  provisioner "powershell" {
    environment_vars = distinct(concat(local.environment, [
      "ADMIN_USERNAME=${build.User}",
      "ADMIN_PASSWORD=${build.Password}",
      "AZCOPY_AUTO_LOGIN_TYPE=MSI",
      "AZCOPY_MSI_RESOURCE_STRING=${local.factory.identity}",
    ]))
    script            = "${local.path.imageRoot}/../_scripts/core/Initialize-VM.ps1"
  }

  provisioner "windows-restart" {
    # force restart 
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Install Windows Updates (1/3)
  # =============================================================================================

  provisioner "windows-update" {
    search_criteria = local.update.search
    filters = local.update.filters
  }

  # =============================================================================================
  # Enable Windows Features 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.environment
    inline            = [templatefile("${local.path.imageRoot}/../_templates/InstallFeatures.pkrtpl.hcl", { features = local.resolved.features })]
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Install Language Packs 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.environment
    inline            = [templatefile("${local.path.imageRoot}/../_templates/InstallLanguage.pkrtpl.hcl", { language = local.resolved.language })]
  }

  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Install Windows Updates (2/3)
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
    environment_vars  = local.environment
    inline            = [templatefile("${local.path.imageRoot}/../_templates/InstallDevDrive.pkrtpl.hcl", { devDrive = local.image.devDrive })]
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
    environment_vars  = local.environment
    scripts           = distinct(concat(
      ["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
      [for file in fileset("${local.path.imageRoot}", "../_scripts/pkgs/[^(x_)]*.ps1") : file]
    )) 
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
    environment_vars  = local.environment
    scripts           = distinct(concat(
      ["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
      local.resolved.prepare
    ))
  }
  
  provisioner "windows-restart" {
    check_registry    = true
    restart_timeout   = "30m"
  }

  # =============================================================================================
  # Package Sequence
  # =============================================================================================

  provisioner "powershell" {
    elevated_user       = build.User
    elevated_password   = build.Password
    environment_vars    = local.environment
    inline              = [templatefile("${local.path.imageRoot}/../_templates/InstallPackages.pkrtpl.hcl", { packages = local.resolved.packages })]
    max_retries         = 30
    start_retry_timeout = "2m"
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
    environment_vars  = local.environment
    scripts           = distinct(concat(
      ["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
      local.resolved.configure
    )) 
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
    environment_vars  = local.environment
    inline            = [templatefile("${local.path.imageRoot}/../_templates/InstallRepositories.pkrtpl.hcl", { devDrive = local.image.devDrive })]
  }

  # =============================================================================================
  # Publish Image Capabilities 
  # =============================================================================================

  provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.environment
    inline            = [templatefile("${local.path.imageRoot}/../_templates/CapabilitiesDocument.pkrtpl.hcl", { packages = local.resolved.packages })]
  }

  # =============================================================================================
  # Install Windows Updates (3/3)
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
    environment_vars  = local.environment
    timeout           = "2h"
    script            = "${local.path.imageRoot}/../_scripts/core/Generalize-VM.ps1"
  }

  # =============================================================================================
  # On Error - Collect information from remote system
  # =============================================================================================

  error-cleanup-provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.environment
    scripts           = distinct(concat(
      ["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
      [for file in fileset("${local.path.imageRoot}", "../_scripts/error/*.ps1") : file]
    ))
  }
}
