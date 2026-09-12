output "resource_group_name" {
  description = "Name of the lab resource group."
  value       = azurerm_resource_group.lab.name
}

output "hub_vnet_id" {
  description = "Resource ID of the hub VNet."
  value       = azurerm_virtual_network.hub.id
}

output "app_vnet_id" {
  description = "Resource ID of the application spoke VNet."
  value       = azurerm_virtual_network.app.id
}