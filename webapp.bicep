param namePrefix string
param rglocation string = resourceGroup().location
param CopyCount int = 2

@allowed([
  'Test'
  'Prod'
])
param VmSize string

@description('Storage Account type')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_LRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
  'Standard_ZRS'
])
param storageAccountType string 

param AdminUserName string

@secure()
param AdminPassword string

param ObjectId string


var VnetAddressSpace = '172.17.0.0/16'
var VmSubnet = '172.17.0.64/27'
var GwSubnet = '172.17.1.0/24'
var KeyVaultName = 'Kv-${namePrefix}-${uniqueString(resourceGroup().id)}'
var vmSizeForTest = 'Standard_B2s'
var vmSizeForProd = 'Standard_D4s_v3'
var selectedVmSize = VmSize == 'Test' ? vmSizeForTest : vmSizeForProd


resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: KeyVaultName
  location: rglocation
  properties: {
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
  name: '${namePrefix}${uniqueString(resourceGroup().id)}stor${i}'
  location: rglocation
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}]

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-Vnet'
  location: rglocation
  properties: {
    addressSpace: {
      addressPrefixes: [
        VnetAddressSpace
      ]
    }
    subnets: [
      {
        name: '${namePrefix}-${uniqueString(resourceGroup().id)}-VmSubnet'
        properties: {
          addressPrefix: VmSubnet
        }
      }
      {
        name: '${namePrefix}-${uniqueString(resourceGroup().id)}-GwSubnet'
        properties: {
          addressPrefix: GwSubnet
        }
      }
    ]
  }
}

resource publicip 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-PIP'
  location: rglocation
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-04-01' = [for i in range(0, CopyCount): {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-NIC${i}'
  location: rglocation
  properties: {
    ipConfigurations: [
      {
        name: '${namePrefix}-IpConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', '${virtualNetwork.name}', '${namePrefix}-${uniqueString(resourceGroup().id)}-VmSubnet')
          }
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${namePrefix}-${uniqueString(resourceGroup().id)}-LB', '${namePrefix}-backendPool')
            }
          ]
        }
      }
    ]
    networkSecurityGroup: {
      id: resourceId('Microsoft.Network/networkSecurityGroups', '${namePrefix}-${uniqueString(resourceGroup().id)}-NSG')
    }
  }
  dependsOn: [
    loadBalancerInternal
  ]
}]

//Basic NSG setting to test deployment will need to add specific ports based on feedback
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-NSG'
  location: rglocation
  properties: {
    securityRules: [
      {
        name: 'nsgRule'
        properties: {
          description: 'description'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '80'
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

resource loadBalancerInternal 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-LB'
  location: rglocation
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: '${namePrefix}-FrtEndIpConf'
        properties: {
          privateIPAddress: '172.17.0.94'
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', '${virtualNetwork.name}', '${namePrefix}-${uniqueString(resourceGroup().id)}-VmSubnet')
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: '${namePrefix}-backendPool'
      }
    ]
    loadBalancingRules: [
      {
        name: '${namePrefix}-LBRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', '${namePrefix}-${uniqueString(resourceGroup().id)}-LB', '${namePrefix}-FrtEndIpConf')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${namePrefix}-${uniqueString(resourceGroup().id)}-LB', '${namePrefix}-backendPool')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${namePrefix}-${uniqueString(resourceGroup().id)}-LB', '${namePrefix}-probes')
          }
        }
      }
    ]
    probes: [
      {
        name: '${namePrefix}-probes'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
  }
  dependsOn: []
}

resource windowsVM 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, CopyCount): {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-VM${i}'
  location: rglocation
  properties: {
    hardwareProfile: {
      vmSize: selectedVmSize
    }
    osProfile: {
      computerName: '${namePrefix}server'
      adminUsername: AdminUserName
      adminPassword: AdminPassword
      windowsConfiguration:{
        provisionVMAgent: true
        enableAutomaticUpdates: false
        patchSettings: {
          patchMode: 'Manual'
          assessmentMode: 'ImageDefault'
        }
        enableVMAgentPlatformUpdates: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: '${namePrefix}-${uniqueString(resourceGroup().id)}-OsDisk${i}'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}]

resource applicationGateway 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGw'
  location: rglocation
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: '${namePrefix}-GwIpConf'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', '${virtualNetwork.name}', '${namePrefix}-${uniqueString(resourceGroup().id)}-GwSubnet')
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: '${namePrefix}-FrtEndIpConf'
        properties: {
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', '${publicip.name}')
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: '${namePrefix}-FrtPort'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: '${namePrefix}-BckEndPool'
        properties: {
          backendAddresses: [
            {
              ipAddress: '172.17.0.94'
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: '${namePrefix}-BckHttpSet'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
        }
      }
    ]
    httpListeners: [
      {
        name: '${namePrefix}HttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIpConfigurations', '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGw', '${namePrefix}-FrtEndIpConf')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGw', '${namePrefix}-FrtPort')
          }
          protocol: 'Http'
          sslCertificate: null
        }
      }
    ]
    requestRoutingRules: [
      {
        name: '${namePrefix}-RouteRule'
        properties: {
          ruleType: 'Basic'
          priority: 1
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGw', '${namePrefix}HttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGw', '${namePrefix}-BckEndPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGw', '${namePrefix}-BckHttpSet')
          }
        }
      }
    ]
    firewallPolicy: {
      id: appGW_AppFW_Pol.id
    }
  }
}

resource appGW_AppFW_Pol 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-04-01' = {
  name: '${namePrefix}-${uniqueString(resourceGroup().id)}-AppGwFWPol'
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
}
//install IIs on webservers to test end to end 
resource runCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-03-01' = [for i in range(0, CopyCount): {
  name: '${windowsVM[i].name}/InstallIIS'
  location: rglocation
  properties: {
    asyncExecution: false
    source: {
      script: '''
      Install-WindowsFeature -name Web-Server -IncludeManagementTools
    '''
    }
  }
}
]
