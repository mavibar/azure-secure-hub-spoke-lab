locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    managedBy   = "terraform"
    purpose     = "cloud-security-lab"
  }
}

data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}