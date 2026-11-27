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
    condition     = can(regex("^d51-[a-f0-9]{8}$", var.run_id))
    error_message = "Use the exact saved case identifier."
  }
}
variable "ssh_public_key" { type = string }
variable "shutdown_utc" { type = string }
variable "schedule_start_utc" { type = string }
variable "role_ids" { type = map(string) }
locals { tags = { labRun = var.run_id, Owner = "CloudSecurityLab", Purpose = "Disposable Azure Disk Backup lesson" } }
resource "azurerm_resource_group" "lab" {
  name     = "rg-csl-recovery-${var.run_id}"
  location = "eastus"
  tags     = local.tags
}
resource "azurerm_resource_group" "snapshots" {
  name     = "rg-csl-snapshots-${var.run_id}"
  location = azurerm_resource_group.lab.location
  tags     = local.tags
}
resource "azurerm_resource_group" "restored" {
  name     = "rg-csl-restored-${var.run_id}"
  location = azurerm_resource_group.lab.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "lab" {
  name                = "vnet-recovery"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = ["10.51.0.0/24"]
  tags                = local.tags
}
resource "azurerm_subnet" "tester" {
  name                            = "tester"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.51.0.0/27"]
  default_outbound_access_enabled = false
}
resource "azurerm_network_security_group" "tester" {
  name                = "nsg-recovery-no-inbound"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
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
resource "azurerm_public_ip" "egress" {
  name                = "pip-recovery-egress"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}
resource "azurerm_network_interface" "tester" {
  name                = "nic-recovery-tester"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
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
  name                            = "vm-recovery-tester"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = "Standard_B2als_v2"
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.tester.id]
  depends_on                      = [azurerm_network_interface_security_group_association.tester]
  admin_ssh_key {
    username   = "labadmin"
    public_key = var.ssh_public_key
  }
  os_disk {
    name                 = "disk-recovery-os"
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
resource "azurerm_managed_disk" "source" {
  name                          = "disk-source-data"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  storage_account_type          = "StandardSSD_LRS"
  create_option                 = "Empty"
  disk_size_gb                  = 4
  network_access_policy         = "DenyAll"
  public_network_access_enabled = false
  tags                          = local.tags
}
resource "azurerm_virtual_machine_data_disk_attachment" "source" {
  managed_disk_id    = azurerm_managed_disk.source.id
  virtual_machine_id = azurerm_linux_virtual_machine.tester.id
  lun                = 0
  caching            = "None"
}
resource "azurerm_data_protection_backup_vault" "lab" {
  name                       = "bv-disk-lesson"
  resource_group_name        = azurerm_resource_group.lab.name
  location                   = azurerm_resource_group.lab.location
  datastore_type             = "VaultStore"
  redundancy                 = "LocallyRedundant"
  soft_delete                = "On"
  retention_duration_in_days = 14
  identity { type = "SystemAssigned" }
  tags = local.tags
}
resource "azurerm_data_protection_backup_policy_disk" "daily" {
  name                            = "daily-seven-days"
  vault_id                        = azurerm_data_protection_backup_vault.lab.id
  backup_repeating_time_intervals = ["R/${var.schedule_start_utc}/P1D"]
  default_retention_duration      = "P7D"
  time_zone                       = "UTC"
}
resource "azurerm_role_assignment" "reader" {
  name                             = var.role_ids["Reader"]
  scope                            = azurerm_managed_disk.source.id
  role_definition_name             = "Disk Backup Reader"
  principal_id                     = azurerm_data_protection_backup_vault.lab.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
resource "azurerm_role_assignment" "snapshot" {
  name                             = var.role_ids["Snapshot"]
  scope                            = azurerm_resource_group.snapshots.id
  role_definition_name             = "Disk Snapshot Contributor"
  principal_id                     = azurerm_data_protection_backup_vault.lab.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
resource "azurerm_role_assignment" "restore" {
  name                             = var.role_ids["Restore"]
  scope                            = azurerm_resource_group.restored.id
  role_definition_name             = "Disk Restore Operator"
  principal_id                     = azurerm_data_protection_backup_vault.lab.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
resource "azurerm_data_protection_backup_instance_disk" "source" {
  name                         = "backup-source-data"
  location                     = azurerm_resource_group.lab.location
  vault_id                     = azurerm_data_protection_backup_vault.lab.id
  disk_id                      = azurerm_managed_disk.source.id
  snapshot_resource_group_name = azurerm_resource_group.snapshots.name
  backup_policy_id             = azurerm_data_protection_backup_policy_disk.daily.id
  depends_on                   = [azurerm_role_assignment.reader, azurerm_role_assignment.snapshot, azurerm_role_assignment.restore]
}
output "vault_principal" { value = azurerm_data_protection_backup_vault.lab.identity[0].principal_id }
