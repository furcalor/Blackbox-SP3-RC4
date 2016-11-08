#!/bin/bash

ACTION=$1
OPTION=$2
OPTIONAL=$3

USAGE="
USAGE: ${0} [clone|pull] [debug|release] [wifi|dbs|all|none}
    Actions:
        clone	- remove old build directory and clone fresh, applying all
                  patches and staying at v4.9-RC4
        pull	- keep existing build dir and pull changes only, and will 
                  sync all changes from Torvalds current tree
    Options:
        debug	- create debug .deb also (>400MB)
        release - create release build only

    Optional:
	wifi	- Add patch & use MAC80211 iwlwifi instead of mwifiex
        dbs	- Patch kernel for Geniatech HDSTAR support
	all	- Patch kernel for both iwlwifi and geniatech hdstar
	none	- No optional patches
	
    Example: (clone and build release with iwlwifi)
    ${0} clone release wifi"

dprint() {
	echo "---> ${@}" >&2
}

# validate we have internet access for git
ping 8.8.8.8 -c 1 2>&1 >/dev/null
if [ $? -ne 0 ]; then
	dprint "Internet access is required, please resolve and try again."
	exit 1
fi

if [ "$ACTION" == "clone" ]; then

	rm -rf linux.old
	mv linux linux.old

	# clone from Linus git tree
	git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

	# now, reset to v4.9-RC4, do a pull again to reset
	cd linux
	git reset --hard b58ec8b5824717875b844a9e8cc62fc6eb5fd289

	# apply all the Patches from dir
	for i in $( ls ../Patches ); do
		patch -p1 --ignore-whitespace -i ../Patches/$i
	done

elif [ "$ACTION" == "pull" ]; then

	# git pull from Linux tree
	cd linux
	git pull |grep up-to-date

	# if no changes, then we're done
	if [ $? -eq 0 ]; then
		dprint "Nothing to do."
		exit 0
	fi

else

	dprint "${USAGE}"
	exit 1
fi

# make config file based off of running config
yes '' | make oldconfig

# disable LUSTRE
sed -i 's/CONFIG_LUSTRE_FS=m/CONFIG_LUSTRE_FS=n/g' .config

if [ "$ACTION" == "clone" ]; then
	# update the .config for surface button in case this is the first time build
	sed -i 's/# CONFIG_SURFACE_PRO3_BUTTON is not set/CONFIG_SURFACE_PRO3_BUTTON=m/g' .config
fi

if [ "$OPTION" == "release" ]; then
	# update .config and disable debug
	sed -i 's/CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/g' .config
elif [ "$OPTION" == "debug" ]; then
	# update .config and enable debug
	sed -i 's/# CONFIG_DEBUG_INFO is not set/CONFIG_DEBUG_INFO=y/g' .config
else
	dprint "${USAGE}"
	exit 1
fi


if [ "$OPTIONAL" == "wifi" ]; then
		#MAC80211 iwlwifi patch for 88W8897 from https://patchwork.kernel.org/patch/9201663/
		patch -p1 --ignore-whitespace -i ../Patches/Opt/0008-mwlwifi-patch.patch

elif [ "$ACTION" == "dvb" ]; then
		#Genia Tech HDSTAR patch from https://gist.github.com/pdp7/dfd98f86788d48fb2ed5
		patch -p1 --ignore-whitespace -i ../Patches/0009-geniatech-hdstar-modules.patch


elif [ "$ACTION" == "all" ]; then

	for i in $( ls ../Patches ); do
		patch -p1 --ignore-whitespace -i ../Patches/Opt/$i
	done

elif [ "$ACTION" == "none" ]; then

else

	dprint "${USAGE}"
	exit 1
fi


# build it
make clean
make -j `getconf _NPROCESSORS_ONLN` deb-pkg LOCALVERSION=-SP3

# move the build output to build after cleaning up old stuff
cd ..
rm -rf build
mkdir build
mv linux-* build/
