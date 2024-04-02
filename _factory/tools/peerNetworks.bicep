import * as tools from './tools.bicep'
targetScope = 'subscription'

param HubNetworkId string
param HubGatewayIP string = ''
param HubPeeringPrefix string = 'Hub'
param SpokeNetworkIds array
param SpokePeeringPrefix string = 'Spoke'
param OperationId string = guid(deployment().name)

module peerHub2Spoke 'peerNetwork.bicep' = [for i in range(0, length(SpokeNetworkIds)): {
  name: '${take(deployment().name, 36)}_${uniqueString(HubPeeringPrefix, HubNetworkId, SpokePeeringPrefix, SpokeNetworkIds[i], OperationId)}'
  scope: resourceGroup(split(HubNetworkId, '/')[2], split(HubNetworkId, '/')[4])
  params: {
    LocalVirtualNetworkName: tools.getResourceName(HubNetworkId)
    RemoteVirtualNetworkId: SpokeNetworkIds[i]
    PeeringPrefix: SpokePeeringPrefix
  }
}]

module peerSpoke2Hub 'peerNetwork.bicep' = [for i in range(0, length(SpokeNetworkIds)): {
  name: '${take(deployment().name, 36)}_${uniqueString(SpokePeeringPrefix, SpokeNetworkIds[i], HubPeeringPrefix, HubNetworkId, OperationId)}'
  scope: resourceGroup(split(SpokeNetworkIds[i], '/')[2], split(SpokeNetworkIds[i], '/')[4])
  params: {
    LocalVirtualNetworkName: tools.getResourceName(SpokeNetworkIds[i]) 
    RemoteVirtualNetworkId: HubNetworkId
    RemoteGatewayIP: HubGatewayIP
    PeeringPrefix: HubPeeringPrefix
  }
}]

