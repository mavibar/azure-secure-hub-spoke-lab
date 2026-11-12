resource "azurerm_network_security_rule" "rdp_investigation" {
  name                        = "Allow-Management-RDP"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = "rg-day41-fixture"
  network_security_group_name = "nsg-day41-fixture"
}
