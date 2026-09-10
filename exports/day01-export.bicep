param virtualNetworks_vnet_app_dev_name string = 'vnet-app-dev'
param virtualNetworks_vnet_hub_dev_name string = 'vnet-hub-dev'

resource virtualNetworks_vnet_app_dev_name_resource 'Microsoft.Network/virtualNetworks@2025-07-01' = {
  name: virtualNetworks_vnet_app_dev_name
  location: 'eastus'
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    encryption: {
      enabled: false
      enforcement: 'AllowUnencrypted'
    }
    privateEndpointVNetPolicies: 'Disabled'
    subnets: [
      {
        name: 'snet-web'
        id: virtualNetworks_vnet_app_dev_name_snet_web.id
        properties: {
          addressPrefixes: [
            '10.20.1.0/24'
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-app'
        id: virtualNetworks_vnet_app_dev_name_snet_app.id
        properties: {
          addressPrefixes: [
            '10.20.2.0/24'
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-data'
        id: virtualNetworks_vnet_app_dev_name_snet_data.id
        properties: {
          addressPrefixes: [
            '10.20.3.0/24'
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
    ]
    virtualNetworkPeerings: [
      {
        name: 'hub-to-app'
        id: virtualNetworks_vnet_app_dev_name_hub_to_app.id
        properties: {
          peeringState: 'Connected'
          peeringSyncLevel: 'FullyInSync'
          remoteVirtualNetwork: {
            id: virtualNetworks_vnet_hub_dev_name_resource.id
          }
          allowVirtualNetworkAccess: true
          allowForwardedTraffic: false
          allowGatewayTransit: false
          useRemoteGateways: false
          doNotVerifyRemoteGateways: false
          peerCompleteVnets: true
          enableOnlyIPv6Peering: false
          remoteAddressSpace: {
            addressPrefixes: [
              '10.10.0.0/16'
            ]
          }
          remoteVirtualNetworkAddressSpace: {
            addressPrefixes: [
              '10.10.0.0/16'
            ]
          }
        }
      }
    ]
    enableDdosProtection: false
  }
}

resource virtualNetworks_vnet_hub_dev_name_resource 'Microsoft.Network/virtualNetworks@2025-07-01' = {
  name: virtualNetworks_vnet_hub_dev_name
  location: 'eastus'
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    encryption: {
      enabled: false
      enforcement: 'AllowUnencrypted'
    }
    privateEndpointVNetPolicies: 'Disabled'
    subnets: [
      {
        name: 'snet-management'
        id: virtualNetworks_vnet_hub_dev_name_snet_management.id
        properties: {
          addressPrefixes: [
            '10.10.1.0/24'
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      {
        name: 'AzureFirewallSubnet'
        id: virtualNetworks_vnet_hub_dev_name_AzureFirewallSubnet.id
        properties: {
          addressPrefixes: [
            '10.10.2.0/26'
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      {
        name: 'GatewaySubnet'
        id: virtualNetworks_vnet_hub_dev_name_GatewaySubnet.id
        properties: {
          addressPrefixes: [
            '10.10.3.0/27'
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
    ]
    virtualNetworkPeerings: [
      {
        name: 'app-to-hub'
        id: virtualNetworks_vnet_hub_dev_name_app_to_hub.id
        properties: {
          peeringState: 'Connected'
          peeringSyncLevel: 'FullyInSync'
          remoteVirtualNetwork: {
            id: virtualNetworks_vnet_app_dev_name_resource.id
          }
          allowVirtualNetworkAccess: true
          allowForwardedTraffic: false
          allowGatewayTransit: false
          useRemoteGateways: false
          doNotVerifyRemoteGateways: false
          peerCompleteVnets: true
          enableOnlyIPv6Peering: false
          remoteAddressSpace: {
            addressPrefixes: [
              '10.20.0.0/16'
            ]
          }
          remoteVirtualNetworkAddressSpace: {
            addressPrefixes: [
              '10.20.0.0/16'
            ]
          }
        }
      }
    ]
    enableDdosProtection: false
  }
}

resource virtualNetworks_vnet_hub_dev_name_AzureFirewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  name: '${virtualNetworks_vnet_hub_dev_name}/AzureFirewallSubnet'
  properties: {
    addressPrefixes: [
      '10.10.2.0/26'
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
  }
  dependsOn: [
    virtualNetworks_vnet_hub_dev_name_resource
  ]
}

resource virtualNetworks_vnet_hub_dev_name_GatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  name: '${virtualNetworks_vnet_hub_dev_name}/GatewaySubnet'
  properties: {
    addressPrefixes: [
      '10.10.3.0/27'
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
  }
  dependsOn: [
    virtualNetworks_vnet_hub_dev_name_resource
  ]
}

resource virtualNetworks_vnet_app_dev_name_snet_app 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  name: '${virtualNetworks_vnet_app_dev_name}/snet-app'
  properties: {
    addressPrefixes: [
      '10.20.2.0/24'
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
  }
  dependsOn: [
    virtualNetworks_vnet_app_dev_name_resource
  ]
}

resource virtualNetworks_vnet_app_dev_name_snet_data 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  name: '${virtualNetworks_vnet_app_dev_name}/snet-data'
  properties: {
    addressPrefixes: [
      '10.20.3.0/24'
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
  }
  dependsOn: [
    virtualNetworks_vnet_app_dev_name_resource
  ]
}

resource virtualNetworks_vnet_hub_dev_name_snet_management 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  name: '${virtualNetworks_vnet_hub_dev_name}/snet-management'
  properties: {
    addressPrefixes: [
      '10.10.1.0/24'
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
  }
  dependsOn: [
    virtualNetworks_vnet_hub_dev_name_resource
  ]
}

resource virtualNetworks_vnet_app_dev_name_snet_web 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  name: '${virtualNetworks_vnet_app_dev_name}/snet-web'
  properties: {
    addressPrefixes: [
      '10.20.1.0/24'
    ]
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
  }
  dependsOn: [
    virtualNetworks_vnet_app_dev_name_resource
  ]
}

resource virtualNetworks_vnet_hub_dev_name_app_to_hub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-07-01' = {
  name: '${virtualNetworks_vnet_hub_dev_name}/app-to-hub'
  properties: {
    peeringState: 'Connected'
    peeringSyncLevel: 'FullyInSync'
    remoteVirtualNetwork: {
      id: virtualNetworks_vnet_app_dev_name_resource.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    doNotVerifyRemoteGateways: false
    peerCompleteVnets: true
    enableOnlyIPv6Peering: false
    remoteAddressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    remoteVirtualNetworkAddressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
  }
  dependsOn: [
    virtualNetworks_vnet_hub_dev_name_resource
  ]
}

resource virtualNetworks_vnet_app_dev_name_hub_to_app 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-07-01' = {
  name: '${virtualNetworks_vnet_app_dev_name}/hub-to-app'
  properties: {
    peeringState: 'Connected'
    peeringSyncLevel: 'FullyInSync'
    remoteVirtualNetwork: {
      id: virtualNetworks_vnet_hub_dev_name_resource.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    doNotVerifyRemoteGateways: false
    peerCompleteVnets: true
    enableOnlyIPv6Peering: false
    remoteAddressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    remoteVirtualNetworkAddressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
  }
  dependsOn: [
    virtualNetworks_vnet_app_dev_name_resource
  ]
}
