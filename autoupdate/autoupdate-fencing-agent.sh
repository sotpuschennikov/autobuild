#!/bin/bash

PACKAGENAME=fencing-agent
SRCREPO=https://github.com/stackforge/fuel-web
SPECREPO=https://github.com/stackforge/fuel-main
[ -z "$SPECBRANCH" ] && SPECBRANCH=$SRCBRANCH
RPMSPECFILE="packages/rpm/specs/$PACKAGENAME.spec"

SRCFILES='bin/fencing-agent.cron bin/fencing-agent.rb'
RPMDSTFILES='fencing-agent.cron fencing-agent.rb'

DEBSPECFILE="packages/deb/specs/$PACKAGENAME"

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

      # Unpack specs
      cp $MYOUTDIR/spec/$RPMSPECFILE $MYOUTDIR/dst
      # Update source
      for (( i=1; i<=$FILESNUM; i++ )); do
        srcfile=$MYOUTDIR/src/`echo $SRCFILES | cut -d " " -f $i`
        dstfile=$MYOUTDIR/dst/`echo $RPMDSTFILES | cut -d " " -f $i`
        cp -R $srcfile $dstfile
      done

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
      version=`cat debian/changelog | head -1 | cut -d' ' -f2 | sed 's|(||;s|\-.*||'`
      mkdir $PACKAGENAME-$version
      # Update source
      for (( i=1; i<=$FILESNUM; i++ )); do
        srcfile=$MYOUTDIR/src/`echo $SRCFILES | cut -d " " -f $i`
        dstfile=$MYOUTDIR/dst/$PACKAGENAME-$version/`echo $DEBDSTFILES | cut -d " " -f $i`
        cp -R $srcfile $dstfile
      done

      autobuilddebpackage
  else
      echo "Skip DEB building due to DISABLEDEB=$DISABLEDEB"
  fi
else
  info "No changes in $PACKAGENAME. Exiting"
fi

