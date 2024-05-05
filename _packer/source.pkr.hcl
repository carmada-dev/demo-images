source "azure-arm" "vm" {

  # general settings
  skip_create_image                   = false
  async_resourcegroup_delete          = true
  secure_boot_enabled                 = true
  use_azure_cli_auth                  = true
  security_type                       = "TrustedLaunch"
  vm_size                             = "Standard_D8s_v5"
  license_type                        = "Windows_Client"

  # winrm options
  communicator                        = "winrm"
  winrm_username                      = "packer"
  winrm_insecure                      = true
  winrm_timeout                       = "15m"
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
  user_assigned_managed_identities    = [ local.factory.identity ]
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