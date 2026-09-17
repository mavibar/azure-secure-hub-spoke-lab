provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  # Whizlabs administrators own subscription-level provider registration.
  resource_provider_registrations = "none"
}
