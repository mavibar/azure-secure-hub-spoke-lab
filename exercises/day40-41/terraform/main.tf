terraform {
  required_version = "~> 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "web_nsg" {
  source              = "./modules/nsg"
  name                = "nsg-day40-fixture"
  location            = "eastus"
  resource_group_name = "rg-day40-fixture"
  tags = {
    purpose = "ci-investigation"
  }
}

output "web_nsg_id" {
  description = "NSG ID exposed by the exercise module."
  value       = module.web_nsg.id
}
