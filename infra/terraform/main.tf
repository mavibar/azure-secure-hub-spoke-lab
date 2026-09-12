locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    managedBy   = "terraform"
    purpose     = "cloud-security-lab"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location

  tags = local.common_tags
}