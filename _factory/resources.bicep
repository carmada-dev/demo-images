import * as tools from './tools/tools.bicep'
targetScope = 'resourceGroup'

param config object

@secure()
param token string

var factoryName = config.name 
var factoryLocation = config.location

var networkConfig = contains(config, 'network') ? config.network : {}
var peerConfig = contains(networkConfig, 'peer') ? networkConfig.peer : {}
var peerGatewayIP = contains(peerConfig, 'gatewayIP') ? peerConfig.gatewayIP : ''
var peerNetworkId = contains(peerConfig, 'networkId') ? peerConfig.networkId : ''

var runnerConfig = contains(config, 'runner') ? config.runner : {}
var runnerType = empty(runnerConfig) ? '' : runnerConfig.type
var runnerImage = empty(runnerConfig) ? '' : toLower('${factoryName}-${runnerConfig.type}-runner:latest')


resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: factoryName
  location: factoryLocation
}

resource routes 'Microsoft.Network/routeTables@2023-09-01' = {
  name: factoryName
  location: factoryLocation
  properties: {
    routes: [
      {
        name: 'default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: empty(peerGatewayIP) ? 'Internet' : 'VirtualAppliance'
          nextHopIpAddress: empty(peerGatewayIP) ? null : peerGatewayIP
        }
      }
    ]
  }
}

resource network 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: factoryName
  location: factoryLocation
  properties: {
    addressSpace: {
      addressPrefixes: [ networkConfig.addressPrefix ]
    }
    subnets: [
      {
        name: 'FactorySubnet'
        properties: {
          addressPrefix: cidrSubnet(networkConfig.addressPrefix, 25, 0)
          routeTable: {
            id: routes.id
          }
        }
      }
    ]
  }
}

module peer 'tools/peerNetworks.bicep' = if (!empty(peerNetworkId) && !empty(peerGatewayIP)) {
  name: '${take(deployment().name, 36)}-peer'
  scope: subscription()
  params: {
    HubNetworkId: peerNetworkId
    HubGatewayIP: peerGatewayIP
    SpokeNetworkIds: [network.id]
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'key${uniqueString(resourceGroup().id)}'
  location: factoryLocation
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}

resource vaultSecret_PersonalAccessToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'personal-access-token'
  parent: vault
  properties: {
    value: token
  }
}

resource vaultSecret_RegistryPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'registry-password'
  parent: vault
  properties: {
    value: registry.listCredentials().passwords[0].value
  }
}

resource vaultPE 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: vault.name
  location: factoryLocation
  properties: {
    customNetworkInterfaceName: vault.name
    subnet: {
      id: tools.getSubnetResourceId(network.properties.subnets, 'FactorySubnet')
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'        
        properties: {
          privateLinkServiceId: vault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'sto${uniqueString(resourceGroup().id)}'
  location: factoryLocation
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource storagePE 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: storage.name
  location: factoryLocation
  properties: {
    customNetworkInterfaceName: storage.name
    subnet: {
      id: tools.getSubnetResourceId(network.properties.subnets, 'FactorySubnet')
    }
    privateLinkServiceConnections: [
      {
        name: 'storage'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'acr${uniqueString(resourceGroup().id)}'
  location: factoryLocation
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource registryBuildIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: '${registry.name}-build'
  location: factoryLocation
}

resource registryOwnerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
}

resource registryOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, registryOwnerRoleDefinition.id, registryBuildIdentity.id)
  scope: registry
  properties: {
    principalId: registryBuildIdentity.properties.principalId
    roleDefinitionId: registryOwnerRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: factoryName
  location: factoryLocation
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: factoryName
  location: factoryLocation
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
  }
}

resource runnerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: '${environment.name}-job'
  location: factoryLocation
}

resource registryPullRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
}

resource registryPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, registryPullRoleDefinition.id, runnerIdentity.id)
  scope: registry
  properties: {
    principalId: runnerIdentity.properties.principalId
    roleDefinitionId: registryPullRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}

// =====================================================================================
// GitHub Runner
// =====================================================================================

resource gitHubRunnerImage 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (runnerType == 'GitHub') {
  name: '${registryBuildIdentity.name}-${guid('github', deployment().name)}'
  location: factoryLocation
  dependsOn: [ registryOwnerRoleAssignment ]
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${registryBuildIdentity.id}' : {}
    }
  }
  properties: {
    azCliVersion: '2.26.1'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    scriptContent: 'az acr build --subscription "${subscription().subscriptionId}" --resource-group "${resourceGroup().name}" --registry "${registry.name}" --image "${runnerImage}" --file "Dockerfile.github" "https://github.com/Azure-Samples/container-apps-ci-cd-runner-tutorial.git"'
  }
}

resource gitHubRunnerJob 'Microsoft.App/jobs@2023-05-01' = if (runnerType == 'GitHub') {
  name: 'runner-github'
  location: factoryLocation
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runnerIdentity.id}' : {}
    }
  }
  dependsOn: [ 
    gitHubRunnerImage
  ]
  properties: {
    environmentId: environment.id

    configuration: {

      triggerType: 'Event'
      replicaTimeout: 1800
      replicaRetryLimit: 0            

      eventTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
        scale: {
          minExecutions: 0
          maxExecutions: 10
          pollingInterval: 30
          rules: [
            {
              name: 'github-runner'
              type: 'github-runner'
              auth: [
                {
                  secretRef: 'personal-access-token'
                  triggerParameter: 'personalAccessToken'
                }
              ]
              metadata: {
                githubAPIURL: 'https://api.github.com'
                owner: runnerConfig.owner
                runnerScope: 'repo'
                repos: runnerConfig.repo
                //labels: ['image-factory', toLower(factoryName)]
                targetWorkflowQueueLength: '1'
              }
            }
          ]
        }
      }

      registries: [
        {
          identity: runnerIdentity.id
          server: registry.properties.loginServer
        }
      ]

      secrets: [
        {
          name: 'personal-access-token'
          value: token
        }
      ]
    }

    template: {
      containers: [
        {
          name: 'runner'
          image: '${registry.properties.loginServer}/${runnerImage}'
          env: [
            {
              name: 'GITHUB_PAT'
              secretRef: 'personal-access-token'
            }
            {
              name: 'REPO_URL'
              value: 'https://github.com/${runnerConfig.owner}/${runnerConfig.repo}'
            }
            {
              name: 'REGISTRATION_TOKEN_API_URL'
              value: 'https://api.github.com/repos/${runnerConfig.owner}/${runnerConfig.repo}/actions/runners/registration-token'
            }
          ]
          resources: {
            cpu: 2
            memory: '4Gi'
          }
        }
      ]
    }
    
  }
}

// =====================================================================================
// Azure DevOps Runner
// =====================================================================================

resource azureDevOpsRunnerImage 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (runnerType == 'AzureDevOps') {
  name: '${registryBuildIdentity.name}-${guid('ado', deployment().name)}'
  location: factoryLocation
  dependsOn: [ registryOwnerRoleAssignment ]
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${registryBuildIdentity.id}' : {}
    }
  }
  properties: {
    azCliVersion: '2.26.1'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    scriptContent: 'az acr build --subscription "${subscription().subscriptionId}" --resource-group "${resourceGroup().name}" --registry "${registry.name}" --image "${runnerImage}" --file "Dockerfile.azure-pipelines" "https://github.com/Azure-Samples/container-apps-ci-cd-runner-tutorial.git"'
  }
}

resource azureDevOpsRunnerJob 'Microsoft.App/jobs@2023-05-01' = if (runnerType == 'AzureDevOps') {
  name: 'runner-ado'
  location: factoryLocation
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runnerIdentity.id}' : {}
    }
  }
  dependsOn: [ 
    azureDevOpsRunnerImage
  ]
  properties: {
    environmentId: environment.id

    configuration: {

      triggerType: 'Event'
      replicaTimeout: 1800
      replicaRetryLimit: 0            
      
      eventTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
        scale: {
          minExecutions: 0
          maxExecutions: 10
          pollingInterval: 30
          rules: [
            {
              name: 'azure-pipelines'
              type: 'azure-pipelines'
              auth: [
                {
                  secretRef: 'personal-access-token'
                  triggerParameter: 'personalAccessToken'
                }
                {
                  secretRef: 'organization-url'
                  triggerParameter: 'organizationURL'
                }
              ]
              metadata: {
                poolName: runnerConfig.pool
                targetPipelinesQueueLength: 1
                runnerScope: 'repo'
              }
            }
          ]
        }
      }

      registries: [
        {
          identity: runnerIdentity.id
          server: registry.properties.loginServer
        }
      ]

      secrets: [
        {
          name: 'personal-access-token'
          value: token
        }
        {
          name: 'organization-url'
          value: 'https://dev.azure.com/${runnerConfig.organization}'
        }
      ]
    }

    template: {
      containers: [
        {
          name: 'runner'
          image: '${registry.properties.loginServer}/${runnerImage}'
          env: [
            {
              name: 'AZP_TOKEN'
              secretRef: 'personal-access-token'
            }
            {
              name: 'AZP_URL'
              secretRef: 'organization-url'
            }
            {
              name: 'AZP_POOL'
              value: runnerConfig.pool
            }
          ]
          resources: {
            cpu: 2
            memory: '4Gi'
          }
        }
      ]
    }
    
  }
}


output factoryInfo object = {
  subscription: subscription().subscriptionId
  region: factoryLocation
	identity: identity.id
  network: network.id
  vault: vault.id
} 
