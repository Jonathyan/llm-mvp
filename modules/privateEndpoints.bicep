// modules/privateEndpoints.bicep
param location string
param vnetId string
param privateSubnetId string
param keyVaultId string
param openAiId string

// DNS Zone voor Key Vault
resource privateDnsZoneKeyVault 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource vnetLinkKeyVault 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneKeyVault
  name: '${last(split(vnetId, '/'))}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private Endpoint voor Key Vault
resource peKeyVault 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-keyvault'
  location: location
  properties: {
    subnet: {
      id: privateSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-keyvault'
        properties: {
          privateLinkServiceId: keyVaultId
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource peDnsGroupKeyVault 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: peKeyVault
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-kv'
        properties: {
          privateDnsZoneId: privateDnsZoneKeyVault.id
        }
      }
    ]
  }
}

// DNS Zone voor OpenAI
resource privateDnsZoneOpenAI 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.openai.azure.com'
  location: 'global'
}

resource vnetLinkOpenAI 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneOpenAI
  name: '${last(split(vnetId, '/'))}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private Endpoint voor OpenAI
resource peOpenAI 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-openai'
  location: location
  properties: {
    subnet: {
      id: privateSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-openai'
        properties: {
          privateLinkServiceId: openAiId
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource peDnsGroupOpenAI 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: peOpenAI
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-oai'
        properties: {
          privateDnsZoneId: privateDnsZoneOpenAI.id
        }
      }
    ]
  }
}
