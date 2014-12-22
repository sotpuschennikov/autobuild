#!/bin/bash
[ -z $PROJECTNAME ] && exit 1
[ -z $NEEDUPDATE ] && NEEDUPDATE=false
[ -z $OBSURL ] && OBSURL='https://osci-obs.vm.mirantis.net'
OBSAPI="-A ${OBSURL}:444" 

FILESNUM=`echo $SRCFILES | awk '{print NF}'`
MYOUTDIR=$WRKDIR/workdir/$PACKAGENAME
[ -d $MYOUTDIR ] || mkdir -p $MYOUTDIR
pushd $MYOUTDIR &>/dev/null

set -x

if [ -d src ]; then
  pushd src &>/dev/null
  git fetch --all
  git checkout -B $SRCBRANCH origin/$SRCBRANCH 
  popd &>/dev/null
else
  git clone $WRKDIR/data/${SRCREPO##*/} src
  pushd src &>/dev/null
  git checkout -B $SRCBRANCH origin/$SRCBRANCH 
  popd &>/dev/null
fi

pushd src &>/dev/null
[ -f $MYOUTDIR/prevcommit ] || git log -n1 | grep ^commit | cut -d " " -f 2 > $MYOUTDIR/prevcommit
[ -z $PREV_COMMIT ] && PREV_COMMIT=`cat $MYOUTDIR/prevcommit`
CURR_COMMIT=`git log -n1 | grep ^commit | cut -d " " -f 2`
CHANGED_FILES=`git diff ${PREV_COMMIT} | grep ^+++ | sed 's|+++ b/||'`
popd &>/dev/null

for file in $CHANGED_FILES; do
  for srcfile in $SRCFILES; do
    if [[ "$file" =~ "$srcfile" ]]; then NEEDUPDATE=true; fi
  done
done

if [ -n $SPECREPO ]; then
  if [ -d spec ]; then
    pushd spec &>/dev/null
    git fetch --all
    git checkout -B $SPECBRANCH origin/$SPECBRANCH
    popd &>/dev/null
  else
    git clone $WRKDIR/data/${SPECREPO##*/} spec
    pushd spec &>/dev/null
    git checkout -B $SPECBRANCH origin/$SPECBRANCH
    popd &>/dev/null
  fi

  pushd spec &>/dev/null
  [ -f $MYOUTDIR/specprevcommit ] || git log -n1 | grep ^commit | cut -d " " -f 2 > $MYOUTDIR/specprevcommit
  [ -z $SPECPREV_COMMIT ] && SPECPREV_COMMIT=`cat $MYOUTDIR/specprevcommit`
  CHANGED_FILES=`git diff ${SPECPREV_COMMIT} | grep ^+++ | sed 's|+++ b/||'`
  popd &>/dev/null
  
  for file in $CHANGED_FILES; do
      if [ -n "$RPMSPECFILE" ]; then
        for specfile in $RPMSPECFILE; do
          [[ "$file" =~ "$specfile" ]] && NEEDUPDATE=true
        done
      fi
      #if [ -n "$DEBSPECFILE" ]; then
      #  [[ "$file" =~ "$DEBSPECFILE" ]] && NEEDUPDATE=true
      #fi
  done

fi             
popd &>/dev/null

set +x

get_fuel_package_revision() {
  # Getting URL to the master prj repository
  REPOURL="http://${OBSURL##*/}:82"
  REPONAME=`osc meta prj $PROJECTNAME | grep "repository name" | cut -d '"' -f 2`

  if [ -z "`wget -q $REPOURL/$PROJECTNAME/$REPONAME/ -O - | grep '>Packages<'`" ]
  then # CentOS repo
    # Getting current package revision
    revision=`wget -q $REPOURL/$PROJECTNAME/$REPONAME/repodata/primary.xml.gz -O - | gunzip | \
              grep /$binpackagename-$version- | grep src\.rpm | sort -r | head -1 | \
              cut -d'"' -f2 | sed 's|^.*/||; s|\.src\.rpm$||' | awk -F'-' '{print $NF}'`
  else # Ubuntu repo
    # Getting current package revision
    revision=`wget -q $REPOURL/$PROJECTNAME/$REPONAME/Packages.gz -O - | gunzip | \
              grep /${binpackagename}_ | grep ^File | sort -r | head -1 | cut -d'_' -f2 | \
              awk -F'-' '{print $NF}' | sed 's|.*ubuntu||'`
  fi
  [ -z "$revision" ] && revision=0
  # Increment revision
  revision=$(( $revision + 1 ))
}

get_obs_package() {
  [ -d $MYOUTDIR/obs ] && rm -rf $MYOUTDIR/obs
  if ! osc $OBSAPI co -o $MYOUTDIR/obs $PROJECTNAME $PACKAGENAME; then
    create_package
    osc $OBSAPI co -o $MYOUTDIR/obs $PROJECTNAME $PACKAGENAME
    NEEDUPDATE=true
  fi
}

autobuilddebpackage () {
  PROJECTNAME=ubuntu-$OBSPROJECT

  # Get OBS package
  get_obs_package
  if [ -d $MYOUTDIR/obs ]; then
    cd $MYOUTDIR/obs
    rm -f *
  else
    exit 1
  fi

  # Define version
  cd $MYOUTDIR/dst

  binpackagename=`cat debian/control | grep ^Packa | cut -d' ' -f 2 | head -1`
  version=`cat debian/changelog | grep "$PACKAGENAME (" | head -1 | sed 's|^.*(||;s|).*$||' | awk -F "-" '{print $1}'`
  get_fuel_package_revision
  release="ubuntu$revision"
  fullver=$version-$release

  info "Package version: $fullver"

  # Update changelog
  DEBFULLNAME='OSCI Jenkins' DEBEMAIL='dburmistrov@mirantis.com' dch -b --force-distribution -v "$fullver" "Update code from upstream"

  # Pack debian specs to .debian.tar.gz
  TAR_BASENAME="${PACKAGENAME}_${fullver#*:}.debian"
  TARFILE="${MYOUTDIR}/${TAR_BASENAME}.tar.gz"

  tar --owner=root --group=root -czf $TARFILE $EXCLUDES debian

  # Pack all other files to .orig.tar.gz
  # Exclude debian dir
  mv debian renameforexcludedebian
  TAR_BASENAME="${PACKAGENAME}_${version#*:}.orig"
  TARFILE="${MYOUTDIR}/${TAR_BASENAME}.tar.gz"
  tar --owner=root --group=root -czf $TARFILE $EXCLUDES --exclude=renameforexcludedebian *
  mv renameforexcludedebian debian

  # Create DSC file
  generate_dsc

  #Add new files to package
  mv $MYOUTDIR/*.dsc $MYOUTDIR/obs/
  mv $MYOUTDIR/*.gz $MYOUTDIR/obs/
  cd $MYOUTDIR/obs
  osc $OBSAPI addremove

  # Push updated package to OBS
  info "Committing package $PACKAGENAME"
  osc $OBSAPI commit -m "Update from github" && echo $CURR_COMMIT > $MYOUTDIR/prevcommit || exit 1

  # Wait for building package
  echo
  echo "Starting build of $PACKAGENAME"
  echo "$OBSURL/package/live_build_log?arch=x86_64&package=$PACKAGENAME&project=$PROJECTNAME&repository=ubuntu"
  info "To abort build copy this URL to browser: $OBSURL/package/abort_build?arch=x86_64&project=$PROJECTNAME&repo=ubuntu&package=${PACKAGENAME}REMOVEME"
  get_build_status
  wait_for_packages_in_repo

  # Update reprepro
  info "Updating $PROJECTNAME/reprepro repository"
  REPONAME=`osc $OBSAPI meta prj $PROJECTNAME | grep "repository name" | sed 's|^.*="||;s|".*$||'`
  ARCH=`osc $OBSAPI meta prj $PROJECTNAME | grep "<arch>" | awk -F'[<>]' '{print $3}'`
  DIST=precise
  for binpackage in `osc api /build/$PROJECTNAME/$REPONAME/$ARCH/$PACKAGENAME/ | grep ".deb\"" | cut -d'"' -f2`; do
    ssh -q root@osci-obs.vm.mirantis.net "\
       export REPREPRO_BASE_DIR=/srv/obs/repos/$PROJECTNAME/reprepro; \
       for package in \`find /srv/obs/repos/$PROJECTNAME/$REPONAME/ -name $binpackage\`; do \
       reprepro includedeb $DIST \$package; \
       done"
  done
}

autobuildrpmpackage () {
  PROJECTNAME=centos-$OBSPROJECT

  # Get OBS package
  get_obs_package
  if [ -d $MYOUTDIR/obs ]; then
    cd $MYOUTDIR/obs
    rm -f *
  else
    exit 1
  fi

  # Define version
  cd $MYOUTDIR/dst
  specfile=`find $MYOUTDIR/dst/ -name *.spec`

  binpackagename=`rpm -q --specfile $specfile --queryformat %{NAME}"\n" | head -1`
  version=`rpm -q --specfile $specfile --queryformat %{VERSION}"\n" | head -1`
  get_fuel_package_revision
  info "Package version: $version-$revision"

  # Update specs
  sed -i "s/Release:.*$/Release: ${revision}/" $specfile

  # Add new files to package
  mv $MYOUTDIR/dst/* $MYOUTDIR/obs/
  cd $MYOUTDIR/obs
  osc $OBSAPI addremove

  # Push updated package to OBS
  info "Committing package $PACKAGENAME"
  osc $OBSAPI commit -m "Update from github" && echo $CURR_COMMIT > $MYOUTDIR/prevcommit || exit 1

  # Wait for building package
  echo
  echo "Starting build of $PACKAGENAME"
  echo "$OBSURL/package/live_build_log?arch=x86_64&package=$PACKAGENAME&project=$PROJECTNAME&repository=centos"
 # info "To abort build copy this URL to browser: $OBSURL/package/abort_build?arch=x86_64&project=$PROJECTNAME&repo=centos&package=${PACKAGENAME}REMOVEME"
  get_build_status
  wait_for_packages_in_repo
}

