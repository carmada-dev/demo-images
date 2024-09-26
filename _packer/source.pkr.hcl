source "azure-arm" "vm" {

  # general settings
  skip_create_image                   = false
  async_resourcegroup_delete          = true
  secure_boot_enabled                 = true
  use_azure_cli_auth                  = true
  vtpm_enabled                        = true
  security_type                       = "TrustedLaunch"
  vm_size                             = "Standard_D8s_v5"
  license_type                        = "Windows_Client"

  # winrm options
  communicator                        = "winrm"
  winrm_username                      = "packer"
  winrm_insecure                      = true
  winrm_timeout                       = "15m"
  winrm_use_ssl                       = true

  # avoid keyvault creation
  skip_create_build_key_vault         = true
  custom_script                       = "powershell -ExecutionPolicy Unrestricted -NoProfile -NonInteractive -Command \"$userData = (Invoke-RestMethod -H @{'Metadata'='True'} -Method GET -Uri 'http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-01-01&format=text'); $contents = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($userData)); set-content -path c:\\Windows\\Temp\\userdata.ps1 -value $contents; . c:\\Windows\\Temp\\userdata.ps1;\""
  user_data_file                      = "../_packer/vm_userdata.ps1"

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
  user_assigned_managed_identities    = [ local.factory.identity ]
  temp_resource_group_name            = "PKR-${upper(local.variables.imageName)}-${upper(local.variables.imageVersion)}${upper(local.variables.imageSuffix)}"
  public_ip_sku                       = "Standard"

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

  # spot {
  #     eviction_policy                 = "Delete"
  #     max_price                       = "-1" # -1 means the current on-demand price
  # }

  # new image version are excluded from latest to support staging
  shared_gallery_image_version_exclude_from_latest = true
}