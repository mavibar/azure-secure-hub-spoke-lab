terraform {
  required_version = "= 1.16.2"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "= 5.4.0" }
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
    condition     = can(regex("^d48-[a-f0-9]{8}$", var.run_id))
    error_message = "Use the saved run ID; never adopt an existing fixture."
  }
}
variable "ssh_public_key" { type = string }
variable "role_assignment_id" { type = string }
variable "reviewer_assignment_id" { type = string }
variable "reviewer_principal_id" { type = string }
variable "shutdown_utc" { type = string }
locals {
  tags = { labRun = var.run_id, Owner = "CloudSecurityLab", Purpose = "Disposable private access lesson" }
}
resource "azurerm_resource_group" "lab" {
  name     = "rg-csl-private-${var.run_id}"
  location = "eastus"
  tags     = local.tags
}
resource "azurerm_virtual_network" "lab" {
  name                = "vnet-private-lesson"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.48.0.0/24"]
  tags                = local.tags
}
resource "azurerm_subnet" "tester" {
  name                            = "tester"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.48.0.0/27"]
  default_outbound_access_enabled = false
}
resource "azurerm_subnet" "endpoint" {
  name                              = "endpoint"
  resource_group_name               = azurerm_resource_group.lab.name
  virtual_network_name              = azurerm_virtual_network.lab.name
  address_prefixes                  = ["10.48.0.32/27"]
  private_endpoint_network_policies = "Disabled"
  default_outbound_access_enabled   = false
}
resource "azurerm_network_security_group" "tester" {
  name                = "nsg-tester-no-inbound"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
# Explicit egress for the VM agent. The external control test runs on the host.
# The NSG denies all new inbound connections, including SSH.
resource "azurerm_public_ip" "egress" {
  name                = "pip-tester-egress"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}
resource "azurerm_network_interface" "tester" {
  name                = "nic-tester"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.tester.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.egress.id
  }
}
resource "azurerm_network_interface_security_group_association" "tester" {
  network_interface_id      = azurerm_network_interface.tester.id
  network_security_group_id = azurerm_network_security_group.tester.id
}
resource "azurerm_linux_virtual_machine" "tester" {
  name                            = "vm-private-tester"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = "Standard_B2als_v2"
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.tester.id]
  depends_on                      = [azurerm_network_interface_security_group_association.tester]
  admin_ssh_key {
    username   = "labadmin"
    public_key = var.ssh_public_key
  }
  identity { type = "SystemAssigned" }
  os_disk {
    name                 = "disk-private-tester"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 32
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "24.04.202610250"
  }
  tags = local.tags
}
resource "azurerm_dev_test_global_vm_shutdown_schedule" "safety" {
  virtual_machine_id    = azurerm_linux_virtual_machine.tester.id
  location              = azurerm_resource_group.lab.location
  enabled               = true
  daily_recurrence_time = var.shutdown_utc
  timezone              = "UTC"
  notification_settings { enabled = false }
  tags = local.tags
}
resource "azurerm_storage_account" "lab" {
  name                            = "csl${replace(var.run_id, "-", "")}"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }
  tags = local.tags
}
resource "azurerm_storage_container" "lesson" {
  name                  = "lesson"
  storage_account_id    = azurerm_storage_account.lab.id
  container_access_type = "private"
}
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "lab" {
  name                 = "link-lesson-vnet"
  private_dns_zone_id  = azurerm_private_dns_zone.blob.id
  virtual_network_id   = azurerm_virtual_network.lab.id
  registration_enabled = false
  tags                 = local.tags
}
resource "azurerm_private_endpoint" "blob" {
  name                          = "pe-lesson-blob"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  subnet_id                     = azurerm_subnet.endpoint.id
  custom_network_interface_name = "nic-private-endpoint"
  private_service_connection {
    name                           = "connection-blob"
    private_connection_resource_id = azurerm_storage_account.lab.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
  private_dns_zone_group {
    name                 = "blob-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
  tags = local.tags
}
# The fixture writer needs PUT for one dummy blob. Scope is this one container.
# Network controls are tested without changing this assignment between probes.
resource "azurerm_role_assignment" "dummy_writer" {
  name                             = var.role_assignment_id
  scope                            = azurerm_storage_container.lesson.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_linux_virtual_machine.tester.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
output "private_ip" { value = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address }
output "principal_id" { value = azurerm_linux_virtual_machine.tester.identity[0].principal_id }

# Existing reviewer only: authorized external read test, no new human identity.
resource "azurerm_role_assignment" "external_reader" {
  name                 = var.reviewer_assignment_id
  scope                = azurerm_storage_container.lesson.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.reviewer_principal_id
  principal_type       = "User"
}
