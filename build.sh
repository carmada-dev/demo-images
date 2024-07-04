#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

usage() { 
	echo "======================================================================================"
	echo "Usage: $0"
	echo "======================================================================================"
	echo " -i [OPTIONAL] 	The name of the image to build"
	exit 1; 
}

displayHeader() {
	echo -e "\n======================================================================================"
	echo $1
	echo -e "======================================================================================\n"
}

IMAGEVERSION="$(date '+%Y.%m%d.%H%M')"
PROJECT=""
USER="me"

while getopts 'i:p:u:' OPT; do
    case "$OPT" in
		i)
			IMAGE="${OPTARG}" ;;
		*) 
			usage ;;
    esac
done

clear

buildImage() {

	pushd "$(dirname "$1")" > /dev/null

	rm -f ./image.log

	displayHeader "Read Image Definition ($1)" | tee -a ./image.log
	IMAGESUFFIX="$(uname -n | tr '[:lower:]' '[:upper:]')"
	IMAGENAME="$(basename "$(dirname "$1")")-$(whoami | tr '[:lower:]' '[:upper:]')"
	IMAGEJSON="$(echo "jsonencode(local)" | packer console ../_packer/ | jq | tee -a ./image.log)"
	echo "$IMAGEJSON" | jq .

	displayHeader "Switch subscription context" | tee -a ./image.log
	az account set --subscription $(echo "$IMAGEJSON" | jq --raw-output '.factory.subscription') | tee -a ./image.log
	
	displayHeader "Ensure Image Definition ($1)" | tee -a ./image.log
	az sig image-definition create \
		--subscription $(echo "$IMAGEJSON" | jq --raw-output '.image.gallery.subscription') \
		--resource-group $(echo "$IMAGEJSON" | jq --raw-output '.image.gallery.resourceGroup') \
		--gallery-name $(echo "$IMAGEJSON" | jq --raw-output '.image.gallery.name') \
		--gallery-image-definition $IMAGENAME \
		--publisher $(whoami) \
		--offer $(echo "$IMAGEJSON" | jq --raw-output '.image.offer') \
		--sku $(echo "$IMAGEJSON" | jq --raw-output '.image.sku') \
		--os-type Windows \
		--os-state Generalized \
		--hyper-v-generation V2 \
		--features 'IsHibernateSupported=true SecurityType=TrustedLaunch' \
		--only-show-errors | tee -a ./image.log

	displayHeader "Initializing Image ($1)" | tee -a ./image.log
	packer init ../_packer/ 2>&1 | tee -a ./image.log
	packer init --upgrade ../_packer/ 2>&1 | tee -a ./image.log

	displayHeader "Building Image ($1)" | tee -a ./image.log
	packer build \
		-force \
		-color=false \
		-timestamp-ui \
		-var "imageName=$IMAGENAME" \
		-var "imageSuffix=$IMAGESUFFIX" \
		-var "imageVersion=$IMAGEVERSION" \
		../_packer/ 2>&1 | tee -a ./image.log

	IMAGEID=$(tail -n 15 ./image.log | grep 'ManagedImageSharedImageGalleryId: ' | cut -d ' ' -f 2-)

	if [ ! -z "$IMAGEID" ]; then

		COMPUTEGALLERY_RESOURCEID=$(echo $IMAGEID | cut -d '/' -f -9)
		DEVCENTERGALLERY_RESOURCEID=$(az devcenter admin gallery list --subscription $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.subscription') --resource-group $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.resourceGroup') --dev-center $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.name') | jq --raw-output ".[] | select(.galleryResourceId == \"$COMPUTEGALLERY_RESOURCEID\") | .id")
		DEVCENTERGALLERY_IMAGEID="$DEVCENTERGALLERY_RESOURCEID/$(echo "echo $IMAGEID" | cut -d '/' -f 10-)"

		displayHeader "Updating DevBox Definition ($1)" | tee -a ./image.log
		DEFINITIONJSON=$(az devcenter admin devbox-definition create \
			--devbox-definition-name $IMAGENAME \
			--subscription $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.subscription') \
			--resource-group $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.resourceGroup') \
			--dev-center $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.name') \
			--image-reference id="$DEVCENTERGALLERY_IMAGEID" \
			--os-storage-type $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.storage') \
			--sku name="$(echo $IMAGEJSON | jq --raw-output '.image.devCenter.compute')" \
			--only-show-errors | tee -a ./image.log)

	fi

	popd > /dev/null
}

displayHeader "Ensure DevCenter Extension"
az extension add --name devcenter --upgrade --yes 

while read IMAGEPATH; do

	[[ -z "$IMAGE" || "$(echo "$IMAGE" | tr '[:upper:]' '[:lower:]')" == "$(echo "$(basename $(dirname $IMAGEPATH))" | tr '[:upper:]' '[:lower:]')" ]] && buildImage $IMAGEPATH

done < <(find . -type f -path './*/image.json')
