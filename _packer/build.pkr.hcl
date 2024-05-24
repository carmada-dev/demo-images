build {

  sources = ["source.azure-arm.vm"]

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
    environment_vars = setunion(local.environment, [
      "ADMIN_USERNAME=${build.User}",
      "ADMIN_PASSWORD=${build.Password}"
    ])
    script            = "${local.path.imageRoot}/../_scripts/core/Initialize-VM.ps1"
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
    scripts           = setunion(
      ["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
      fileset("${local.path.imageRoot}", "../_scripts/pkgs/*.ps1")
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
    environment_vars  = local.environment
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
    environment_vars  = local.environment
    inline            = [templatefile("${local.path.imageRoot}/../_templates/InstallPackages.pkrtpl.hcl", { packages = local.resolved.packages })]
    max_retries       = 10
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
    environment_vars  = local.environment
    timeout           = "1h"
    script            = "${local.path.imageRoot}/../_scripts/core/Generalize-VM.ps1"
  }

  # =============================================================================================
  # On Error - Collect information from remote system
  # =============================================================================================

  error-cleanup-provisioner "powershell" {
    elevated_user     = build.User
    elevated_password = build.Password
    environment_vars  = local.environment
    scripts           = setunion(
      ["${local.path.imageRoot}/../_scripts/core/NOOP.ps1"],
      fileset("${local.path.imageRoot}", "../_scripts/error/*.ps1")
    ) 
  }
}
