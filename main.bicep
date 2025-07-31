// main.bicep
targetScope = 'resourceGroup'

param location string = resourceGroup().location
param adminUsername string
@secure()
param adminSshKey string
param scriptUrl string // URL naar je 'install-app.sh' script in een publieke repo of storage account
param allowedSshSourceIp string

// Module voor het netwerk
module network 'modules/network.bicep' = {
  name: 'networkDeployment'
  params: {
    location: location
    allowedSshSourceIp: allowedSshSourceIp
  }
}

// Module voor de VM
// Deze module wordt eerst gedeployd om de Principal ID te krijgen
module vm 'modules/vm.bicep' = {
  name: 'vmDeployment'
  params: {
    location: location
    subnetId: network.outputs.publicSubnetId
    adminUsername: adminUsername
    adminSshKey: adminSshKey
    scriptUrl: scriptUrl
  }
}

// Module voor de backend services
// Gebruikt de Principal ID van de VM voor de Key Vault access policy
module backend 'modules/backend.bicep' = {
  name: 'backendDeployment'
  params: {
    location: location
    principalId: vm.outputs.vmPrincipalId
  }
}

// Module voor de Private Endpoints
// Heeft de ID's van de backend services en het netwerk nodig
module privateEndpoints 'modules/privateEndpoints.bicep' = {
  name: 'privateEndpointsDeployment'
  params: {
    location: location
    vnetId: network.outputs.vnetId
    privateSubnetId: network.outputs.privateSubnetId
    keyVaultId: backend.outputs.keyVaultId
    openAiId: backend.outputs.openAiId
  }
}

output keyVaultName string = backend.outputs.keyVaultName
