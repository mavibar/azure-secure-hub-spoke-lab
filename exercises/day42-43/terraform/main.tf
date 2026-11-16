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
  use_oidc                        = true
  use_cli                         = false
  resource_provider_registrations = "none"
}

variable "lab_resource_group" {
  type        = string
  description = "Existing resource group on which the CI identity has Reader only."
  sensitive   = true
}

data "azurerm_resource_group" "lab" {
  name = var.lab_resource_group
}

resource "azurerm_network_security_group" "proposed" {
  name                = "nsg-csl-ci-review"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name

  tags = {
    purpose = "learning"
  }
}
