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

ensureJson2Hcl() {
	pushd "/usr/local/bin" > /dev/null
	if [ ! -f "/usr/local/bin/json2hcl" ]; then
		VERSION=$(curl --silent "https://api.github.com/repos/kvz/json2hcl/releases/latest" | jq -r ".tag_name")
		wget -c "https://github.com/kvz/json2hcl/releases/download/$VERSION/json2hcl_0.1.1_linux_amd64.tar.gz" -q -O - | sudo tar -xz json2hcl
	fi
	sudo chmod 755 ./json2hcl 
	popd > /dev/null
}

getGalleryConfiguration() {
	ensureJson2Hcl
	echo "$(json2hcl -reverse < "$1" | jq --raw-output '[.. | ."gallery"? | select(. != null)][0][0]')"
}

getImageConfiguration() {
	ensureJson2Hcl
	echo "$(json2hcl -reverse < "$1" | jq --raw-output '[.. | ."image"? | select(. != null)][0][0]')"
}

getDevCenterConfiguration() {
	ensureJson2Hcl
	echo "$(json2hcl -reverse < "$1" | jq --raw-output '[.. | ."devCenter"? | select(. != null)][0][0]')"
}

buildImage() {

	IMAGESUFFIX="$(uname -n | tr '[:lower:]' '[:upper:]')"
	IMAGENAME="$(basename "$(dirname "$1")")-$(whoami | tr '[:lower:]' '[:upper:]')"

	GALLERYJSON=$(getGalleryConfiguration "$1")
	IMAGEJSON=$(getImageConfiguration "$1")
	DEVCENTERJSON=$(getDevCenterConfiguration "$1")

	pushd "$(dirname "$1")" > /dev/null

	rm -f ./image.pkr.log

	displayHeader "Ensure Image Definition ($1)" | tee -a ./image.pkr.log

	az sig image-definition create \
		--subscription $(echo "$GALLERYJSON" | jq --raw-output '.subscription') \
		--resource-group $(echo "$GALLERYJSON" | jq --raw-output '.resourceGroup') \
		--gallery-name $(echo "$GALLERYJSON" | jq --raw-output '.name') \
		--gallery-image-definition $IMAGENAME \
		--publisher $(whoami) \
		--offer $(echo "$IMAGEJSON" | jq --raw-output '.offer') \
		--sku $(echo "$IMAGEJSON" | jq --raw-output '.sku') \
		--os-type Windows \
		--os-state Generalized \
		--hyper-v-generation V2 \
		--features 'IsHibernateSupported=true SecurityType=TrustedLaunch' \
		--only-show-errors | tee -a ./image.pkr.log

	displayHeader "Initializing Image ($1)" | tee -a ./image.pkr.log

	packer init \
		. 2>&1 | tee -a ./image.pkr.log

	displayHeader "Building Image ($1)" | tee -a ./image.pkr.log

	packer build \
		-force \
		-color=false \
		-timestamp-ui \
		-var "imageName=$IMAGENAME" \
		-var "imageSuffix=$IMAGESUFFIX" \
		-var "imageVersion=$IMAGEVERSION" \
		. 2>&1 | tee -a ./image.pkr.log

	IMAGEID=$(tail -n 15 ./image.pkr.log | grep 'ManagedImageSharedImageGalleryId: ' | cut -d ' ' -f 2-)

	if [ ! -z "$IMAGEID" ]; then

		COMPUTEGALLERY_RESOURCEID=$(echo $IMAGEID | cut -d '/' -f -9)
		DEVCENTERGALLERY_RESOURCEID=$(az devcenter admin gallery list --subscription $(echo $DEVCENTERJSON | jq --raw-output '.subscription') --resource-group $(echo $DEVCENTERJSON | jq --raw-output '.resourceGroup') --dev-center $(echo $DEVCENTERJSON | jq --raw-output '.name') | jq --raw-output ".[] | select(.galleryResourceId == \"$COMPUTEGALLERY_RESOURCEID\") | .id")
		DEVCENTERGALLERY_IMAGEID="$DEVCENTERGALLERY_RESOURCEID/$(echo "echo $IMAGEID" | cut -d '/' -f 10-)"

		displayHeader "Updating DevBox Definition ($1)" | tee -a ./image.pkr.log

		DEFINITIONJSON=$(az devcenter admin devbox-definition create \
			--devbox-definition-name $IMAGENAME \
			--subscription $(echo $DEVCENTERJSON | jq --raw-output '.subscription') \
			--resource-group $(echo $DEVCENTERJSON | jq --raw-output '.resourceGroup') \
			--dev-center $(echo $DEVCENTERJSON | jq --raw-output '.name') \
			--image-reference id="$DEVCENTERGALLERY_IMAGEID" \
			--os-storage-type $(echo $DEVCENTERJSON | jq --raw-output '.storage') \
			--sku name="$(echo $DEVCENTERJSON | jq --raw-output '.compute')" \
			--no-wait \
			--only-show-errors | tee -a ./image.pkr.log)

		if [ -n "$PROJECT" ]; then

			displayHeader "Creation DevBox Instance ($1)" | tee -a ./image.pkr.log

			PROJECTJSON=$(az devcenter admin project list \
				--query "[?starts_with(devCenterId, '/subscriptions/$(echo $DEVCENTERJSON | jq --raw-output '.subscription')/') && ends_with(devCenterId, '/$(echo $DEVCENTERJSON | jq --raw-output '.name')') && name == '$PROJECT'] | [0]" 
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
						--only-show-errors | tee -a ./image.pkr.log)
				
				fi

				az devcenter admin devbox-definition wait \
					--ids $(echo $DEFINITIONJSON | jq --raw-output '.id') \
					--custom "imageValidationStatus!='Succeeded'" \
					--only-show-errors \
					--output none 

				az devcenter dev dev-box create \
					--subscription $(echo $PROJECTJSON | jq --raw-output '.id | split("/")[2]') \
					--dev-center-name $(echo $DEVCENTERJSON | jq --raw-output '.name') \
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

done < <(find . -type f -path './*/image.pkr.hcl')
