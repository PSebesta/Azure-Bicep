param namePrefix string
param rglocation string = resourceGroup().location
param CopyCount int = 2

@allowed([
  'Test'
  'Prod'
])
param VmSize string


param AdminUserName string

@secure()
param AdminPassword string

param ObjectId string

var VnetName = '${namePrefix}-${uniqueString(resourceGroup().id)}-vnet'
var VnetAddressSpace = '172.17.0.0/16'
var VmSubnetName = 'Vm-${namePrefix}-subnet'
var VmSubnet = '172.17.0.64/27'
var GwSubnetName = 'gw-${namePrefix}-subnet'
var GwSubnet = '172.17.1.0/24'
var KeyVaultName = 'Kv-${namePrefix}-${uniqueString(resourceGroup().id)}'
var vmSizeForTest = 'Standard_B2s'
var vmSizeForProd = 'Standard_D2s_v3'
var selectedVmSize = VmSize == 'test' ? vmSizeForTest : vmSizeForProd



resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: KeyVaultName
  location: rglocation
  properties: {
    enablePurgeProtection: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: ObjectId
        permissions: {
          keys: [
            'get'
          ]
          secrets: [
            'list'
            'get'
            'set'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

resource storageaccount 'Microsoft.Storage/storageAccounts@2023-01-01' = [for i in range(0, CopyCount): {
  name: '${namePrefix}${resourceGroup().id}store${i}'
  location: rglocation
  kind: 'StorageV2'
  sku: {
    name: 'Standard_RAGRS'
    
  }
}]

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: VnetName
  location: rglocation
  properties: {
    addressSpace: {
      addressPrefixes: [
        VnetAddressSpace
      ]
    }
    subnets: [
      {
        name: VmSubnetName
        properties: {
          addressPrefix: VmSubnet
        }
      }
      {
        name: GwSubnetName
        properties: {
          addressPrefix: GwSubnet
        }
      }
    ]
  }
}

resource publicIPAdress 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-pip'
  location: rglocation
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${namePrefix}-${uniqueString(resourceGroup().id)}'
    }
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-nsg'
  location: rglocation
  properties: {
    securityRules: [
      {
        name: '${namePrefix}nsgR1'
        properties: {
          description: 'description'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-04-01' = [for i in range(0, CopyCount): {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-vnic-${i}'
  location: rglocation
  properties: {
    ipConfigurations: [
      {
        name: '${namePrefix}-ipconf1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: format('Microsoft.Network/virtualNetworks/subnets/%s/%s', virtualNetwork.name, VmSubnetName)
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: format('Microsoft.Network/networkSecurityGroups/%s', networkSecurityGroup.name)
    }
  }
}]

resource loadBalancerInternal 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-LB'
  location: rglocation
  properties: {
    frontendIPConfigurations: [
      {
        name: '${namePrefix}-LB-FrontEnd'
        properties: {
          privateIPAddress: '172.17.0.94'
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: format('Microsoft.Network/virtualNetworks/subnets/%s/%s', virtualNetwork.name, VmSubnetName)
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: '${namePrefix}-BckEndPool'
      }
    ]
    loadBalancingRules: [
      {
        name: '${namePrefix}-LBRule1'
        properties: {
          frontendIPConfiguration: {
            id: 'frontendIPConfiguration.id'
          }
          backendAddressPool: {
            id: 'backendAddressPool.id'
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: 'probe.id'
          }
        }
      }
    ]
    probes: [
      {
        name: 'name'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}

resource applicationGateway 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGW'
  location: rglocation
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'name'
        properties: {
          subnet: {
            id: 'id'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'name'
        properties: {
          publicIPAddress: {
            id: 'id'
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'name'
        properties: {
          port: 'port'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'name'
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'name'
        properties: {
          port: 'port'
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
        }
      }
    ]
    httpListeners: [
      {
        name: 'name'
        properties: {
          frontendIPConfiguration: {
            id: 'id'
          }
          frontendPort: {
            id: 'id'
          }
          protocol: 'Http'
          sslCertificate: null
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'name'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: 'id'
          }
          backendAddressPool: {
            id: 'id'
          }
          backendHttpSettings: {
            id: 'id'
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
    publicIPAdress
  ]
}

resource applicationGatewayFirewall 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-WafPolicy'
  location: rglocation
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Detection'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.1'
        }
      ]
    }
  }
  dependsOn: [
    publicIPAdress
    virtualNetwork
    applicationGateway
    networkSecurityGroup
  ]
}

resource windowsVM 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, CopyCount): {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-Vm${i}'
  location: rglocation
  properties: {
    hardwareProfile: {
      vmSize: selectedVmSize
    }
    osProfile: {
      computerName: '${namePrefix}server${i}'
      adminUsername: AdminUserName
      adminPassword: AdminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: '${namePrefix}-${uniqueString(resourceGroup().id)}-OsDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: format('Microsoft.Network/networkInterfaces/%s', networkInterface[i].name)
        }
      ]
    }
    }
}]


