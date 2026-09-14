# ---------------------------------------------------------
# Network Security Groups
# ---------------------------------------------------------

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name

  tags = local.common_tags
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name

  tags = local.common_tags
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-data-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name

  tags = local.common_tags
}


# ---------------------------------------------------------
# Web Tier Rules
# ---------------------------------------------------------

resource "azurerm_network_security_rule" "web_allow_https_from_hub" {
  name                        = "Allow-Hub-HTTPS"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.10.0.0/16"
  destination_address_prefix  = "10.20.1.0/24"
  resource_group_name         = data.azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "web_deny_other_vnet" {
  name                        = "Deny-Other-VNet-Traffic"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.web.name
}


# ---------------------------------------------------------
# Application Tier Rules
# ---------------------------------------------------------

resource "azurerm_network_security_rule" "app_allow_https_from_web" {
  name                        = "Allow-Web-HTTPS"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.20.1.0/24"
  destination_address_prefix  = "10.20.2.0/24"
  resource_group_name         = data.azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "app_deny_other_vnet" {
  name                        = "Deny-Other-VNet-Traffic"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.app.name
}


# ---------------------------------------------------------
# Data Tier Rules
# ---------------------------------------------------------

resource "azurerm_network_security_rule" "data_allow_sql_from_app" {
  name                        = "Allow-App-SQL"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "10.20.2.0/24"
  destination_address_prefix  = "10.20.3.0/24"
  resource_group_name         = data.azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.data.name
}

resource "azurerm_network_security_rule" "data_deny_other_vnet" {
  name                        = "Deny-Other-VNet-Traffic"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.data.name
}


# ---------------------------------------------------------
# NSG-to-Subnet Associations
# ---------------------------------------------------------

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}