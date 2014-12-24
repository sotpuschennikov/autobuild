#!/bin/bash
PACKAGENAME=ruby21-rubygem-astute
SRCREPO=https://github.com/stackforge/fuel-astute
#SPECREPO=https://github.com/stackforge/fuel-main
#[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
#RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"
RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec autoupdate/SPECS/astute.conf autoupdate/SPECS/rubygem-astute.spec.in"

SRCFILES='/'
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
      for specfile in $RPMSPECFILE; do
        #cp $MYOUTDIR/spec/$specfile $MYOUTDIR/dst
        cp $WRKDIR/$specfile $MYOUTDIR/dst
      done

      # Update source
      pushd $MYOUTDIR/src/$SRCFILES &>/dev/null
      gem build astute.gemspec
      mv *.gem $MYOUTDIR/dst/
      popd &>/dev/null

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
