#!/bin/bash
#
set -e

# Defaults:
# firmware
# https://github.com/DarkFlippers/unleashed-firmware
FW="DarkFlippers/unleashed-firmware"
# release
REL="latest"
# development build data
DD="https://up.unleashedflip.com/directory.json"

# firmware variant:
# ""  - 3 custom animations, and default apps preinstalled (base pack)
# "c" - 3 custom animations, and only main apps (Clean build like latest OFW)
# "n" - only official flipper animations, and base pack apps
# "e" - custom animations, extra apps pack preinstalled, and base pack apps too
# "r" - RGB patch (+ extra apps) for flippers with rgb hw backlight mod
VARIANT="e"
FORCE=0
DEVBUILD=0

# socat params
SP="crnl,raw,echo=0,b115200"

MYNAME=$(basename $0)
usage(){
	echo "${MYNAME} - Flipper Zero firmware update script"
	echo "usage: ${MYNAME} [options] [command]"
	echo "  commands:"
	echo "    check          - check for update"
	echo "    update         - update firmware"
	echo "    install <file> - install from local file"
	echo "    list           - list devices"
	echo "    rel            - list available releases"
	echo "    cli            - open interactive cli"
	echo "  options:"
	echo "    -f            - force update"
	echo "    -d <device>   - specify flipper device manually (default - auto)"
	echo "    -v <variant>  - release variant (default - \"e\")"
	echo "    -r <release>  - firmware release (default - latest)"
	echo "    -D            - latest development build"
	exit
}

#check for the gear
gear(){
	for tool in awk curl jq socat python3 ; do
		if [[ -z  "$(command -v ${tool})" ]]; then
			echo "-err: ${tool} not found"
			exit 1
		fi
	done
}

# use python scripts from firmware, until storage functions implenemted in bash
get_scripts(){
	if [[ ! -d scripts ]]; then
		echo "- scripts dir not found, getting it..."
		rm -f release.zip
		curl --fail --silent --show-error -LO  https://github.com/${FW}/archive/refs/heads/release.zip
		unzip -q release.zip 'unleashed-firmware-release/scripts/*'
		mkdir scripts
		mv unleashed-firmware-release/scripts/storage.py scripts/
		mv unleashed-firmware-release/scripts/flipper/ scripts/
		rm -rf unleashed-firmware-release release.zip
	fi
}

get_releases(){
	echo "+ getting available releases..."
	if [[ ${DEVBUILD} == "0" ]]; then
		curl --fail --silent --show-error https://api.github.com/repos/${FW}/releases | jq -r '.[] | .name + " " + .published_at'
	else
		echo "+ for dev build..."
		DJS=$(curl -s "${DD}" | jq -r '.channels[] | select(.id=="development") | .versions[].files[] | select(.type=="full_json") | .url')
		curl -s "$DJS" | jq -r '.firmware_version + " " + .firmware_build_date'
	fi
}

get_release_info(){
	echo "+ getting release info..."
	if [[ "${DEVBUILD}" == "0" ]]; then
		# release info
		if [[ "${REL}" == "latest" ]]; then
			LR=$(curl --fail --silent --show-error https://api.github.com/repos/${FW}/releases/${REL})
		else
			LR=$(curl --fail --silent --show-error https://api.github.com/repos/${FW}/releases | jq -r ".[] | select(.name==\"${REL}\") | .url")
			LR=$(curl --fail --silent --show-error ${LR})
		fi
		# release name
		RN=$(echo "${LR}" | jq -r '.name')
		# release date
		RD=$(echo "${LR}" | jq -r '.published_at')
		# release variant
		RV="${RN}${VARIANT}"
		# download url
		DL=$(echo "${LR}" | jq -r '.assets[] | .browser_download_url' | grep "${RV}.tgz$")
		# filename
		FN=$(echo ${DL} | awk -F/ '{print $NF}')
		# dirname
		DN=$(echo ${FN} | sed -e 's/^flipper-z-//' -e 's/.tgz$//')
	else
		echo "+ for dev build..."
		if [[ "${REL}" != "latest" ]]; then
			echo "- not latest, need to guess, will do it later some day"
			exit
		fi
		DJS=$(curl -s "${DD}" | jq -r '.channels[] | select(.id=="development") | .versions[].files[] | select(.type=="full_json") | .url')
		# release info
		LR=$(curl -s "$DJS")
		# release name
		RN=$(echo "${LR}" | jq -r '.firmware_version')
		RD=$(echo "${LR}" | jq -r '.firmware_build_date')
		# release variant
		RV="${RN}${VARIANT}"
		# release date
                RD=$(echo "${LR}" | jq -r '.firmware_build_date')
		RD=$(echo "$RD" | awk -F- '{print $3 "-" $2 "-" $1}')
		# download url
                DL=$(curl -s "${DD}" | jq -r '.channels[] | select(.id=="development") | .versions[].files[] | select(.type=="update_tgz") | .url')
		if [[ "${VARIANT}" != "" ]]; then
			DL=$(echo "${DL}" | sed -e "s/${RN}.tgz$/${RV}.tgz/" -e 's/\/fw\/dev\//\/fw_extra_apps\//')
		fi
		FN=$(echo ${DL} | awk -F/ '{print $NF}')
                # dirname
                DN=$(echo ${FN} | sed -e 's/^flipper-z-//' -e 's/.tgz$//')

	fi

	echo "+ release: ${RN}"
	echo "+ date:    $(date -d ${RD} +%F) ($(( ($(date +%s) - $(date -d ${RD} +%s)) / 86400 ))d. ago)"
	echo "+ url:     ${DL}"
	echo "+ file:    ${FN}"

	# safeguard for forced dir removal in clenup
	if [[ "${DN}" == "" ]]; then
		echo "- something went wrong"
		exit
	fi
}

get_device(){
	# return, if set already by option
	if [[ "${FZ_DEV}" != "" ]]; then
		echo "+ device provided: ${FZ_DEV}"
		return
	fi
	# detect fz serial device
	FZ_DEV=$(find /dev -path "/dev/serial/by-id*" -name "*Flipper*" -exec readlink -f  {} \;)
	if [[ "${FZ_DEV}" == "" ]]; then
		echo "- device not found."
		exit
	fi
	if [[ $(echo "${FZ_DEV}" | wc -l ) != 1 ]]; then
		echo "- more than 1 device found, use -d option."
		echo "+ devices:"
		echo "${FZ_DEV}"
		exit
	fi
	echo "+ device: ${FZ_DEV}"
}

get_device_fw_version(){
	DV=$(echo "info device" | socat - "${FZ_DEV},${SP}" | grep firmware.version | awk -F: '{print $2}' | tr -d ' ')
	echo "+ on-device version: ${DV}"
	if [[ ("${DV}" == "${RV}") && ("${FORCE}" != "1") ]]; then
		echo "- on-device version matches firmware (will skip update unless forced)."
		exit
	fi
}

device_update(){
	echo "+ running update on device..."
	echo "update install /ext/update/${DN}/update.fuf" | socat - "${FZ_DEV},${SP}"
	echo "+ DONE"
}

do_update(){
	get_scripts
	UP=$(python3 ./scripts/storage.py -p "${FZ_DEV}" read /ext/update/${DN}/update.fuf | grep ^Info: | cut -d' ' -f2)
	if [[ ("${UP}" == "${RV}") && ("${FORCE}" != "1")  ]]; then
		echo "- ${UP} update is found on device, skipping."
	else
		if [[ -e "$FN" ]]; then
			echo "- ${FN} is found locally, skipping download."
		else
			echo "+ downloading..."
			curl -sLO "${DL}"
		fi
		echo "+ extracting..."
		tar -xf $FN
		echo "+ uploading to device..."
		python3 ./scripts/storage.py -p "${FZ_DEV}" send "${DN}" "/ext/update/${DN}"
	fi
	echo "+ cleanup..."
	rm -rf ./${DN}

	device_update
}

do_install(){
	FN=$1
	echo "+ installing from local file ${FN}"
	if [[ "${FN}" == "" ]]; then
		echo "- please provide file path."
		usage
	fi
	if [[ ! -e "${FN}" ]]; then
		echo "- file not found."
		exit 1
	fi
	DN=$(tar -tf ${FN} | grep update.fuf | cut -d/ -f1)
	if [[ "${DN}" == "" ]]; then
		echo "- no update found in a file"
		exit 1
	fi
	echo "+ found update.fuf inside, extracting"
	tar -xf $FN
	echo "+ $(grep ^Info: ${DN}/update.fuf)"

	get_scripts
	echo "+ uploading to device..."
	python3 ./scripts/storage.py -p "${FZ_DEV}" send "${DN}" "/ext/update/${DN}"
	echo "+ cleanup..."
	rm -rf ./${DN}

	device_update
}

cli(){
	echo "starting cli, Ctrl+C to terminate"
	socat - "${FZ_DEV},${SP}"
}

# getopts
while getopts ":fd:v:r:D" opt; do
	case $opt in
		f)
			FORCE=1		
                        ;;
		d)
			FZ_DEV=${OPTARG}
			;;
                v)
                        VARIANT=${OPTARG}
                        ;;
		r)
			REL=${OPTARG}
			;;
		D)
			DEVBUILD=1
			;;
		*)
			usage
			;;
	esac
done
shift $((OPTIND-1))

# defaults
cd $(dirname $0) 

# commands
case $1 in
	check)
		gear
		get_release_info
		get_device
		get_device_fw_version
		;;
	update)
		gear
		get_release_info
		get_device
		get_device_fw_version
		do_update
		;;
	install)
		gear
		get_device
		do_install "$2"
		;;
	list)
		get_device
		;;
	rel)
		get_releases
		;;
	cli)
		gear
		get_device
		cli
		;;
	*)
		usage
		;;
esac
