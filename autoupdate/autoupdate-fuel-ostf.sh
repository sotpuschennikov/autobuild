#!/bin/bash
PACKAGENAME=fuel-ostf
SRCREPO=https://github.com/stackforge/fuel-ostf
SPECREPO=https://github.com/stackforge/fuel-main
[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"
#RPMSPECFILE="autoupdate/SPECS/$PACKAGENAME.spec"
SRCFILES="/"
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
      #cp $WRKDIR/$RPMSPECFILE $MYOUTDIR/dst
      cp $MYOUTDIR/spec/$RPMSPECFILE $MYOUTDIR/dst
      ## Ugly workaround for wrong requirements
      ## Remove it after merge https://review.openstack.org/#/c/81208/
      #sed -i "/%setup/afind . -name setup.py -exec sed -i 's|python-saharaclient\>\=0\.6\.0|python-savannaclient>=0.3|' '{}' \\\;" $MYOUTDIR/dst/$PACKAGENAME.spec


      # Update source
      pushd $MYOUTDIR/src
      python setup.py sdist -d $MYOUTDIR/dst/
      popd

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
