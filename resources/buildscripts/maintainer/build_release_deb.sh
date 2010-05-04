#!/bin/sh

sudo apt-get update -qq
sudo apt-get upgrade -qq
sudo apt-get install -y -q --install-recommends build-essential devscripts debhelper python2.6-dev libfreetype6-dev libglib2.0-dev libfontconfig1-dev intltool binutils pbuilder subversion
sudo pbuilder create --debootstrapopts --variant=buildd

echo
echo 'Fetching source'
echo
svn co http://font-manager.googlecode.com/svn/trunk/ font-manager
cd font-manager
find . -name '.svn' -print | xargs rm -rf
. ./release
echo
echo 'Preparing source'
echo
./configure
make dist-zip
rm -rf BUILD
mkdir BUILD
cd BUILD
unzip -q ../$PACKAGE-$VERSION.zip
cp -R ../debian $PACKAGE-$VERSION/
cp -R $PACKAGE-$VERSION $PACKAGE-$VERSION.orig
cd $PACKAGE-$VERSION
echo
echo 'Doing initial source build'
echo
debuild -S -us -uc
echo
echo 'Building package'
echo
sudo pbuilder build ../*.dsc
cd ../../
rm -rf RESULTS
mkdir RESULTS
cp -f /var/cache/pbuilder/result/$PACKAGE* ./RESULTS/
echo 'Now running cleanup'
rm -f $PACKAGE-$VERSION.zip
rm -rf BUILD
echo
echo 'Done!'


