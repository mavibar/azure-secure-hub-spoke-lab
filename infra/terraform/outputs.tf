output "resource_group_name" {
  description = "Name of the existing sandbox resource group."
  value       = data.azurerm_resource_group.lab.name
}

output "hub_vnet_id" {
  description = "Resource ID of the hub VNet."
  value       = azurerm_virtual_network.hub.id
}

output "app_vnet_id" {
  description = "Resource ID of the application spoke VNet."
  value       = azurerm_virtual_network.app.id
}

output "web_subnet_id" {
  description = "Resource ID of the web subnet."
  value       = azurerm_subnet.web.id
}

output "app_subnet_id" {
  description = "Resource ID of the application subnet."
  value       = azurerm_subnet.app.id
}

output "data_subnet_id" {
  description = "Resource ID of the data subnet."
  value       = azurerm_subnet.data.id
}

output "web_nsg_id" {
  description = "Resource ID of the web-tier NSG."
  value       = azurerm_network_security_group.web.id
}

output "app_nsg_id" {
  description = "Resource ID of the application-tier NSG."
  value       = azurerm_network_security_group.app.id
}

output "data_nsg_id" {
  description = "Resource ID of the data-tier NSG."
  value       = azurerm_network_security_group.data.id
}