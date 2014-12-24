#!/bin/bash
PACKAGENAME=nailgun
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
      ## Ugly workaround for wrong requirements
      ## Remove it after merge https://review.openstack.org/#/c/81208/
      #sed -i "/%setup/afind . -name requirements.txt -exec sed -i 's|==|>=|g' '{}' \\\;" $MYOUTDIR/dst/$PACKAGENAME.spec

      # Update source
      [ -e "$MYOUTDIR/prepsrc" ] && rm -rf "$MYOUTDIR/prepsrc"
      mkdir -p "$MYOUTDIR/prepsrc"
      cp -R $MYOUTDIR/src/$SRCFILES/* $MYOUTDIR/prepsrc
      pushd $MYOUTDIR/prepsrc &>/dev/null
      npm install
      # Workaround for compress static
      grunt build --static-dir=static_compressed
      rm -rf static
      mv static_compressed static
      python setup.py sdist -d $MYOUTDIR/dst/
      rm -rf static
      git reset --hard HEAD
      popd &>/dev/null
      rm -rf "$MYOUTDIR/prepsrc"

      autobuildrpmpackage
  else
      echo "Skip RPM building due to DISABLERPM=$DISABLERPM"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi
