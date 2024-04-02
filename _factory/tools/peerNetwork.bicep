// import * as tools from 'tools.bicep'
targetScope = 'resourceGroup'

param LocalVirtualNetworkName string
param RemoteVirtualNetworkId string
param RemoteGatewayIP string = ''
param PeeringPrefix string 

resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: LocalVirtualNetworkName
}

resource peerVirtualNetwork 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = {
  name: '${PeeringPrefix}-${guid(vnet.id, RemoteVirtualNetworkId)}'
  parent: vnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false 
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: RemoteVirtualNetworkId
    }
  }
}

resource routes 'Microsoft.Network/routeTables@2022-09-01' existing = {
  name: vnet.name
} 

resource route 'Microsoft.Network/routeTables/routes@2022-07-01' = if (!empty(RemoteGatewayIP)) {
  name: 'default'
  parent: routes
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: RemoteGatewayIP
  }
}
