targetScope = 'subscription'
param location string
param resourceGroupName string
param keyVaultName string
param keyVaultResourceGroupName string

// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  params: {
    name: resourceGroupName
    location: location
  }
}

// vnet
module virtualNetworks '../modules/Microsoft.Network/virtualNetworks/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-virtualNetworks'
  scope: resourceGroup(resourceGroupName)
  params: {
    // Required parameters
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    name: 'vnet-01'
    subnets: [
      {
        name: 'subnet-01'
        addressPrefix: '10.0.1.0/24'
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

// basic lb
module loadbalancer '../modules/Microsoft.Network/loadBalancers/deploy.bicep' = {
  name: 'lb-basic-01'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'lb-basic-01'
    location: location
    frontendIPConfigurations: [
      {
        name: 'fe-01'
        subnetId: virtualNetworks.outputs.subnetResourceIds[0]
      }
    ]
    backendAddressPools: [
      {
        name: 'be-01'
      }
    ]
    inboundNatRules: []
    loadBalancerSku: 'Basic'
    loadBalancingRules: [
      {
        backendAddressPoolName: 'be-01'
        backendPort: 80
        frontendIPConfigurationName: 'fe-01'
        frontendPort: 80
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
        name: 'rule-01'
        probeName: 'probe-01'
        protocol: 'Tcp'
      }
    ]
    probes: [
      {
        intervalInSeconds: 5
        name: 'probe-01'
        numberOfProbes: 2
        port: '80'
        protocol: 'Tcp'
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

resource kv1 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroupName)
}

module virtualMachineScaleSets '../modules/Microsoft.Compute/virtualMachineScaleSets/deploy.bicep' = {
  name: 'vmss-01'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    // Required parameters
    encryptionAtHost: false
    adminUsername: kv1.getSecret('adminUsername')
    skuCapacity: 1
    upgradePolicyMode: 'Manual'
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2022-Datacenter'
      version: 'latest'
    }
    name: 'vmss-01'
    osDisk: {
      createOption: 'fromImage'
      diskSizeGB: '128'
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    osType: 'Windows'
    skuName: 'Standard_D2_v4'
    // Non-required parameters
    adminPassword: kv1.getSecret('adminPassword')
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig1'
            properties: {
              primary: true
              subnet: {
                id: virtualNetworks.outputs.subnetResourceIds[0]
              }
              loadBalancerBackendAddressPools: [
                {
                  id: loadbalancer.outputs.backendpools[0].id
                }
              ]
              publicIPAddressConfiguration: {
                name: 'pipconfig1'
                sku: {
                  name: 'Basic'
                }
              }
            }
          }
          {
            name: 'ipconfig2'
            properties: {
              primary: false
              subnet: {
                id: virtualNetworks.outputs.subnetResourceIds[0]
              }
              loadBalancerBackendAddressPools: [
                {
                  id: loadbalancer.outputs.backendpools[0].id
                }
              ]
              publicIPAddressConfiguration: {
                name: 'pipconfig2'
                sku: {
                  name: 'Basic'
                }
              }
            }
          }
        ]
        properties: {
          primary: true
          enableAcceleratedNetworking: false
        }
        nicSuffix: '-nic-01'
      }
      {
        properties: {
          primary: false
          enableAcceleratedNetworking: false
        }
        ipConfigurations: [
          {
            name: 'ipconfig1'
            properties: {
              primary: true
              subnet: {
                id: virtualNetworks.outputs.subnetResourceIds[0]
              }
              loadBalancerBackendAddressPools: [
                {
                  id: loadbalancer.outputs.backendpools[0].id
                }
              ]
              publicIPAddressConfiguration: {
                name: 'pipconfig3'
                sku: {
                  name: 'Basic'
                }
              }
            }
          }
        ]
        nicSuffix: '-nic-02'
      }
    ]
  }
  dependsOn: [
    rg
  ]
}
