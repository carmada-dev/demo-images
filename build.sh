#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

usage() { 
	echo "======================================================================================"
	echo "Usage: $0"
	echo "======================================================================================"
	echo " -g [REQUIRED] 	The resource id of the target compute gallery"
	echo " -i [OPTIONAL] 	The name of the image to build"
	echo " -p [OPTIONAL] 	The name of the publisher of the image"
	echo " -o [OPTIONAL] 	The name of the offer of the image"
	echo " -s [OPTIONAL] 	The name of the SKU of the image"
	echo " -d [FLAG] 		Enable debug mode for Packer"
	exit 1; 
}

displayHeader() {
	echo -e "\n======================================================================================"
	echo $1
	echo -e "======================================================================================\n"
}

while getopts 'g:i:p:o:s:rd' OPT; do
    case "$OPT" in
		g)
			GALLERYID="${OPTARG}" ;;
		i)
			IMAGE="${OPTARG}" ;;
		p)
			IMAGEPUBLISHER="${OPTARG}" ;;
		o)
			IMAGEOFFER="${OPTARG}" ;;
		s)
			IMAGESKU="${OPTARG}" ;;
		d)  
			PACKER_LOG='on' ;;
		*) 
			usage ;;
    esac
done

clear

buildImage() {

	# IMAGENAME=$(basename "$(dirname "$1")")
	# IMAGEVERSION=$(date +%Y.%m%d.%H%M)

	# GALLERYJSON=$(az resource show --ids $GALLERYID)
	# GALLERYNAME=$(echo $GALLERYJSON | jq -r .name)
	# GALLERYRESOURCEGROUP=$(echo $GALLERYJSON | jq -r .resourceGroup)
	# GALLERYRELOCATION=$(echo $GALLERYJSON | jq -r .location)
	# GALLERYSUBSCRIPTION=$(echo $GALLERYID | cut -d / -f3)

	# if [ -z "$IMAGEPUBLISHER" ]; then
	# 	IMAGEPUBLISHER="$GALLERYNAME"
	# fi

	# if [ -z "$IMAGEOFFER" ]; then
	# 	IMAGEOFFER=$(json2hcl -reverse < "$1" | jq --raw-output '[.. | ."offer"? | select(. != null)][0]')
	# fi

	# if [ -z "$IMAGESKU" ]; then
	# 	IMAGESKU=$(json2hcl -reverse < "$1" | jq --raw-output '[.. | ."sku"? | select(. != null)][0]')
	# fi

	pushd "$(dirname "$1")" > /dev/null

	rm -f ./image.pkr.log

	# COUNT=$(az sig image-definition list --subscription $GALLERYSUBSCRIPTION --resource-group $GALLERYRESOURCEGROUP --gallery-name $GALLERYNAME --query "[?name=='$IMAGENAME'] | length(@)")

	# if [ $COUNT == 0 ]; then

	# 	displayHeader "Create image definition $1" | tee -a ./image.pkr.log

	# 	az sig image-definition create \
	# 		--subscription $GALLERYSUBSCRIPTION \
	# 		--resource-group $GALLERYRESOURCEGROUP \
	# 		--gallery-name $GALLERYNAME \
	# 		--gallery-image-definition $IMAGENAME \
	# 		--publisher $IMAGEPUBLISHER \
	# 		--offer $IMAGEOFFER \
	# 		--sku $IMAGESKU \
	# 		--os-type Windows \
	# 		--os-state Generalized \
	# 		--hyper-v-generation V2 \
	# 		--features 'SecurityType=TrustedLaunch' \
	# 		--only-show-errors | tee -a ./image.pkr.log

	# fi

	displayHeader "Init image $1" | tee -a ./image.pkr.log

	packer init \
		. 2>&1 | tee -a ./image.pkr.log

	displayHeader "Building image $1" | tee -a ./image.pkr.log

	packer build \
		-force \
		-color=false \
		-timestamp-ui \
		. 2>&1 | tee -a ./image.pkr.log

		# -var "galleryName=$GALLERYNAME" \
		# -var "galleryResourceGroup=$GALLERYRESOURCEGROUP" \
		# -var "gallerySubscription=$GALLERYSUBSCRIPTION" \
		# -var "galleryLocation=$GALLERYRELOCATION" \
		# -var "imageName=$IMAGENAME" \
		# -var "imageVersion=$IMAGEVERSION" \
		# . 2>&1 | tee -a ./image.pkr.log

	popd > /dev/null
}

# pushd "/usr/local/bin" > /dev/null

# if [ ! -f "/usr/local/bin/json2hcl" ]; then
# 	VERSION=$(curl --silent "https://api.github.com/repos/kvz/json2hcl/releases/latest" | jq -r ".tag_name")
# 	wget -c "https://github.com/kvz/json2hcl/releases/download/$VERSION/json2hcl_0.1.1_linux_amd64.tar.gz" -q -O - | tar -xz json2hcl
# fi

# sudo chmod 755 ./json2hcl 

# popd > /dev/null

while read IMAGEPATH; do

	if [[ -z "$IMAGE" || "$(echo "$IMAGE" | tr '[:upper:]' '[:lower:]')" == "$(echo "$(basename $(dirname $IMAGEPATH))" | tr '[:upper:]' '[:lower:]')" ]]; then

		cp -f ./_core/config.pkr.hcl $(dirname $IMAGEPATH)/config.pkr.hcl
		cp -f ./_core/build.pkr.hcl $(dirname $IMAGEPATH)/build.pkr.hcl
		cp -f ./_core/variables.pkr.hcl $(dirname $IMAGEPATH)/variables.pkr.hcl

		# start the build process
		buildImage $IMAGEPATH

	fi

	rm -f $(dirname $IMAGEPATH)/variables.pkr.hcl
	rm -f $(dirname $IMAGEPATH)/build.pkr.hcl
	rm -f $(dirname $IMAGEPATH)/config.pkr.hcl

done < <(find . -type f -path './*/image.pkr.hcl')
