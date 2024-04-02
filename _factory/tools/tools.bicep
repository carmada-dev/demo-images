@export()
func convertAddressPrefixToInt(addressPrefix string) int =>
  int('${join(map(split(split(addressPrefix, '/')[0], '.'), item => padLeft(item, 3, '0')), '')}${padLeft(split(addressPrefix, '/')[1], 2, '0')}')

@export()
func getLocationName(location string) string => 
  toLower(replace(location, ' ', ''))

@export()
func getLocationDisplayName(locationMap object, location string, removeBlanks bool) string => 
  contains(locationMap, getLocationName(location)) ? replace(filter(items(locationMap), item => item.key == getLocationName(location))[0].value, (removeBlanks ? ' ' : '') , '') : replace(location, (removeBlanks ? ' ' : '') , '')

@export()
func removeProperties(obj object, propertyNames array) object =>
  reduce(filter(items(obj), item => !contains(propertyNames, item.key)), {}, (curr, next) => union(curr, { '${next.key}': next.value }))

@export()
func getSubscriptionId(resourceId string) string => 
  split(resourceId, '/')[2]

@export()
func getResourceGroupName(resourceId string) string => 
  split(resourceId, '/')[4]

@export()
func getResourceName(resourceId string) string => 
  last(split(resourceId, '/'))

@export()
func getSubnetAddressPrefix(subnets array, subnetName string) string =>
  filter(subnets, subnet => subnet.name == subnetName)[0].properties.addressPrefix

@export()
func getSubnetIndex(subnets array, subnetName string) int =>
  indexOf(map(subnets, subnet => subnet.name), subnetName)

@export()
func getSubnetResourceId(subnets array, subnetName string) string =>
  subnets[getSubnetIndex(subnets, subnetName)].id


      