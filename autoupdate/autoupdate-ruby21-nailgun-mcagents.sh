#!/bin/bash
PACKAGENAME=ruby21-nailgun-mcagents
SRCREPO=https://github.com/stackforge/fuel-astute
#SPECREPO=https://github.com/stackforge/fuel-main
#[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
#RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.obs.spec"
RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"
SRCFILES='mcagents/'
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
      #cp $MYOUTDIR/spec/$RPMSPECFILE $MYOUTDIR/dst
      cp $WRKDIR/$RPMSPECFILE $MYOUTDIR/dst

      # Update source
      cd $MYOUTDIR/src/$SRCFILES
      tar -czf $MYOUTDIR/dst/nailgun-mcagents.tar.gz *

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
