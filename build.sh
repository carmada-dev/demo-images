#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

usage() { 
	echo "======================================================================================"
	echo "Usage: $0"
	echo "======================================================================================"
	echo " -i [OPTIONAL] 	The name of the image to build"
	echo " -p [OPTIONAL]	The name of the project to create a DevBox based on the new image"
	echo " -u [OPTIONAL]	The user principal name of the DevBox owner"
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
		p)
			PROJECT="${OPTARG}" ;;
		u)
			USER="$(az ad user show --id ${OPTARG} --query id -o tsv | dos2unix)" ;;
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
	IMAGEJSON="$(echo "jsonencode(local)" | packer console ./ | jq | tee -a ./image.log)"
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
	packer init \
		. 2>&1 | tee -a ./image.log

	displayHeader "Building Image ($1)" | tee -a ./image.log
	packer build \
		-force \
		-color=false \
		-timestamp-ui \
		-var "imageName=$IMAGENAME" \
		-var "imageSuffix=$IMAGESUFFIX" \
		-var "imageVersion=$IMAGEVERSION" \
		. 2>&1 | tee -a ./image.log

	IMAGEID=$(tail -n 15 ./image.log | grep 'ManagedImageSharedImageGalleryId: ' | cut -d ' ' -f 2-)

	if [ ! -z "$IMAGEID" ]; then

		COMPUTEGALLERY_RESOURCEID=$(echo $IMAGEID | cut -d '/' -f -9)
		DEVCENTERGALLERY_RESOURCEID=$(az devcenter admin gallery list --subscription $(echo $IMAGEJSON | jq --raw-output '.devCenter.subscription') --resource-group $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.resourceGroup') --dev-center $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.name') | jq --raw-output ".[] | select(.galleryResourceId == \"$COMPUTEGALLERY_RESOURCEID\") | .id")
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

		if [ -n "$PROJECT" ]; then

			displayHeader "Creation DevBox Instance ($1)" | tee -a ./image.log
			PROJECTJSON=$(az devcenter admin project list \
				--query "[?starts_with(devCenterId, '/subscriptions/$(echo $IMAGEJSON | jq --raw-output '.image.devCenter.subscription')/') && ends_with(devCenterId, '/$(echo $IMAGEJSON | jq --raw-output '.image.devCenter.name')') && name == '$PROJECT'] | [0]" 
				--output tsv | dos2unix)

			if [ -n "$PROJECTJSON" ]; then
			
				POOLJSON=$(az devcenter admin pool list \
					--subscription $(echo $PROJECTJSON | jq --raw-output '.id | split("/")[2]') \
					--resource-group $(echo $PROJECTJSON | jq --raw-output '.id | split("/")[4]') \
					--project-name $PROJECT \
					--query "[?name == '$IMAGENAME'] | [0]" \
					--output tsv | dos2unix)

				if [ -n "$POOLJSON" ]; then

					POOLJSON=$(az devcenter admin pool create \
						--subscription $(echo $PROJECTJSON | jq --raw-output '.id | split("/")[2]') \
						--resource-group $(echo $PROJECTJSON | jq --raw-output '.id | split("/")[4]') \
						--location $(echo $PROJECTJSON | jq --raw-output '.location') \
						--pool-name $IMAGENAME \
						--project-name $PROJECT \
						--devbox-definition-name $IMAGENAME \
						--network-connection-name $PROJECT \
						--local-administrator "Enabled" \
						--only-show-errors | tee -a ./image.log)
				
				fi

				az devcenter admin devbox-definition wait \
					--ids $(echo $DEFINITIONJSON | jq --raw-output '.id') \
					--custom "imageValidationStatus!='Succeeded'" \
					--only-show-errors \
					--output none 

				az devcenter dev dev-box create \
					--subscription $(echo $PROJECTJSON | jq --raw-output '.id | split("/")[2]') \
					--dev-center-name $(echo $IMAGEJSON | jq --raw-output '.image.devCenter.name') \
					--project-name $PROJECT \
					--pool-name $(echo $POOLJSON | jq --raw-output '.name') \
					--dev-box-name "$IMAGENAME-$(echo $IMAGEVERSION | tr "." "-")" \
					--user-id $USER \
					--no-wait

			fi
		fi
	fi

	popd > /dev/null
}

displayHeader "Ensure DevCenter Extension"
az extension add --name devcenter --upgrade --yes 

while read IMAGEPATH; do

	if [[ -z "$IMAGE" || "$(echo "$IMAGE" | tr '[:upper:]' '[:lower:]')" == "$(echo "$(basename $(dirname $IMAGEPATH))" | tr '[:upper:]' '[:lower:]')" ]]; then

		find ./_core -type f -name '*.pkr.hcl' -exec sh -c "cp -f {} $(dirname $IMAGEPATH)/" \;

		buildImage $IMAGEPATH
	fi

	find ./_core -type f -name '*.pkr.hcl' -exec sh -c "rm -f $(dirname $IMAGEPATH)/$(basename {})" \;

done < <(find . -type f -path './*/image.json')
