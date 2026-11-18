terraform {
  required_version = "= 1.16.2"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.4.0"
    }
  }
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
  use_msi                         = true
  use_cli                         = false
  use_oidc                        = false
  resource_provider_registrations = "none"
}
variable "lab_resource_group" {
  type      = string
  sensitive = true
}
variable "revision" {
  type = string
  validation {
    condition     = contains(["v1", "v2"], var.revision)
    error_message = "Only the two reviewed lab revisions are allowed."
  }
}
data "azurerm_resource_group" "lab" { name = var.lab_resource_group }
resource "azurerm_network_security_group" "proposed" {
  name                = "nsg-csl-ci-review"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags = {
    purpose  = "learning"
    revision = var.revision
  }
}
