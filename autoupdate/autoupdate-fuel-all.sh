#!/bin/bash

################ debug vars #########################
#GERRITPRJ=stackforge/fuel-web.git
#export PACKAGENAME=nailgun-agent
#export PROJECTNAME=fuel-4.1-testing
#export NEEDUPDATE=true
#export WRKDIR=/home/dburmistrov/git/obs/
#####################################################
GERRIT_USER='fuel-osci-bot'
#PACKAGES="nailgun-agent nailgun-mcagents nailgun-net-check fencing-agent fuel-ostf python-fuelclient fuelmenu shotgun nailgun rubygem-naily"
PACKAGES="nailgun-agent nailgun-mcagents nailgun-net-check fencing-agent fuel-ostf python-fuelclient python-tasklib fuelmenu shotgun nailgun ruby21-rubygem-astute ruby21-nailgun-mcagents"

[ -z "$SRCBRANCH" ] && export SRCBRANCH=master
[ -z "$WRKDIR" ] && export WRKDIR=`pwd`
[ -n "${GERRITCHURL}" ] && echo && echo "Gerrit change url: ${GERRITCHURL}" && echo

fetch_github () {
  GITHUBNAME=${1##*/}
  GITHUBNAME=${GITHUBNAME%.*}
  if [ -d $WRKDIR/data/$GITHUBNAME ]; then
      pushd $WRKDIR/data/$GITHUBNAME &>/dev/null
      git fetch --all
      git checkout -B $SRCBRANCH origin/$SRCBRANCH
      popd &>/dev/null
  else
    mkdir -p $WRKDIR/data
    git clone $1 $WRKDIR/data/$GITHUBNAME
    pushd $WRKDIR/data/$GITHUBNAME &>/dev/null
    git checkout -B $SRCBRANCH origin/$SRCBRANCH
    popd &>/dev/null
  fi
}

if [ -n "$GERRITPRJ" ]; then
  case ${GERRITPRJ%.*} in
    "stackforge/fuel-web" )
        fetch_github "https://review.openstack.org/$GERRITPRJ"
        bash $WRKDIR/autoupdate/autoupdate-nailgun-agent.sh
        bash $WRKDIR/autoupdate/autoupdate-fencing-agent.sh
        bash $WRKDIR/autoupdate/autoupdate-shotgun.sh
        bash $WRKDIR/autoupdate/autoupdate-python-fuelclient.sh
        bash $WRKDIR/autoupdate/autoupdate-python-tasklib.sh
        bash $WRKDIR/autoupdate/autoupdate-fuelmenu.sh
        bash $WRKDIR/autoupdate/autoupdate-nailgun.sh
        #bash $WRKDIR/autoupdate/autoupdate-rubygem-naily.sh
        bash $WRKDIR/autoupdate/autoupdate-nailgun-net-check.sh
        ;;
    "stackforge/fuel-ostf" )
        fetch_github "https://review.openstack.org/$GERRITPRJ"
        bash $WRKDIR/autoupdate/autoupdate-fuel-ostf.sh
        ;;
    "stackforge/fuel-astute" )
        fetch_github "https://review.openstack.org/$GERRITPRJ"
        bash $WRKDIR/autoupdate/autoupdate-nailgun-mcagents.sh
        bash $WRKDIR/autoupdate/autoupdate-ruby21-nailgun-mcagents.sh
        bash $WRKDIR/autoupdate/autoupdate-ruby21-rubygem-astute.sh
        ;;
    "stackforge/fuel-main" )
        fetch_github "https://review.openstack.org/$GERRITPRJ"
        bash $WRKDIR/autoupdate/autoupdate-nailgun-agent.sh
        bash $WRKDIR/autoupdate/autoupdate-fencing-agent.sh
        bash $WRKDIR/autoupdate/autoupdate-shotgun.sh
        bash $WRKDIR/autoupdate/autoupdate-python-fuelclient.sh
        bash $WRKDIR/autoupdate/autoupdate-python-tasklib.sh
        bash $WRKDIR/autoupdate/autoupdate-fuelmenu.sh
        bash $WRKDIR/autoupdate/autoupdate-nailgun.sh
        bash $WRKDIR/autoupdate/autoupdate-nailgun-net-check.sh
        bash $WRKDIR/autoupdate/autoupdate-fuel-ostf.sh
        bash $WRKDIR/autoupdate/autoupdate-nailgun-mcagents.sh
        ;;
    * ) echo "Unknown repo: ${GERRITPRJ}" ;;
  esac
else
  for githubname in fuel-web fuel-ostf fuel-astute fuel-main; do
    fetch_github "https://review.openstack.org/stackforge/$githubname"
  done 
  ##if GERRIT TRIGGER 
  if [ "${BUILD_CAUSE}" == "SCMTRIGGER" ] ; then
    PACKAGES=""
    pushd $WRKDIR/data/fuel-main/
    echo "MARK: fetching current patchset"
   git fetch -q ssh://$GERRIT_USER@$GERRIT_HOST:$GERRIT_PORT/stackforge/fuel-main $GERRIT_REFSPEC && git checkout -q FETCH_HEAD
    for rpmspec in fuelmenu nailgun ruby21-rubygem-astute fuel-agent fuel-ostf python-fuelclient ruby21-nailgun-mcagents shotgun; do
       if [ "`git diff HEAD^ HEAD -- ./packages/rpm/specs/$rpmspec.spec`" ] ;
         then PACKAGES="$PACKAGES $rpmspec"
       fi
    done
    for dualspec in fencing-agent nailgun-agent nailgun-net-check python-tasklib nailgun-mcagents; do
      [[ "`git diff HEAD^ HEAD -- ./packages/rpm/specs/$dualspec.spec`" ]] || [[ "`git diff HEAD^ HEAD -- ./packages/deb/specs/$dualspec`" ]] && PACKAGES="$PACKAGES $dualspec"
    done
    popd
  fi
  if [[ "$PACKAGENAME" == "all" ]]; then
    for package in $PACKAGES; do
      [ -f "$WRKDIR/autoupdate/autoupdate-$package.sh" ] && bash $WRKDIR/autoupdate/autoupdate-$package.sh
    done
  else
    [ -f "$WRKDIR/autoupdate/autoupdate-$PACKAGENAME.sh" ] && bash $WRKDIR/autoupdate/autoupdate-$PACKAGENAME.sh
  fi
fi

