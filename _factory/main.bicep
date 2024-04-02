targetScope = 'subscription'

param config object

@secure()
param token string

param reset bool = false

var factoryName = config.name
var factoryLocation = config.location

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'FAC-${factoryName}'
  location: factoryLocation
}

module resources './resources.bicep' = if (!reset) {
  name: '${take(deployment().name, 36)}-resources'
  scope: resourceGroup
  params: {
    config: config
    token: token
  }
}

output factoryHome string = resourceGroup.name
output factoryInfo object = reset ? {} : resources.outputs.factoryInfo
