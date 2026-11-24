terraform {
  required_version = "= 1.16.2"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  use_cli                         = true
  use_msi                         = false
  use_oidc                        = false
  resource_provider_registrations = "none"
}

variable "subscription_id" { type = string }
variable "tenant_id" { type = string }
variable "run_id" {
  type = string
  validation {
    condition     = can(regex("^d46-[a-f0-9]{8}$", var.run_id))
    error_message = "Use the exact saved lesson run identifier."
  }
}
variable "allowed_location" { type = string }
variable "owner_value" { type = string }

locals {
  nsg_type = "Microsoft.Network/networkSecurityGroups"
  tags     = { labRun = var.run_id, Owner = var.owner_value }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-csl-policy-${var.run_id}"
  location = var.allowed_location
  tags     = local.tags
}

# Both resources start compliant. Preparation removes Owner from drift only.
# The learner restores the tag to this declared state; no ignore_changes trick.
resource "azurerm_network_security_group" "sample" {
  for_each            = toset(["reference", "drift"])
  name                = "nsg-${each.key}"
  location            = var.allowed_location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_policy_definition" "owner" {
  name         = "csl-${var.run_id}-owner"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "CSL ${var.run_id} - audit NSG Owner"
  description  = "Training: audit NSGs missing the approved Owner value; no automatic repair."
  metadata     = jsonencode({ category = "Cloud Security Lab", labRun = var.run_id })
  parameters = jsonencode({
    ownerValue = { type = "String", metadata = { displayName = "Required Owner value" } }
  })
  policy_rule = jsonencode({
    if = { allOf = [
      { field = "type", equals = local.nsg_type },
      { field = "tags[Owner]", notEquals = "[parameters('ownerValue')]" }
    ] }
    then = { effect = "Audit" }
  })
}

resource "azurerm_policy_definition" "location" {
  name         = "csl-${var.run_id}-location"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "CSL ${var.run_id} - deny other NSG locations"
  description  = "Training: restrict NSGs to the assigned location list."
  metadata     = jsonencode({ category = "Cloud Security Lab", labRun = var.run_id })
  parameters = jsonencode({
    allowedLocations = { type = "Array", metadata = { displayName = "Allowed locations", strongType = "location" } }
  })
  policy_rule = jsonencode({
    if = { allOf = [
      { field = "type", equals = local.nsg_type },
      { field = "location", notIn = "[parameters('allowedLocations')]" }
    ] }
    then = { effect = "Deny" }
  })
}

resource "azurerm_resource_group_policy_assignment" "owner" {
  name                 = "csl-owner-audit"
  display_name         = "Day 46 - Owner audit"
  resource_group_id    = azurerm_resource_group.lab.id
  policy_definition_id = azurerm_policy_definition.owner.id
  enforce              = true
  parameters           = jsonencode({ ownerValue = { value = var.owner_value } })
}

resource "azurerm_resource_group_policy_assignment" "location" {
  name                 = "csl-location-deny"
  display_name         = "Day 47 - Location deny"
  resource_group_id    = azurerm_resource_group.lab.id
  policy_definition_id = azurerm_policy_definition.location.id
  enforce              = true
  parameters           = jsonencode({ allowedLocations = { value = [var.allowed_location] } })
}
