packer {
  required_plugins {

    # https://github.com/hashicorp/packer-plugin-azure
    azure = {
      version = ">= 0.0.0" 
      source  = "github.com/hashicorp/azure"
    }

    # https://github.com/rgl/packer-plugin-windows-update
    windows-update = {
      version = ">= 0.0.0"
      source  = "github.com/rgl/windows-update"
    }
    
  }
}