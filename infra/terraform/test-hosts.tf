# Temporary Day 5 infrastructure. Keep disabled until sandbox capabilities are checked.
variable "enable_test_hosts" {
  description = "Create the four temporary test hosts and their explicit outbound connectivity."
  type        = bool
  default     = false
}

variable "test_vm_size" {
  description = "A Whizlabs-approved x64 VM size with sufficient regional and family quota."
  type        = string
  default     = ""
  validation {
    condition     = !var.enable_test_hosts || length(trimspace(var.test_vm_size)) > 0
    error_message = "Select a supported VM size before enabling test hosts."
  }
}

variable "test_admin_username" {
  description = "Local Linux administrator name; unrelated to the Whizlabs sign-in account."
  type        = string
  default     = "labadmin"
}

variable "test_ssh_public_key" {
  description = "Public SSH key only. Never put the private key in Terraform."
  type        = string
  default     = ""
  validation {
    condition     = !var.enable_test_hosts || can(regex("^ssh-(rsa|ed25519) ", var.test_ssh_public_key))
    error_message = "Supply an RSA or Ed25519 public SSH key before enabling hosts."
  }
}

variable "test_image" {
  description = "Supported Ubuntu x64 image. Resolve and supply its exact version before deployment."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  validation {
    condition     = !var.enable_test_hosts || (var.test_image.version != "latest" && length(var.test_image.version) > 0)
    error_message = "Resolve the Ubuntu image to an exact version before enabling hosts."
  }
}

locals {
  test_host_definitions = {
    management = { subnet_id = azurerm_subnet.management.id, vnet = "hub", port = 0 }
    web        = { subnet_id = azurerm_subnet.web.id, vnet = "spoke", port = var.service_ports.web }
    app        = { subnet_id = azurerm_subnet.app.id, vnet = "spoke", port = var.service_ports.app }
    data       = { subnet_id = azurerm_subnet.data.id, vnet = "spoke", port = var.service_ports.data }
  }
  active_test_hosts = var.enable_test_hosts ? local.test_host_definitions : {}
  test_vnets        = var.enable_test_hosts ? toset(["hub", "spoke"]) : toset([])
}

# A NAT gateway cannot span VNets: one for management in the hub, one for the spoke.
resource "azurerm_public_ip" "test_egress" {
  for_each            = local.test_vnets
  name                = "pip-test-${each.key}-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "test" {
  for_each            = local.test_vnets
  name                = "nat-test-${each.key}-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  sku_name            = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "test" {
  for_each             = local.test_vnets
  nat_gateway_id       = azurerm_nat_gateway.test[each.key].id
  public_ip_address_id = azurerm_public_ip.test_egress[each.key].id
}

resource "azurerm_subnet_nat_gateway_association" "test" {
  for_each       = local.active_test_hosts
  subnet_id      = each.value.subnet_id
  nat_gateway_id = azurerm_nat_gateway.test[each.value.vnet].id
}

resource "azurerm_network_interface" "test" {
  for_each            = local.active_test_hosts
  name                = "nic-test-${each.key}-${var.environment}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.common_tags
  ip_configuration {
    name                          = "private"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "test" {
  for_each                        = local.active_test_hosts
  name                            = "vm-test-${each.key}-${var.environment}"
  location                        = data.azurerm_resource_group.lab.location
  resource_group_name             = data.azurerm_resource_group.lab.name
  size                            = var.test_vm_size
  admin_username                  = var.test_admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.test[each.key].id]
  tags                            = local.common_tags

  admin_ssh_key {
    username   = var.test_admin_username
    public_key = var.test_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.test_image.publisher
    offer     = var.test_image.offer
    sku       = var.test_image.sku
    version   = var.test_image.version
  }

  # No package downloads. The selected Ubuntu image must already contain Python 3.
  custom_data = base64encode(join("\n", ["#cloud-config", yamlencode({
    package_update  = false
    package_upgrade = false
    write_files = [
      {
        path        = "/opt/lab-listener.py"
        permissions = "0644"
        content     = file("${path.module}/scripts/lab-listener.py")
      },
      {
        path        = "/etc/systemd/system/lab-listener.service"
        permissions = "0644"
        content     = "[Unit]\nDescription=Temporary lab TCP listener\nAfter=network.target\n[Service]\nExecStart=/usr/bin/python3 /opt/lab-listener.py --port ${each.value.port} --role ${each.key}\nRestart=on-failure\n[Install]\nWantedBy=multi-user.target\n"
      }
    ]
    runcmd = each.value.port == 0 ? [
      ["sh", "-c", "test -x /usr/bin/python3"]
      ] : [
      ["sh", "-c", "test -x /usr/bin/python3"],
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "lab-listener.service"]
    ]
  })]))

  depends_on = [
    azurerm_nat_gateway_public_ip_association.test,
    azurerm_subnet_nat_gateway_association.test,
    azurerm_subnet_network_security_group_association.web,
    azurerm_subnet_network_security_group_association.app,
    azurerm_subnet_network_security_group_association.data,
    azurerm_network_security_rule.web_allow_https_from_hub,
    azurerm_network_security_rule.web_deny_other_vnet,
    azurerm_network_security_rule.app_allow_https_from_web,
    azurerm_network_security_rule.app_deny_other_vnet,
    azurerm_network_security_rule.data_allow_sql_from_app,
    azurerm_network_security_rule.data_deny_other_vnet
  ]
}

output "test_hosts" {
  description = "Temporary host names and actual dynamically assigned private addresses."
  value = {
    for role, vm in azurerm_linux_virtual_machine.test : role => {
      vm_name    = vm.name
      vm_id      = vm.id
      nic_id     = azurerm_network_interface.test[role].id
      private_ip = azurerm_network_interface.test[role].private_ip_address
      port       = local.test_host_definitions[role].port
    }
  }
}

output "test_policy_only_other_hub_source" {
  description = "Hypothetical non-management hub source for an IP flow verify policy query, NOT a real test host."
  value       = cidrhost(var.network_cidrs.hub, 4)
}
