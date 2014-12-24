#!/bin/bash
PACKAGENAME=nailgun-net-check
SRCREPO=https://github.com/stackforge/fuel-web
SPECREPO=https://github.com/stackforge/fuel-main
[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"
DEBSPECFILE="packages/deb/specs/$PACKAGENAME"
SRCFILES='network_checker/'

AGGREGATE=false

source $WRKDIR/build-functions.sh
source $WRKDIR/autoupdate/autoupdate-functions.sh

if $NEEDUPDATE; then
  info "New changes in $PACKAGENAME!!!"
  OBSPROJECT=$PROJECTNAME

  if [[ ! $DISABLERPM == "1" ]]; then
      # Build RPM package

      [ -d $MYOUTDIR/dst ] && rm -rf $MYOUTDIR/dst
      mkdir -p $MYOUTDIR/dst

      # Get specs
      cp $MYOUTDIR/spec/$RPMSPECFILE $MYOUTDIR/dst

      # Update source
      pushd $MYOUTDIR/src/$SRCFILES
      python setup.py sdist -d $MYOUTDIR/dst/
      popd

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
  if [[ ! $DISABLEDEB == "1" ]]; then
      # Build DEB package

      [ -d $MYOUTDIR/dst ] && rm -rf $MYOUTDIR/dst
      mkdir -p $MYOUTDIR/dst

      cd $MYOUTDIR/dst
      # Unpack specs
      #tar -xf $WRKDIR/$DEBSPECFILE
      cp -R $MYOUTDIR/spec/$DEBSPECFILE/debian .

      version=`cat debian/changelog | head -1 | cut -d' ' -f2 | sed 's|(||;s|\-.*||'`

      # Update source
      #pushd $MYOUTDIR/src/$SRCFILES
      #python setup.py sdist -d $MYOUTDIR/dst/
      #popd
      mkdir -p $MYOUTDIR/dst/$PACKAGENAME-$version/
      cp -R $MYOUTDIR/src/${SRCFILES}/* $MYOUTDIR/dst/$PACKAGENAME-$version/

      autobuilddebpackage
  else
      echo "Skip DEB building due to DISABLEDEB=$DISABLEDEB"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
