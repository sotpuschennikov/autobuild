#!/bin/bash
PACKAGENAME=nailgun-mcagents
SRCREPO=https://github.com/stackforge/fuel-astute
SPECREPO=https://github.com/stackforge/fuel-main
[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"
#RPMSPECFILE="autoupdate/SPECS/$PACKAGENAME.spec"
DEBSPECFILE="autoupdate/SPECS/$PACKAGENAME-spec.tgz"
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
      cp $MYOUTDIR/spec/$RPMSPECFILE $MYOUTDIR/dst

      # Update source
      cd $MYOUTDIR/src/$SRCFILES
      tar -czf $MYOUTDIR/dst/mcagents.tar.gz *

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
  if [[ ! $DISABLEDEB == "1" ]]; then
      # Build DEB package

      [ -d $MYOUTDIR/dst ] && rm -rf $MYOUTDIR/dst
      mkdir -p $MYOUTDIR/dst

      # Unpack specs
      cd $MYOUTDIR/dst
      tar -xf $WRKDIR/$DEBSPECFILE
      version=`cat debian/changelog | head -1 | cut -d' ' -f2 | sed 's|.*(||;s|).*||;s|-.*||'`
      mkdir $PACKAGENAME-$version

      # Update source
      cd $MYOUTDIR/src/$SRCFILES
      tar -czf $MYOUTDIR/dst/$PACKAGENAME-$version/nailgun-mcagents.tar.gz *

      autobuilddebpackage
  else
      echo "Skip DEB building due to DISABLEDEB=$DISABLEDEB"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
