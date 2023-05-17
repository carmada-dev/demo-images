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

while getopts 'g:i:p:o:s:rd' OPT; do
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

	rm -f ./image.pkr.log

	displayHeader "Init image $1" | tee -a ./image.pkr.log

	packer init \
		. 2>&1 | tee -a ./image.pkr.log

	displayHeader "Building image $1" | tee -a ./image.pkr.log

	packer build \
		-force \
		-color=false \
		-timestamp-ui \
		. 2>&1 | tee -a ./image.pkr.log

	popd > /dev/null
}

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
