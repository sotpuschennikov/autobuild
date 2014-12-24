#!/bin/bash
PACKAGENAME=shotgun
SRCREPO=https://github.com/stackforge/fuel-web
SPECREPO=https://github.com/stackforge/fuel-main
[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"
SRCFILES="$PACKAGENAME/"
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

      # Update source
      pushd $MYOUTDIR/src/$SRCFILES
      python setup.py sdist -d $MYOUTDIR/dst/
      popd

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
