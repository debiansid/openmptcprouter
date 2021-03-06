#!/bin/sh

set -e

umask 0022
unset GREP_OPTIONS SED

_get_repo() (
	mkdir -p "$1"
	cd "$1"
	[ -d .git ] || git init
	if git remote get-url origin >/dev/null 2>/dev/null; then
		git remote set-url origin "$2"
	else
		git remote add origin "$2"
	fi
	git fetch origin
	git fetch origin --tags
	git checkout -f "origin/$3" -B "build" 2>/dev/null || git checkout "$3" -B "build"
)

OMR_DIST=${OMR_DIST:-openmptcprouter}
OMR_HOST=${OMR_HOST:-$(curl -sS ifconfig.co)}
OMR_PORT=${OMR_PORT:-8000}
OMR_REPO=${OMR_REPO:-http://$OMR_HOST:$OMR_PORT/release}
OMR_KEEPBIN=${OMR_KEEPBIN:-no}
OMR_IMG=${OMR_IMG:-yes}
OMR_UEFI=${OMR_UEFI:-yes}
OMR_ALL_PACKAGES=${OMR_ALL_PACKAGES:-no}
OMR_TARGET=${OMR_TARGET:-x86_64}
OMR_TARGET_CONFIG="config-$OMR_TARGET"

OMR_FEED_URL="${OMR_FEED_URL:-https://github.com/ysurac/openmptcprouter-feeds}"
OMR_FEED_SRC="${OMR_FEED_SRC:-master}"

if [ ! -f "$OMR_TARGET_CONFIG" ]; then
	echo "Target $OMR_TARGET not found !"
	#exit 1
fi

if [ "$OMR_TARGET" = "rpi3" ]; then
	OMR_REAL_TARGET="aarch64_cortex-a53"
elif [ "$OMR_TARGET" = "rpi2" ]; then
	OMR_REAL_TARGET="arm_cortex-a7_neon-vfpv4"
elif [ "$OMR_TARGET" = "wrt3200acm" ]; then
	OMR_REAL_TARGET="arm_cortex-a9_vfpv3"
elif [ "$OMR_TARGET" = "wrt32x" ]; then
	OMR_REAL_TARGET="arm_cortex-a9_vfpv3"
elif [ "$OMR_TARGET" = "bpi-r2" ]; then
	OMR_REAL_TARGET="arm_cortex-a7_neon-vfpv4"
else
	OMR_REAL_TARGET=${OMR_TARGET}
fi

#_get_repo source https://github.com/ysurac/openmptcprouter-source "master"
_get_repo "$OMR_TARGET/source" https://github.com/openwrt/openwrt "529c95cc15dc9fcc7709400cc921f2a3c03cd263"
_get_repo feeds/packages https://github.com/openwrt/packages "openwrt-18.06"
_get_repo feeds/luci https://github.com/openwrt/luci "openwrt-18.06"

if [ -z "$OMR_FEED" ]; then
	OMR_FEED=feeds/openmptcprouter
	_get_repo "$OMR_FEED" "$OMR_FEED_URL" "$OMR_FEED_SRC"
fi

if [ -n "$1" ] && [ -f "$OMR_FEED/$1/Makefile" ]; then
	OMR_DIST=$1
	shift 1
fi

if [ "$OMR_KEEPBIN" = "no" ]; then 
	rm -rf "$OMR_TARGET/source/bin"
fi
rm -rf "$OMR_TARGET/source/files" "$OMR_TARGET/source/tmp"
#rm -rf "$OMR_TARGET/source/target/linux/mediatek/patches-4.14"
cp -rf root/* "$OMR_TARGET/source"

cat >> "$OMR_TARGET/source/package/base-files/files/etc/banner" <<EOF
-----------------------------------------------------
 PACKAGE:     $OMR_DIST
 VERSION:     $(git -C "$OMR_FEED" describe --tag --always)

 BUILD REPO:  $(git config --get remote.origin.url)
 BUILD DATE:  $(date -u)
-----------------------------------------------------
EOF

cat > "$OMR_TARGET/source/feeds.conf" <<EOF
src-link packages $(readlink -f feeds/packages)
src-link luci $(readlink -f feeds/luci)
src-link openmptcprouter $(readlink -f "$OMR_FEED")
EOF

#cat > "$OMR_TARGET/source/package/system/opkg/files/customfeeds.conf" <<EOF
#src/gz openwrt_luci http://downloads.openwrt.org/snapshots/packages/${OMR_REAL_TARGET}/luci
#src/gz openwrt_packages http://downloads.openwrt.org/snapshots/packages/${OMR_REAL_TARGET}/packages
#src/gz openwrt_base http://downloads.openwrt.org/snapshots/packages/${OMR_REAL_TARGET}/base
#src/gz openwrt_routing http://downloads.openwrt.org/snapshots/packages/${OMR_REAL_TARGET}/routing
#src/gz openwrt_telephony http://downloads.openwrt.org/snapshots/packages/${OMR_REAL_TARGET}/telephony
#EOF
cat > "$OMR_TARGET/source/package/system/opkg/files/customfeeds.conf" <<EOF
src/gz openwrt_luci http://downloads.openwrt.org/releases/18.06.0/packages/${OMR_REAL_TARGET}/luci
src/gz openwrt_packages http://downloads.openwrt.org/releases/18.06.0/packages/${OMR_REAL_TARGET}/packages
src/gz openwrt_base http://downloads.openwrt.org/releases/18.06.0/packages/${OMR_REAL_TARGET}/base
src/gz openwrt_routing http://downloads.openwrt.org/releases/18.06.0/packages/${OMR_REAL_TARGET}/routing
src/gz openwrt_telephony http://downloads.openwrt.org/releases/18.06.0/packages/${OMR_REAL_TARGET}/telephony
EOF

if [ -f "$OMR_TARGET_CONFIG" ]; then
	cat "$OMR_TARGET_CONFIG" config -> "$OMR_TARGET/source/.config" <<-EOF
	CONFIG_IMAGEOPT=y
	CONFIG_VERSIONOPT=y
	CONFIG_VERSION_DIST="$OMR_DIST"
	CONFIG_VERSION_REPO="$OMR_REPO"
	CONFIG_VERSION_NUMBER="$(git -C "$OMR_FEED" describe --tag --always)"
	CONFIG_PACKAGE_${OMR_DIST}-full=y
	EOF
else
	cat config -> "$OMR_TARGET/source/.config" <<-EOF
	CONFIG_IMAGEOPT=y
	CONFIG_VERSIONOPT=y
	CONFIG_VERSION_DIST="$OMR_DIST"
	CONFIG_VERSION_REPO="$OMR_REPO"
	CONFIG_VERSION_NUMBER="$(git -C "$OMR_FEED" describe --tag --always)"
	CONFIG_PACKAGE_${OMR_DIST}-full=y
	EOF
fi
if [ "$OMR_ALL_PACKAGES" = "yes" ]; then
	echo 'CONFIG_ALL=y' >> "$OMR_TARGET/source/.config"
fi
if [ "$OMR_IMG" = "yes" ] && [ "$OMR_TARGET" = "x86_64" ]; then 
	echo 'CONFIG_VDI_IMAGES=y' >> "$OMR_TARGET/source/.config"
	echo 'CONFIG_VMDK_IMAGES=y' >> "$OMR_TARGET/source/.config"
fi


cd "$OMR_TARGET/source"

echo "Checking if UEFI patch is set or not"
if [ "$OMR_UEFI" = "yes" ] && [ "$OMR_TARGET" = "x86_64" ]; then 
	if [ ! -f "target/linux/x86/image/startup.nsh" ]; then
		patch -N -p1 -s < ../../patches/uefi.patch
	fi
else
	if [ -f "target/linux/x86/image/startup.nsh" ]; then
		patch -N -R -p1 -s < ../../patches/uefi.patch
	fi
fi
echo "Done"

#echo "Remove gtime dependency"
#if ! patch -Rf -N -p1 -s --dry-run < ../../patches/gtime.patch; then
#	patch -N -p1 -s < ../../patches/gtime.patch
#fi
#echo "Done"


#echo "Set to kernel 4.9 for all arch"
#find target/linux/ -type f -name Makefile -exec sed -i 's%KERNEL_PATCHVER:=4.14%KERNEL_PATCHVER:=4.9%g' {} \;
#echo "Done"
#echo "Set to kernel 4.14 for rpi arch"
#find target/linux/brcm2708 -type f -name Makefile -exec sed -i 's%KERNEL_PATCHVER:=4.9%KERNEL_PATCHVER:=4.14%g' {} \;
#echo "Done"
#echo "Remove old RPI firmware"
#rm -rf target/linux/brcm2708/base-files/lib/firmware
#echo "Done"

echo "Update feeds index"
cp .config .config.keep
scripts/feeds clean
scripts/feeds update -a
if [ "$OMR_ALL_PACKAGES" = "yes" ]; then
	scripts/feeds install -a -p packages
	scripts/feeds install -a -p luci
fi
scripts/feeds install -a -d y -f -p openmptcprouter
cp .config.keep .config
echo "Done"

if [ ! -f "../../$OMR_TARGET_CONFIG" ]; then
	echo "Target $OMR_TARGET not found ! You have to configure and compile your kernel manually."
	exit 1
fi

echo "Building $OMR_DIST for the target $OMR_TARGET"
make defconfig
make IGNORE_ERRORS=m "$@"
echo "Done"
