#!/bin/bash
PACKAGENAME=rubygem-naily
SRCREPO=https://github.com/stackforge/fuel-web
#SPECREPO=https://github.com/stackforge/fuel-main
#RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"
#[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
RPMSPECFILE="autoupdate/SPECS/$PACKAGENAME.spec"
SRCFILES='naily/'
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
      cp $WRKDIR/$RPMSPECFILE $MYOUTDIR/dst

      # Update source
      pushd $MYOUTDIR/src/$SRCFILES
      gem build naily.gemspec
      mv *.gem $MYOUTDIR/dst/
      popd

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
