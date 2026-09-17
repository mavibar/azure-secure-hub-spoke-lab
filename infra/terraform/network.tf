# ---------------------------------------------------------
# Hub Virtual Network
# ---------------------------------------------------------

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  address_space       = [var.network_cidrs.hub]

  tags = local.common_tags
}


# ---------------------------------------------------------
# Hub Subnets
# ---------------------------------------------------------

resource "azurerm_subnet" "management" {
  name                            = "snet-management"
  resource_group_name             = data.azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.network_cidrs.management]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = data.azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.network_cidrs.firewall]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = data.azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.network_cidrs.gateway]
}


# ---------------------------------------------------------
# Application Spoke Virtual Network
# ---------------------------------------------------------

resource "azurerm_virtual_network" "app" {
  name                = "vnet-app-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  address_space       = [var.network_cidrs.spoke]

  tags = local.common_tags
}


# ---------------------------------------------------------
# Application Spoke Subnets
# ---------------------------------------------------------

resource "azurerm_subnet" "web" {
  name                            = "snet-web"
  resource_group_name             = data.azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.app.name
  address_prefixes                = [var.network_cidrs.web]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "app" {
  name                            = "snet-app"
  resource_group_name             = data.azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.app.name
  address_prefixes                = [var.network_cidrs.app]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "data" {
  name                            = "snet-data"
  resource_group_name             = data.azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.app.name
  address_prefixes                = [var.network_cidrs.data]
  default_outbound_access_enabled = false
}


# ---------------------------------------------------------
# Hub-to-Spoke VNet Peering
# ---------------------------------------------------------

resource "azurerm_virtual_network_peering" "hub_to_app" {
  name                      = "peer-hub-to-app"
  resource_group_name       = data.azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.app.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
}

resource "azurerm_virtual_network_peering" "app_to_hub" {
  name                      = "peer-app-to-hub"
  resource_group_name       = data.azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.app.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

