#!/bin/bash

usage() { 
	echo "======================================================================================"
	echo "Usage: $0"
	echo "======================================================================================"
	echo " -s [OPTIONAL] 	The target subscription's name or id"
	exit 1; 
}

SUBSCRIPTION="$(az account show --query id -o tsv)"

while getopts 's:' OPT; do
    case "$OPT" in
		s)
			SUBSCRIPTION="${OPTARG}" ;;
		*) 
			usage ;;
    esac
done

clear

while read RESOURCEGROUP; do

	echo "Deleting resource group '$RESOURCEGROUP' ..."
	az group delete --resource-group $RESOURCEGROUP --force-deletion-types 'Microsoft.Compute/virtualMachines' --no-wait --yes

done < <(az group list --subscription "$SUBSCRIPTION" --query "[?starts_with(name, 'PKR-')].name" -o tsv)