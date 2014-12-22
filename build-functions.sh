#!/bin/bash
[ -z "$GERRIT_USER" ] && GERRIT_USER='openstack-ci-jenkins'
[ -z "$PRJSUFFIX" ] && PRJSUFFIX="-stable"
EXCLUDES='--exclude-vcs'
[ -z "$OBSURL" ] && OBSURL='https://osci-obs.vm.mirantis.net'
[ -z "$OBSAPI" ] && OBSAPI="-A ${OBSURL}:444"
[ -z "$AGGREGATE" ] && AGGREGATE=false
[ -z "${GERRIT_SCHEME}" ] || URL="${GERRIT_SCHEME}://${GERRIT_USER}@${GERRIT_HOST}:${GERRIT_PORT}/"
[ -z $URL ] && URL="ssh://${GERRIT_USER}@gerrit.mirantis.com:29418/"
[ -z "${GERRIT_HOST}" ] && GERRIT_HOST=`echo $URL | sed 's|[:/@]||g'`
[ -z $DISABLEOBS ] || set -x
GITDATA=${HOME}/gitdata/$GERRIT_HOST

GOOGLE_WORKSHEET_NAME=${GOOGLE_WORKSHEET_NAME:-$GERRIT_BRANCH}
GSS_CMD=${GSS_CMD:-gss_db.py}

LP_PROJECT=fuel
LP_PROJECT_AFFECTED="$LP_PROJECT,mos"

error () {
  echo
  echo -e "ERROR: $*"
  echo
  exit 1
}

info () {
  echo
  echo -e "INFO: $*"
  echo
}

function job_lock() {
    local LOCKFILE=$1
    shift
    fd=15
    eval "exec $fd>$LOCKFILE"
    if [ "$1" = "set" ]; then
        flock -x $fd
    elif [ "$1" = "unset" ]; then
        flock -u $fd
    fi
}

report_merged() {
  if [[ -f ~/.config/gss_db/gss_db.conf ]]; then
    local PACKAGE_TYPE=$(echo $JOB_NAME | grep -ioE 'rpm|deb')
    $GSS_CMD "$GOOGLE_SPREADSHEET_ID" "$GOOGLE_WORKSHEET_NAME" insert \
             timestamp="$(date +'%Y-%m-%d %H:%M:%S %Z')" \
             project="$GERRIT_PROJECT" \
             package="$PACKAGE_TYPE" \
             change-owner="$GERRIT_CHANGE_OWNER_NAME" \
             change-owner-email="$GERRIT_CHANGE_OWNER_EMAIL" \
             change-request="$GERRIT_CHANGE_URL" \
             description="$GERRIT_CHANGE_SUBJECT"
  fi
}

remove_changeset_project() {
  if [[ $GERRIT_EVENT_TYPE == "change-merged" ]]
  then
    CHANGESETPROJECT=`osc $OBSAPI ls / | grep "\-$GERRIT_CHANGE_NUMBER$" | grep $MASTERPRJ || :`
    info "Remove project $CHANGESETPROJECT due to merged status"
    report_merged
    for prj in $CHANGESETPROJECT; do
      if [ ! -z "$prj" ]; then
          osc $OBSAPI rdelete -f -r $prj -m "Patchset merged into master" || :
      fi
    done
  fi
}

set_default_params () {
  if [ -n "$GERRIT_PROJECT" ]; then
    # Remove PRJSUFFIX from master projects
    [[ "$GERRIT_BRANCH" == "master" ]] && unset PRJSUFFIX
    [[ "$GERRIT_BRANCH" == "master" ]] && PRJPREFIX="${PRJPREFIX}fuel-"
    # Detect OBS project for OpenStack packages
    [ -n "$GERRIT_BRANCH" ] && PROJECTNAME=${PRJPREFIX}`echo $GERRIT_BRANCH | cut -d'/' -f2`${PRJSUFFIX}
    # Detect OBS project for other packages
    case ${GERRIT_PROJECT%/*} in
      "openstack-ci/centos64"|"packages/centos6" ) PROJECTNAME=centos-fuel-${GERRIT_BRANCH##*/}${PRJSUFFIX} ;;
      "openstack-ci/precise"|"packages/precise" ) PROJECTNAME=ubuntu-fuel-${GERRIT_BRANCH##*/}${PRJSUFFIX} ;;
      "fuel-qa-team" ) PROJECTNAME=qa-ubuntu ;;
    esac
    # Detect packagename
    case ${GERRIT_PROJECT%/*} in
      "openstack-ci/openstack"|"openstack-build" )
         PACKAGENAME=${GERRIT_PROJECT##*/}
         PACKAGENAME=${PACKAGENAME%-*}
         ;;
      "openstack-ci/centos64"|"packages/centos6" ) PACKAGENAME=${GERRIT_PROJECT##*/} ;;
      "openstack-ci/precise"|"packages/precise" ) PACKAGENAME=${GERRIT_PROJECT##*/} ;;
      "openstack" ) PACKAGENAME=${GERRIT_PROJECT##*/} ;;
      "fuel-qa-team" ) PACKAGENAME=${GERRIT_PROJECT##*/} ;;
    esac
    # Detect source and spec gerrit projects and branches
    case ${GERRIT_PROJECT%/*} in
      "openstack-ci/openstack"|"openstack-build" )
         SRCPROJECT="openstack/$PACKAGENAME"
         SPECPROJECT=$GERRIT_PROJECT
         # Source and Spec branches should have identical names!
         SOURCEBRANCH=$GERRIT_BRANCH
         SPECBRANCH=$GERRIT_BRANCH
         SPECCHANGEID=$GERRIT_REFSPEC
         ;;
      "openstack-ci/centos64"|"packages/centos6" )
         SRCPROJECT=$GERRIT_PROJECT
         SOURCEBRANCH=$GERRIT_BRANCH
         SOURCECHANGEID=$GERRIT_REFSPEC
         ;;
      "openstack-ci/precise"|"packages/precise" )
         SRCPROJECT=$GERRIT_PROJECT
         SOURCEBRANCH=$GERRIT_BRANCH
         SOURCECHANGEID=$GERRIT_REFSPEC
         ;;
      "openstack" )
         SRCPROJECT=$GERRIT_PROJECT
         case ${GERRIT_HOST} in
             "gerrit.mirantis.com" )  SPECPROJECT="openstack-ci/openstack/$PACKAGENAME-build" ;;
             *) SPECPROJECT="openstack-build/$PACKAGENAME-build" ;;
         esac
         # Source and Spec branches should have identical names!
         SOURCEBRANCH=$GERRIT_BRANCH
         SPECBRANCH=$GERRIT_BRANCH
         SOURCECHANGEID=$GERRIT_REFSPEC
         ;;
      "fuel-qa-team" )
         SRCPROJECT=$GERRIT_PROJECT
         SOURCEBRANCH=$GERRIT_BRANCH
         SOURCECHANGEID=$GERRIT_REFSPEC
         ;;
    esac

    MASTERPRJ=$PROJECTNAME
    if [[ "$GERRIT_EVENT_TYPE" == "patchset-created" ]]; then
      PROJECTNAME=${PROJECTNAME}-${GERRIT_CHANGE_NUMBER}
    else
      remove_changeset_project
    fi
  else
    [ -z "$PROJECTNAME" ] && error "Project name isn't given! Exiting!"
    [ -z "$PACKAGENAME" ] && error "Package name isn't given! Exiting!"
    MASTERPRJ=$PROJECTNAME
    if [ -n "$SOURCECHANGEID" ]; then
        _CHANGEID=`echo $SOURCECHANGEID | cut -d'/' -f4`
        PROJECTNAME=${PROJECTNAME}-${_CHANGEID}
    fi
    if [ -n "$SPECCHANGEID" ]; then
        _CHANGEID=`echo $SPECCHANGEID | cut -d'/' -f4`
        PROJECTNAME=${PROJECTNAME}-${_CHANGEID}
    fi
    if [ -n "${SRC_DEPS_PROJECT_PATH}" ]; then
        SRCPROJECT="${SRC_DEPS_PROJECT_PATH}/$PACKAGENAME"
    else
      [ -z "$SRCPROJECT" ] && SRCPROJECT="openstack/$PACKAGENAME"
      case ${GERRIT_HOST} in
         "gerrit.mirantis.com" ) [  -z "$SPECPROJECT" ] && SPECPROJECT="openstack-ci/openstack/$PACKAGENAME-build" ;; 
         * ) [ -z "$SPECPROJECT" ] && SPECPROJECT="openstack-build/$PACKAGENAME-build" ;;
      esac
    fi  
  fi
}

get_task_ids() {
  jira_task_ids=`git log -n1 | grep -oi 'OSCI-[0-9]\+' | sort -u`
  lp_task_ids=`git log -n1 | grep -iE '\bbug\b|\bbugs\b|\bbugfix|\blp\b|\lp[0-9]\+' | grep -o '[0-9]\{5,\}\b' | sort -u`
}

fetch_upstream () {
  # Do not clone projects every time. It makes gerrit sad. Cache it!
  for prj in $SRCPROJECT $SPECPROJECT; do
    # Update code base cache
    [ -d ${GITDATA} ] || mkdir -p ${GITDATA}
    if [ ! -d ${GITDATA}/$prj ]; then
      info "Cache for $prj doesn't exist. Cloning to ${HOME}/gitdata/$prj"
      mkdir -p ${GITDATA}/$prj
      # Lock cache directory
      job_lock ${GITDATA}/${prj}.lock set
      pushd ${GITDATA} &>/dev/null
      info "Cloning sources from $URL/$prj.git ..."
      git clone "$URL/$prj.git" "$prj"
      popd &>/dev/null
    else
      # Lock cache directory
      job_lock ${GITDATA}/${prj}.lock set
      info "Updating cache for $prj"
      pushd ${GITDATA}/$prj &>/dev/null
      info "Fetching sources from $URL/$prj.git ..."
      git fetch --all
      popd &>/dev/null
    fi
    if [[ $prj == $SRCPROJECT ]]; then
      _DIRSUFFIX="src"
      _BRANCH=$SOURCEBRANCH
      [ -z $SOURCECHANGEID ] || _CHANGEID=$SOURCECHANGEID
    fi
    if [[ $prj == $SPECPROJECT ]]; then
      _DIRSUFFIX="spec"
      _BRANCH=$SPECBRANCH
      [ -z $SPECCHANGEID ] || _CHANGEID=$SPECCHANGEID
    fi
    [ -e "${PACKAGENAME}-${_DIRSUFFIX}" ] && rm -rf "${PACKAGENAME}-${_DIRSUFFIX}"
    info "Getting $_DIRSUFFIX from $URL/$prj.git ..."
    cp -R ${GITDATA}/${prj} ${PACKAGENAME}-${_DIRSUFFIX}
    # Unlock cache directory
    job_lock ${GITDATA}/${prj}.lock unset
    pushd ${PACKAGENAME}-${_DIRSUFFIX} &>/dev/null
    switch_to_revision $_BRANCH
    # TODO: do not build package if _CHANGEID different from HEAD
    # Get code from HEAD if change is merged
    [[ $GERRIT_EVENT_TYPE == "change-merged" ]] && unset _CHANGEID
    # If _CHANGEID specified switch to it
    [  -z $_CHANGEID ] || switch_to_changeset $prj $_CHANGEID
    popd &>/dev/null
    case $_DIRSUFFIX in
      "src") gitshasrc=$gitsha
        ;;
      "spec") gitshaspec=$gitsha
        ;;
      *) error "Unknown project type"
        ;;
    esac
    unset _DIRSUFFIX
    unset _BRANCH
    unset _CHANGEID
  done
}

switch_to_revision () {
  info "Switching to branch $*"
  if ! git checkout $*; then
    error "$* not accessible by default clone/fetch"
  else
    git reset --hard origin/$*
    gitsha=`git log -1 --pretty="%h"`
  fi
  if [[ $GERRIT_EVENT_TYPE == "change-merged" ]]; then
      if git remote -v | sed 's|\.git | |' | awk '/origin/ {print $2 " " $3}' | grep "$GERRIT_PROJECT (fetch)" &>/dev/null; then
          get_task_ids
      fi
  fi
}

switch_to_changeset () {
  info "Switching to changeset $2"
  git fetch "$URL/$1.git" $2
  git checkout FETCH_HEAD
  gitsha=`git log -1 --pretty="%h"`
  get_task_ids
}

get_last_commit_info () {
  message=`git log -n 1 | tail -n +5 | sed 's|^ *||'`
  author=`git log -n 1 | grep ^Author: | cut -c9- | sed 's|<.*||'`
  email=`git log -n 1 | grep ^Author: | sed 's|^.*<||;s|>.*$||'`
  cdate=`git log -n 1 | grep ^Date: | cut -d' ' -f4,5,6,8`
}

get_version () {
  # Trying to get Fuel version from branch name of current project
  fuelver=`echo $SOURCEBRANCH | egrep -o 'fuel-[0-9.]*' | egrep -o '[0-9.]*' | cat`
  if [[ $fuelver == "" ]]; then
    # Trying to get Fuel version from:
    # 1. fuel-main project
    # 2. latest version from branch list of current project
    if [ -d ${GITDATA}/openstack/fuel-main ]; then
      # Lock cache directory
      job_lock ${GITDATA}/openstack/fuel-main.lock set
      pushd ${GITDATA}//openstack/fuel-main &>/dev/null
      git fetch --all
      fuelver=`cat config.mk | grep ^PRODUCT_VERSION | cut -d'=' -f2`
      popd &>/dev/null
      # Unlock cache directory
      job_lock ${GITDATA}/openstack/fuel-main.lock unset
    fi
    [[ $fuelver == "" ]] && \
      fuelver=`git branch -a | grep "openstack-ci/fuel-" | sed 's|.*openstack-ci/fuel-||; s|/.*||' | sort -ur | head -1`
    [[ $fuelver == "" ]] && \
      error "Unable to detect latest Fuel version"
  fi
  # Get Ops version from upstream tag
  [[ "$version" == "" ]] && version=`git describe --tags --match "[0-9]*" | sed 's|-.*||'`
}

# Deprecated function
#
#get_obs_revision() {
#  tmpdir="/tmp/tmpdir$RANDOM"
#  mkdir -p $tmpdir
#  pushd $tmpdir
#  #if osc $OBSAPI co $PROJECTNAME $PACKAGENAME &>/dev/null
#  if osc $OBSAPI co $MASTERPRJ $PACKAGENAME &>/dev/null
#  then
#      #cd $PROJECTNAME/$PACKAGENAME
#      cd $MASTERPRJ/$PACKAGENAME
#      revision=`osc $OBSAPI info | grep Revision | cut -d " " -f2`
#  else
#    revision="0"
#  fi
#  [[ "$revision" == "None" ]] && revision="0"
#  popd
#  rm -rf $tmpdir
#}

get_openstack_revision() {
  REPOURL="http://${OBSURL##*/}:82"
  REPONAME=`osc $OBSAPI meta prj $MASTERPRJ | egrep -o "repository name=\"[a-z]+\"" | cut -d'"' -f2`
  # Getting current package revision
  case $REPONAME in
    "centos") # CentOS repo
              # Test metadata file for 10 attempts
              trycnt=10
              while ! wget -q $REPOURL/$MASTERPRJ/$REPONAME/repodata/primary.xml.gz \
                      -O primary.xml.gz &> /dev/null && [ $trycnt -gt 0 ]; do
                sleep 10
                trycnt=$(( $trycnt - 1 ))
              done
              if [ $trycnt -eq 0 ]; then
                rm -f primary.xml.gz
                error "Unable to fetch metadata $REPOURL/$MASTERPRJ/$REPONAME/repodata/primary.xml.gz"
              fi
              revision=`cat primary.xml.gz | gunzip \
                        | grep /$binpackagename- | grep $version | grep mira[0-9] | sort -r | head -1 \
                        | egrep -o mira[0-9]+ | sed 's|mira||'`
              rm -f primary.xml.gz
              ;;
    "ubuntu") # Ubuntu repo
              # Test metadata file for 10 attempts
              trycnt=10
              while ! wget -q $REPOURL/$MASTERPRJ/$REPONAME/Packages.gz -O Packages.gz &> /dev/null && [ $trycnt -gt 0 ]; do
                sleep 10
                trycnt=$(( $trycnt - 1 ))
              done
              if [ $trycnt -eq 0 ]; then
                rm -f Packages.gz
                error "Unable to fetch metadata $REPOURL/$MASTERPRJ/$REPONAME/Packages.gz"
              fi
              revision=`cat Packages.gz | gunzip \
                        | grep /${binpackagename}_ | grep ^File | grep $version |grep mira[0-9] \
                        | sort -r | head -1 | egrep -o mira[0-9]+ | sed 's|mira||'`
              rm -f Packages.gz
              ;;
    *) error "Something went wrong. Can't detect repotype" ;;
  esac
  [ -z "$revision" ] && revision=-1
  # Exit if revision isn't a number
  echo $revision | grep -E '^\-?[0-9]+$' &>/dev/null || error "Wrong revision format"

  # Increment revision
  revision=$(( $revision + 1 ))
}

get_deps_revision() {
  # Getting URL to the master prj repository
  REPOURL="http://${OBSURL##*/}:82"
  REPONAME=`osc $OBSAPI meta prj $MASTERPRJ | egrep -o "repository name=\"[a-z]+\"" | cut -d'"' -f2`
  # Getting current package revision
  case $REPONAME in
    "centos") # CentOS repo
              # Test metadata file
              if ! wget -q $REPOURL/$MASTERPRJ/$REPONAME/repodata/primary.xml.gz -O - | gunzip > /dev/null; then
                error "Unable to fetch metadata $REPOURL/$MASTERPRJ/$REPONAME/repodata/primary.xml.gz"
              fi
              revision=`wget -q $REPOURL/$MASTERPRJ/$REPONAME/repodata/primary.xml.gz -O - | gunzip \
                        | grep /$binpackagename-$version- | grep src\.rpm | sort -r | head -1 \
                        | cut -d'"' -f2 | sed 's|^.*/||; s|\.src\.rpm$||' | awk -F'-' '{print $NF}' \
                        | egrep -o 'mira[0-9]+' | sed 's|^mira||'`
              ;;
    "ubuntu") # Ubuntu repo
              # Test metadata file
              if ! wget -q $REPOURL/$MASTERPRJ/$REPONAME/Packages.gz -O - | gunzip > /dev/null; then
                error "Unable to fetch metadata $REPOURL/$MASTERPRJ/$REPONAME/Packages.gz"
              fi
              revision=`wget -q $REPOURL/$MASTERPRJ/$REPONAME/Packages.gz -O - | gunzip \
                        | grep $binpackagename | grep ^File | grep "\-ubuntu" | cut -d'_' -f2 \
                        | cut -d'-' -f2 | sed 's|.*ubuntu||' | sort -r | head -1`
              ;;
    *) error "Something went wrong. Can't detect repotype" ;;
  esac
  [ -z "$revision" ] && revision=0
  # Increment revision
  revision=$(( $revision + 1 ))
}

get_build_status() {
  REPONAME=`osc $OBSAPI meta prj $PROJECTNAME | egrep -o "repository name=\"[a-z]+\"" | cut -d'"' -f2`
  ARCH="x86_64"

  finished='failed succeeded broken unresolvable disabled excluded'

  status="schedulled"

  timeout=12600
  interval=30

  until [[ $finished =~ $status ]] || [ $timeout -eq 0 ]
  do
    sleep $interval
    timeout=$(( $timeout - $interval ))
    #status=`osc $OBSAPI api /build/$PROJECTNAME/_result | grep "\"$PACKAGENAME\"" | sed 's|^.*code="||;s|".*$||'`
    status=`osc $OBSAPI api /build/$PROJECTNAME/$REPONAME/$ARCH/$PACKAGENAME/_status | grep "<status" | sed 's|^.*code="||;s|".*$||'`
    details=`osc $OBSAPI api /build/$PROJECTNAME/$REPONAME/$ARCH/$PACKAGENAME/_status | grep "<details" | sed 's|^.*<details>||;s|</details>||'`
  done

  [[ $details == "" ]] && details=none

  osc $OBSAPI api /build/$PROJECTNAME/$REPONAME/$ARCH/$PACKAGENAME/_log > ${WRKDIR}/buildlog.txt

  fill_buildresult $status $timeout $REPONAME $PACKAGENAME "$details" ${WRKDIR}/buildlog.txt

  if [[ $status == "failed" ]]
  then
    echo
    echo "Last log:"
    cat ${WRKDIR}/buildlog.txt | tail -20
  fi

  info "Build result: $status"
  info "Full build log: ${BUILD_URL}/artifact/buildlog.txt"

  if [[ $status != "succeeded" ]]
  then
    [[ -z "$details" ]] || echo "Details: $details"
    exit 1
  fi

  if [ $timeout -eq 0 ]; then
     error "Timeout reached. Last build status: $status"
  fi
}

fill_buildresult () {
    #$status $timeout $REPONAME $PACKAGENAME $details ${WRKDIR}/buildlog.txt
    local buildstat=$1
    local istimeout=$2
    local reponame=$3
    local packagename=$4
    local builddetails=$5
    local buildlog=$6
    local failcnt=0
    local xmlfilename=${WRKDIR}/buildresult.xml
    [[ $buildstat == "succeeded" ]] || local failcnt=1
    if [ $timeout -eq 0 ]; then
        local failcnt=1
        local builddetails="Timeout reached. Last build status: $buildstat"
    fi
    [[ $reponame == "centos" ]] && local pkgtype=RPM || local pkgtype=DEB
    echo "<testsuite name=\"Package build\" tests=\"Package build\" errors=\"0\" failures=\"$failcnt\" skip=\"0\">" > $xmlfilename
    echo -n "<testcase classname=\"$pkgtype\" name=\"$packagename\" time=\"0\"" >> $xmlfilename
    if [[ $failcnt == 0 ]]; then
        echo "/>" >> $xmlfilename
    else
        echo ">" >> $xmlfilename
        echo "<failure type=\"Failure\" message=\"$buildstat\">" >> $xmlfilename
        if [[ $buildstat == "failed" ]]; then
            echo "Last log:" >> $xmlfilename
            cat $buildlog | tail -20 | sed 's|<|\&lt;|g; s|>|\&gt;|g' >> $xmlfilename
        else
            echo "Details: $builddetails" >> $xmlfilename
        fi
        echo "</failure>" >> $xmlfilename
        echo "</testcase>" >> $xmlfilename
    fi
    echo "</testsuite>" >> $xmlfilename
    # Copy artifacts to upstream job
    [[ -z ${PARENT_JOB} ]] || cp $xmlfilename ../${PARENT_JOB}/buildresult-${JOB_NAME}-${BUILD_ID}.xml
}

wait_for_packages_in_repo() {
  REPONAME=`osc $OBSAPI meta prj $PROJECTNAME | egrep -o "repository name=\"[a-z]+\"" | cut -d'"' -f2`
  ARCH=`osc $OBSAPI meta prj $PROJECTNAME | grep "<arch>" | awk -F'[<>]' '{print $3}'`
  binfile=`osc $OBSAPI api /build/$PROJECTNAME/$REPONAME/$ARCH/$PACKAGENAME/ | grep "binary filename" | \
           grep -v 'src\.rpm"' | egrep '\.(deb|rpm)"' |  head -1 | cut -d'"' -f2`
  timeout=360
  interval=5

  packs_in_repo=0

  until [ $packs_in_repo -gt 0 ] || [ $timeout -eq 0 ]
  do
    sleep $interval
    timeout=$(( $timeout - $interval ))

    for folder in amd64 all x86_64 noarch; do
      packs_in_repo=$(( $packs_in_repo + `osc $OBSAPI api /published/$PROJECTNAME/$REPONAME/$folder/ | grep $binfile | wc -l` ))
    done
  done

  if [ $timeout -eq 0 ]; then
    error "Timeout reached. Package didn't appear in the repo"
  else
    info "Repository URL: http:/${OBSURL#*/}:82/$PROJECTNAME/$REPONAME"
  fi
}

create_aggregate_package() {
  # Create aggregate if it doesn't exist
  conffile="$MYOUTDIR/create_aggregate_package_config.xml"
  if ! osc $OBSAPI meta pkg $PROJECTNAME aggregate-from-$MASTERPRJ &>/dev/null
  then
    cat >$conffile <<EOF
<package name="aggregate-from-$MASTERPRJ" project="$PROJECTNAME">
  <title></title>
  <description></description>
</package>
EOF
    info "Creating new aggregate package at project $PROJECTNAME"
    [ -z $DISABLEOBS ] && osc $OBSAPI meta pkg -F $conffile $PROJECTNAME aggregate-from-$MASTERPRJ
    [ -z $DISABLEOBS ] && rm -f $conffile
  fi
}

create_package() {
  # Create package if it doesn't exst
  conffile="$MYOUTDIR/create_package_config.xml"
  if ! osc $OBSAPI meta pkg $PROJECTNAME $PACKAGENAME &>/dev/null
  then
    cat >$conffile <<EOF
<package name="$PACKAGENAME" project="$PROJECTNAME">
  <title></title>
  <description></description>
</package>
EOF
    info "Creating new package $PACKAGENAME at project $PROJECTNAME"
    [ -z $DISABLEOBS ] && osc $OBSAPI meta pkg -F $conffile $PROJECTNAME $PACKAGENAME
    [ -z $DISABLEOBS ] && rm -f $conffile
  fi
}

aggregate_packages_from_master_project(){
  create_aggregate_package
  tmpdir="$MYOUTDIR/aggregate"
  [ -e "$tmpdir" ] && rm -rf "$tmpdir"
  mkdir -p $tmpdir
  pushd $tmpdir &>/dev/null
  packages=`osc $OBSAPI ls $MASTERPRJ | grep -v ^$PACKAGENAME$`
  # Get package tree from OBS
  osc $OBSAPI co $PROJECTNAME aggregate-from-$MASTERPRJ
  cd $PROJECTNAME/aggregate-from-$MASTERPRJ
  # Remove old files of package
  rm -f *
  # Create _aggregate file
  echo "<aggregatelist>" > _aggregate
  echo "  <aggregate project=\"$MASTERPRJ\">" >> _aggregate
  for pkg in $packages
  do
    echo "    <package>$pkg</package>" >> _aggregate
  done
  echo "  </aggregate>" >> _aggregate
  echo "</aggregatelist>" >> _aggregate
  [ -z $DISABLEOBS ] && osc $OBSAPI addremove
  # Push updated package to OBS
  [ -z $DISABLEOBS ] && osc $OBSAPI commit -m "Aggregate all packages except $PACKAGENAME from project $PROJECTNAME"
  popd &>/dev/null
  [ -z $DISABLEOBS ] && rm -rf $tmpdir
}

copy_prjconf_from_masterprj() {
  prjconffile="$MYOUTDIR/copy_prjconf_from_masterprj_config.xml"
  osc $OBSAPI meta prjconf $MASTERPRJ > $prjconffile
  [ -z $DISABLEOBS ] && osc $OBSAPI meta prjconf -F $prjconffile $PROJECTNAME
  [ -z $DISABLEOBS ] && rm -f $prjconffile
}

create_project() {
  # Create new or update existing project
  if [[ "$MASTERPRJ" != "$PROJECTNAME" ]]
  then
    conffile="$MYOUTDIR/create_project_config.xml"
    osc $OBSAPI meta prj $MASTERPRJ > $conffile
    # Set Build Trigger Setting to "local" for changeset projects
    if [[ $GERRIT_EVENT_TYPE == "patchset-created" ]]; then
      mv $conffile $conffile.tmp
      cat $conffile.tmp | sed 's|rebuild="[a-z]\+"||' | sed 's|<repository name[a-z=" ]\+|& rebuild="local"|' > $conffile
      rm $conffile.tmp
    fi
    reponame=`cat $conffile | egrep -o "repository name=\"[a-z]+\"" | cut -d'"' -f2`
    [[ "$AGGREGATE" == "false" ]] && masterpath='<path project="'$MASTERPRJ'" repository="'$reponame'"/>'
    sed -i "s|$MASTERPRJ|$PROJECTNAME|" $conffile
    sed -i "s|<title.*|<title>Package $PACKAGENAME from changeset</title>|" $conffile
    [ -n "$masterpath" ] && sed -i "/repository name/a$masterpath" $conffile

    info "Creating new project $PROJECTNAME"
    [ -z $DISABLEOBS ] && osc $OBSAPI meta prj -F $conffile $PROJECTNAME
    [ -z $DISABLEOBS ] && copy_prjconf_from_masterprj
    rm -f $conffile
  fi
}

push_package_to_obs () {
  [ -z $DISABLEOBS ] && create_package
  tmpdir="$MYOUTDIR/obs"
  [ -e "$tmpdir" ] && rm -rf $tmpdir
  mkdir -p $tmpdir
  pushd $tmpdir &>/dev/null
  # Get package tree from OBS
  osc $OBSAPI co $PROJECTNAME $PACKAGENAME
  cd $PROJECTNAME/$PACKAGENAME
  #Remove old files of package
  rm -f *
  #Add new files to package
  cp $MYOUTDIR/*  $tmpdir/$PROJECTNAME/$PACKAGENAME/ || :
  [ -z $DISABLEOBS ] && osc $OBSAPI addremove
  trmessage=`echo "$message" | head -20`
  info "Committing package $PACKAGENAME with message $trmessage"
  #Push updated package to OBS
  [ -z $DISABLEOBS ] && osc $OBSAPI commit -m "$trmessage" || exit 1
  popd
  [ -z $DISABLEOBS ] && rm -rf $tmpdir
}

generate_dsc () {
  #Some magic with sed and awk
  DSCFILE="${MYOUTDIR}/$1_${fullver#*:}.dsc"

  echo "Format: 3.0 (quilt)" > "$DSCFILE"
  cat debian/control | grep -E '^Source' >> "$DSCFILE"
  echo -n "Binary: " >> "$DSCFILE"
  cat debian/control | grep Pack | awk '{print $2}' | sed -e :a -e "/$/N; s/\n/, /; ta" >> "$DSCFILE"
  cat debian/control | grep Archi | tail -1 >> "$DSCFILE"
  echo -n "Version: " >> "$DSCFILE"
  cat debian/changelog | head -1 | awk -F '[(,)]' '{ print $2 }' >> "$DSCFILE"
  #echo $fullver >> "$DSCFILE"
  cat debian/control | grep -E '^Maintainer' >> "$DSCFILE" || :
  cat debian/control | sed -n -e '/^Uploaders/,/^\w/p' | sed '$d' | sed -e :a -e "/$/N; s/\n//; ta" >> "$DSCFILE"
  cat debian/control | sed -n -e '/^Build-Depends:/,/^\w/p' | sed '$d' | sed -e :a -e "/$/N; s/\n//; ta" >> "$DSCFILE"
  cat debian/control | sed -n -e '/^Build-Depends-Indep/,/^\w/p' | sed '$d' | sed -e :a -e "/$/N; s/\n//; ta" >> "$DSCFILE"
  cat debian/control | grep -E '^Standards-Version' >> "$DSCFILE" || :
  cat debian/control | grep -E '^Homepage' >> "$DSCFILE" || :
  cat debian/control | grep -E '^Vcs-Browser' >> "$DSCFILE" || :
  cat debian/control | grep -E '^Vcs-Bzr' >> "$DSCFILE" || :
  echo "Package-List:" >> "$DSCFILE"
  globSection=`cat debian/control | grep -E '^Section' | head -1 | awk '{print $2}'`
  globPriority=`cat debian/control | grep -E '^Priority' | head -1 | awk '{print $2}'`
  cat debian/control | grep -E "^(Package|Section|Priority|$)" | \
    awk 'BEGIN { FS="\n"; RS=""; ORS = " "} \
    { print $1; \
      if (!index ($0, "Section")) \
         print "Section: '$globSection'"; \
      else \
         print $2; \
      if (!index ($0, "Priority")) \
         print "Priority: '$globPriority'"; \
      else \
         print $3; \
      print "\n"}' | \
    sed 's|Package: ||;s|Section: |deb |;s|Priority: ||' | sed -e '1d;$d' >> "$DSCFILE"
  echo "Checksums-Sha1:" >> "$DSCFILE"
  TARBALLS=`find ${MYOUTDIR}/ -maxdepth 1 -name "$1*.tar.gz"`
  for i in $TARBALLS; do
    filename=`ls -la $i | awk '{print $9}' | sed -e "s|^${MYOUTDIR}/||"`
    filesize=`ls -la $i | awk '{print $5}'`
    filechecksum=`sha1sum $i | awk '{print $1}'`
    echo " $filechecksum $filesize $filename" >> "$DSCFILE"
  done
  echo "Checksums-Sha256:" >> "$DSCFILE"
  for i in $TARBALLS; do
    filename=`ls -la $i | awk '{print $9}' | sed -e "s|^${MYOUTDIR}/||"`
    filesize=`ls -la $i | awk '{print $5}'`
    filechecksum=`sha256sum $i | awk '{print $1}'`
    echo " $filechecksum $filesize $filename" >> "$DSCFILE"
  done
  echo "Files:" >> "$DSCFILE"
  for i in $TARBALLS; do
    filename=`ls -la $i | awk '{print $9}' | sed -e "s|^${MYOUTDIR}/||"`
    filesize=`ls -la $i | awk '{print $5}'`
    filechecksum=`md5sum $i | awk '{print $1}'`
    echo " $filechecksum $filesize $filename" >> "$DSCFILE"
  done
  cat debian/control | grep 'Original-Maintainer' | sed 's|XSBC-||' >> "$DSCFILE"
}

get_comment_body () {
    case $REPONAME in
        "centos")
            PKG_DISTRO="RPM" ;;
        "ubuntu")
            PKG_DISTRO="DEB" ;;
        *) ;;
    esac

    FILES=$(osc $OBSAPI api /build/${PROJECTNAME}/${REPONAME}/x86_64/${PACKAGENAME} \
                | cut -d '"' -f2 \
                | grep -v "src\.rpm$" \
                | grep "\.${PKG_DISTRO,,}$")

    echo -e "${PKG_DISTRO} package ${PACKAGENAME} has been built for project $SRCPROJECT"
    echo -e "Package version == ${version}, package release == ${release}"
    echo -e ""
    echo -e "Changeset: $GERRIT_CHANGE_URL
project:   $GERRIT_PROJECT
branch:    $GERRIT_BRANCH
author:    $GERRIT_CHANGE_OWNER_NAME
committer: $GERRIT_PATCHSET_UPLOADER_NAME
subject:   $GERRIT_CHANGE_SUBJECT
status:    $GERRIT_EVENT_TYPE"
    echo -e ""
    echo -e "Files placed on repository:
$FILES"
    echo -e ""
    if [ "$GERRIT_EVENT_TYPE" = "patchset-created" ]; then
        echo -e "NOTE: Changeset is not merged, created temporary package repository."
    elif [ "$GERRIT_EVENT_TYPE" = "change-merged" ]; then
        echo -e "Changeset merged. Package placed on primary repository"
    fi
    echo -e "${PKG_DISTRO} repository URL: ${REPOURL}/$PROJECTNAME/${REPONAME}"
}

# parameters: "comment body (may be multiline)" issue_id issue_id ...
jira_comment () {
  if [[ -f ~/.jira-cli/config ]]; then
    local COMMENT=$1
    shift
    local TASK_IDS="$@"
    if [ -n "$TASK_IDS" ]; then
      for t in $TASK_IDS; do
         jira-cli comment $t -c "$COMMENT"
      done
    fi
  fi
}

# parameters: "comment body (may be multiline)" bug_id bug_id ...
lp_comment () {
  if [[ -f ~/.launchpadlib/creds ]]; then
    local COMMENT=$1
    shift
    local TASK_IDS="$@"
    if [ -n "$TASK_IDS" ]; then
      for t in $TASK_IDS; do
        lp_cli.py $LP_PROJECT -o "$LP_PROJECT_AFFECTED" comment $t "$COMMENT"
        #if [ "$GERRIT_EVENT_TYPE" = "patchset-created" ]; then
        #    BUG_STATUS="In Progress"
        #elif [ "$GERRIT_EVENT_TYPE" = "change-merged" ]; then
        #    BUG_STATUS="Fix Committed"
        #fi
        #[ -n "$BUG_STATUS" ] && lp_cli.py $LP_PROJECT -o "$LP_PROJECT_AFFECTED" update $t --status "$BUG_STATUS"
      done
    fi
  fi
}
