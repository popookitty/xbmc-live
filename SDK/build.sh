#!/bin/bash

#      Copyright (C) 2005-2008 Team XBMC
#      http://www.xbmc.org
#
#  This Program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2, or (at your option)
#  any later version.
#
#  This Program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with XBMC; see the file COPYING.  If not, write to
#  the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
#  http://www.gnu.org/copyleft/gpl.html


echo
echo "Checking availability of required packages..."

REQUIREDPACKAGES=( git-core debootstrap asciidoc docbook-xsl curl build-essential debhelper autoconf automake autotools-dev curl subversion unzip)
NOTINSTALLED=()

for k in "${REQUIREDPACKAGES[@]}" ; do
	if [ "$( dpkg -l  | grep "ii" | grep "$k" )" = "" ] ; then
		NOTINSTALLED+=($k)
	fi
done

if [ ${#NOTINSTALLED[@]} -gt 0 ]; then
	echo
	echo "FATAL: the following packages are missing, exiting."
	for k in "${NOTINSTALLED[@]}"; do
		echo "  $k";
	done
	exit 1
fi

#
# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

# Clean our mess on exiting
cleanup()
{
	if [ -n "$WORKPATH" ]; then
		if [ -z "$KEEP_WORKAREA" ]; then
			echo "Cleaning workarea..."
			rm -rf $WORKPATH
			if [ -f $THISDIR/binary.iso ]; then
				chmod 777 $THISDIR/binary.*
			fi
			echo "All clean"
		fi
	fi
}
trap 'cleanup' EXIT TERM INT


THISDIR=$(pwd)
WORKDIR=workarea
WORKPATH=$THISDIR/$WORKDIR
export WORKPATH
export WORKDIR

echo ""

if [ -d "$WORKPATH" ]; then
	echo "Cleaning workarea..."
	rm -rf $WORKPATH
fi
mkdir $WORKPATH

if ls $THISDIR/binary.* > /dev/null 2>&1; then
	rm -rf $THISDIR/binary.*
fi

echo "Creating new workarea..."

# cp all (except git directories) into workarea
rsync -r -l --exclude=.git --exclude=$WORKDIR . $WORKDIR

if ! which lb > /dev/null ; then
	cd $WORKPATH/Tools
	if [ ! -d live-build ]; then
		repoURL="http://live.debian.net/archive/packages/live-build/orig/"
		if [ -z "$SDK_USELATESTDEBIANLIVE" ]; then
		    latestPackage="live-build_3.0~a38.orig.tar.gz"
		else
		    latestPackage=$(curl -x "" -s -f $repoURL | grep live-build | tail -1 | grep -o '"live-build_[^"]*.tar.gz"' | sed -e "s/\"//g")
		fi

		if ! ls $latestPackage > /dev/null 2>&1 ; then
			echo "Retrieving live-build tarball..."
			echo " -  Latest package: $latestPackage"

			wget -q "$repoURL$latestPackage"
			if [ "$?" -ne "0" ] || [ ! -f $latestPackage ] ; then
				echo "Needed package ($latestPackage) not found, exiting..."
				exit 1
			fi
		fi
		tar xf $latestPackage
		mv live-build-* live-build
	fi

	LB_HOMEDIR=$WORKPATH/Tools/live-build

	export LB_BASE="${LB_HOMEDIR}"
	export PATH="${PATH}:${LB_BASE}/scripts/build"

	cd $THISDIR
fi

echo "Start building..."
echo ""

cd $WORKPATH

# Execute hooks if env variable is defined
if [ -n "$SDK_BUILDHOOKS" ]; then
	for hook in $SDK_BUILDHOOKS; do
		if [ -x $hook ]; then
			$hook
			if [ "$?" -ne "0" ]; then
				exit 1
			fi
		fi
	done
fi

#
# Build needed packages
#
if [ -f $WORKPATH/buildDEBs/build.sh ]; then
	echo ""
	echo "------------------------"
	echo "Build needed packages..."
	echo "------------------------"
	echo ""

	cd $WORKPATH/buildDEBs
	./build.sh
	if [ "$?" -ne "0" ]; then
		exit 1
	fi
	cd $THISDIR
fi

#
# Copy all needed files in place for the real build
#

filesToRun=$(ls $WORKPATH/copyFiles-*.sh 2> /dev/null)
if [ -n "$filesToRun" ]; then
	for hook in $filesToRun; do
		$hook
		if [ "$?" -ne "0" ]; then
			exit 1
		fi
	done
fi

#
# Perform XBMCLive image build
#

echo ""
echo "-------------------------------"
echo "Perform XBMCLive image build..."
echo "-------------------------------"
echo ""

cd $WORKPATH/buildLive
./build.sh
cd $THISDIR

#
# Copy binary files from workarea
#

if [ -f $WORKPATH/buildLive/binary-hybrid.iso ] || [ -f $WORKPATH/buildLive/binary.iso ] || [ -f $WORKPATH/buildLive/binary.img ] ; then
	mv $WORKPATH/buildLive/binary*.* .
	chmod 777 binary*.*
	echo "XBMCLive build completed!"
fi
