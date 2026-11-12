# Azure NSG module fixture

This module is copied from the committed Days 37–38 NSG module for the Days 40–41 pull-request investigation. Its caller supplies synthetic exercise values.

The caller provides four inputs.

- `name` is a string containing the NSG name.
- `location` is a string containing the Azure region.
- `resource_group_name` is a string containing the resource group name.
- `tags` is a map of string tag values.

The module exposes two outputs.

- `name` is the NSG name.
- `id` is its Azure resource ID.

The module requires `hashicorp/azurerm` version `5.4.0`. The exercise root selects it with `source = "./modules/nsg"`.
