// modules/backend.bicep
param location string
param principalId string
param openAiSku string = 'S0'

var keyVaultName = 'kv-${uniqueString(resourceGroup().id)}'
var openAiName = 'oai-${uniqueString(resourceGroup().id)}'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    accessPolicies: [
      {
        tenantId: tenant().tenantId
        objectId: principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
    enableRbacAuthorization: false // Gebruik access policies voor dit voorbeeld
  }
}

resource openAi 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiName
  location: location
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Disabled' // Belangrijk voor private endpoint
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output openAiId string = openAi.id
