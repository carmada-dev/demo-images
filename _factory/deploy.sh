#!/bin/bash

usage() { 
	echo "======================================================================================"
	echo "Usage: $0"
	echo "======================================================================================"
	echo " -c [REQUIRED] 	Configuration file"
	echo " -t [REQUIRED] 	GitHub Access token (req scope: repo, read:org, manage_runners:org)"
	echo " -r [OPTIONAL] 	Reset the factory"
	echo " -b [OPTIONAL] 	Build only - convert bicep to ARM template"
	echo "======================================================================================"
	exit 1; 
}

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
RESET=false
BUILD=false

while getopts 'c:t:rb' OPT; do
    case "$OPT" in
		c)
			CONFIGURATIONFILE="${OPTARG}" ;;
		t)
			TOKEN="${OPTARG}" ;;
		r)
			RESET=true ;;
		b)
			BUILD=true ;;
		*) 
			usage ;;
    esac
done

SUBSCRIPTIONID="$(jq -r .subscription $CONFIGURATIONFILE)"
LOCATION="$(jq -r .location $CONFIGURATIONFILE)"
PARAMETERS="config=@$CONFIGURATIONFILE token=$TOKEN"

if $BUILD; then
	echo "Building factory to JSON ($SCRIPT_DIR/main.json) ..."
	az bicep build --file ./main.bicep --outfile ./main.json
	exit 0
fi

if $RESET; then

	echo "Resolving factory home in $SUBSCRIPTIONID ..."
	RESOURCEGROUP=$(az deployment sub create \
		--subscription $SUBSCRIPTIONID \
		--name $(uuidgen) \
		--location $LOCATION \
		--template-file ./main.bicep \
		--only-show-errors \
		--parameters $PARAMETERS reset=true \
		--output tsv \
		--query "properties.outputs.factoryHome.value" | dos2unix)

	echo "Deleting factory home in $SUBSCRIPTIONID ($RESOURCEGROUP) ..."
	az group delete \
		--subscription $SUBSCRIPTIONID \
		--name $RESOURCEGROUP \
		--yes \
		--force-deletion-types Microsoft.Compute/virtualMachineScaleSets \
		--output none

fi

echo "Purging deleted resources in $SUBSCRIPTIONID ..."
for KEYVAULT in $(az keyvault list-deleted --subscription $SUBSCRIPTIONID --resource-type vault --query "[].name" -o tsv 2>/dev/null | dos2unix); do
	echo "- KeyVault '$KEYVAULT' ..." 
	az keyvault purge --subscription $SUBSCRIPTIONID --name $KEYVAULT -o none & 
done; wait

echo "Deploying factory in $SUBSCRIPTIONID ($CONFIGURATIONFILE) ..."
az deployment sub create \
	--subscription $SUBSCRIPTIONID \
	--name $(uuidgen) \
	--location $LOCATION \
	--template-file ./main.bicep \
	--only-show-errors \
	--parameters $PARAMETERS

