variable "galleryName" {
  type        = string
  default     = ""
  description = "The name of the target gallery"
}

variable "galleryResourceGroup" {
  type        = string
  default     = ""
  description = "The name of the target gallery resource group"
}

variable "gallerySubscription" {
  type        = string
  default     = ""
  description = "The name of the target gallery subscription"
}

variable "galleryLocation" {
  type        = string
  default     = ""
  description = "The location of the target gallery"
}

variable "imageName" {
  type        = string
  default     = ""
  description = "The name of the image to build"
}

variable "imageVersion" {
  type        = string
  default     = ""
  description = "The version of the image to build"
}

