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

while getopts 'i:' OPT; do
    case "$OPT" in
		i)
			IMAGE="${OPTARG}" ;;
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

	IMAGESUFFIX="$(whoami | tr '[:lower:]' '[:upper:]')"
	IMAGENAME="$(basename "$(dirname "$1")")-$IMAGESUFFIX"

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
		--features 'SecurityType=TrustedLaunch' \
		--only-show-errors | tee -a ./image.pkr.log

	displayHeader "Initializing Image ($1)" | tee -a ./image.pkr.log

	packer init \
		. 2>&1 | tee -a ./image.pkr.log

	displayHeader "Building Image ($1)" | tee -a ./image.pkr.log

	packer build \
		-force \
		-color=false \
		-timestamp-ui \
		-var "imageSuffix=$IMAGESUFFIX" \
		. 2>&1 | tee -a ./image.pkr.log

	COMPUTEGALLERY_IMAGEID=$(tail -n 15 ./image.pkr.log | grep 'ManagedImageSharedImageGalleryId: ' | cut -d ' ' -f 2-)
	COMPUTEGALLERY_RESOURCEID=$(echo $COMPUTEGALLERY_IMAGEID | cut -d '/' -f -9)
	DEVCENTERGALLERY_RESOURCEID=$(az devcenter admin gallery list --subscription $(echo $DEVCENTERJSON | jq --raw-output '.subscription') --resource-group $(echo $DEVCENTERJSON | jq --raw-output '.resourceGroup') --dev-center $(echo $DEVCENTERJSON | jq --raw-output '.name') | jq --raw-output ".[] | select(.galleryResourceId == \"$COMPUTEGALLERY_RESOURCEID\") | .id")
	DEVCENTERGALLERY_IMAGEID="$DEVCENTERGALLERY_RESOURCEID/$(echo "echo $COMPUTEGALLERY_IMAGEID" | cut -d '/' -f 10-)"

	displayHeader "Updating DevBox Definition ($1)" | tee -a ./image.pkr.log

	az devcenter admin devbox-definition create \
		--dev-box-definition-name $IMAGENAME \
		--subscription $(echo $DEVCENTERJSON | jq --raw-output '.subscription') \
		--resource-group $(echo $DEVCENTERJSON | jq --raw-output '.resourceGroup') \
		--dev-center $(echo $DEVCENTERJSON | jq --raw-output '.name') \
		--image-reference id="$DEVCENTERGALLERY_IMAGEID" \
		--os-storage-type $(echo $DEVCENTERJSON | jq --raw-output '.storage') \
		--sku name="$(echo $DEVCENTERJSON | jq --raw-output '.compute')" \
		--no-wait \
		--only-show-errors 2>&1 | tee -a ./image.pkr.log

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
