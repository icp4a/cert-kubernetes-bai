#!/bin/bash
###############################################################################
#
# LICENSED MATERIALS - PROPERTY OF IBM
#
# (C) COPYRIGHT IBM CORP. 2022. ALL RIGHTS RESERVED.
#
# US GOVERNMENT USERS RESTRICTED RIGHTS - USE, DUPLICATION OR
# DISCLOSURE RESTRICTED BY GSA ADP SCHEDULE CONTRACT WITH IBM CORP.
#
###############################################################################

echo " "
echo " "
echo "##########################################################################################################"
echo "                              Running BAI Post install Check"
echo "##########################################################################################################"

SCRIPT_START_TIME=`date`
echo "Start time : ${SCRIPT_START_TIME}"

cd $DIR
mkdir logs 2> /dev/null
LOG_DIR=$DIR/logs

consoleFooter()
{
  echo "##########################################################################################################"
  SCRIPT_END_TIME=`date`
  echo "End Time: ${SCRIPT_END_TIME}"
  if (( $SECONDS > 3600 )) ; then
      let "hours=SECONDS/3600"
      let "minutes=(SECONDS%3600)/60"
      let "seconds=(SECONDS%3600)%60"
      echo "${1} Completed in $hours hour(s), $minutes minute(s) and $seconds second(s)"
  elif (( $SECONDS > 60 )) ; then
      let "minutes=(SECONDS%3600)/60"
      let "seconds=(SECONDS%3600)%60"
      echo "${1} Completed in $minutes minute(s) and $seconds second(s)"
  else
      echo "${1} Completed in $SECONDS seconds"
  fi
  echo "##########################################################################################################"
  echo ""
}

printHeaderMessage()
{
 echo ""
  if [  "${#2}" -ge 1 ] ;then
      echo "${2}${1}"
  else
      echo "${BLUE_TEXT}${1}"
  fi
  echo "################################################################${RESET_TEXT}"
  sleep 1
}

OS()
{
  printHeaderMessage "Checking OS before continuing on"
  OS=`find /etc | grep -c os-release`
  if [[ "$OS" == "1" || "$OS" == "2" ]]; then
    IS_UBUNTU=`cat /etc/*-release | grep ID | grep -c Ubuntu`
    IS_RH=`cat /etc/os-release | grep ID | grep -c rhel`
    echo "Linux is being used"
    source ~/.profile 2> /dev/null
  else
    IS_MAC=`sw_vers | grep ProductName | awk '{print $2}' | grep -c macOS`
    source ~/.bash_profile 2> /dev/null
    echo "macOS is being used"
  fi
  if [ "$IS_MAC" == "1" ]; then
    MAC=true
  else
    IS_MAC=0
  fi
}

operatorAndAPIVersions()
{
  # Auto-detect the namespace where InsightsEngine CR is deployed
  # Try --all-namespaces first, fall back to -A flag
  BAI_AUTO_NAMESPACE=`${CLI_CMD} get InsightsEngine --all-namespaces --no-headers 2> /dev/null | awk 'NR==1' | awk '{print $1}'`
  if [ -z "$BAI_AUTO_NAMESPACE" ]; then
    BAI_AUTO_NAMESPACE=`${CLI_CMD} get InsightsEngine -A --no-headers 2> /dev/null | awk 'NR==1' | awk '{print $1}'`
  fi
  export BAI_AUTO_NAMESPACE

  # Fetch deployment name in the auto-detected namespace
  BAI_DEPLOYMENT_NAME=`${CLI_CMD} get InsightsEngine -n ${BAI_AUTO_NAMESPACE} --no-headers 2> /dev/null | awk 'NR==1' | awk '{print $1}'`
  export BAI_DEPLOYMENT_NAME

  # Fetch deployment type from InsightsEngine CR spec
  BAI_DEPLOYMENT_TYPE=`${CLI_CMD} get InsightsEngine ${BAI_DEPLOYMENT_NAME} -n ${BAI_AUTO_NAMESPACE} -o jsonpath='{.spec.deployment_type}' 2> /dev/null`
  if [ -z "$BAI_DEPLOYMENT_TYPE" ]; then
    BAI_DEPLOYMENT_TYPE=`${CLI_CMD} get InsightsEngine ${BAI_DEPLOYMENT_NAME} -n ${BAI_AUTO_NAMESPACE} -o jsonpath='{.spec.shared_configuration.sc_deployment_type}' 2> /dev/null`
  fi
  if [ -z "$BAI_DEPLOYMENT_TYPE" ]; then
    BAI_DEPLOYMENT_TYPE="Production"
  fi
  export BAI_DEPLOYMENT_TYPE

  # Detect if OLM-based deployment
  OLM_DEPLOYMENT="false"
  OLM_CHECK=`${CLI_CMD} get csv -n ${BAI_AUTO_NAMESPACE} 2> /dev/null | grep -c "ibm-insights-engine-operator"`
  if [ "$OLM_CHECK" -ge 1 ]; then
    OLM_DEPLOYMENT="true"
  fi
  export OLM_DEPLOYMENT

  CS_DEPLOYMENT_NAME=`${CLI_CMD} get commonservices -n ${BAI_AUTO_NAMESPACE} 2> /dev/null | awk 'NR==2' | awk '{print $1}'`
  export CS_DEPLOYMENT_NAME
}

validateOCPAccess()
{
  printHeaderMessage "Validate OCP Access"

  OCP_CONSOLE_URL=`${CLI_CMD} whoami --show-console 2> /dev/null`
  if [ -z  "${OCP_CONSOLE_URL}" ]; then
    echo "${RED_TEXT}${ICON_FAIL} ${RESET_TEXT} No access to cluster via oc command. PLease log in and try again...${RESET_TEXT}"
    consoleFooter "${CP_FUNCTION_NAME}"
    exit
  fi
  echo "${BLUE_TEXT}${ICON_SUCCESS} PASSED ${RESET_TEXT} Access to cluster via oc command${RESET_TEXT}"

  OCP_CLUSTER_VERSION=`${CLI_CMD} get clusterversion 2> /dev/null | grep version | awk '{print  $2 }'`
  OCP_SERVER_VERSION=`${CLI_CMD} get clusterversion 2> /dev/null | grep version | awk '{print  $2 }'`
  ADMIN_USER=`${CLI_CMD} whoami`

  CLUSTER_NAME=`${CLI_CMD} -n kube-system get configmap cluster-info -o yaml 2> /dev/null | grep '"name":'  | grep -v cluster-info | sed 's/"//g' | sed 's/,//g' | sed "s/name: //g" | sed "s/ //g"`
  #If cm cluster-info does not exist, check for cm cluster-config-v1
  if [ -z ${CLUSTER_NAME} ]; then
    CLUSTER_NAME=`${CLI_CMD} -n kube-system get configmap cluster-config-v1 -o yaml 2> /dev/null | grep name | awk 'NR==3' | awk '{print $2}'`
  fi
  if [ -z ${CLUSTER_NAME} ]; then
    CLUSTER_NAME=`${CLI_CMD} describe infrastructure/cluster 2> /dev/null | grep "Infrastructure Name" | awk '{print $3}'`
  fi

  CLUSTER_DOMAIN=`${CLI_CMD} describe infrastructure/cluster 2> /dev/null | grep "Etcd Discovery Domain" | awk '{print $4}'`

  if [ -z "$CLUSTER_DOMAIN" ]; then
     CLUSTER_BASE_DOMAIN=`${CLI_CMD} -n kube-system get configmap cluster-config-v1 -o yaml 2> /dev/null| grep baseDomain | awk '{print $2}'`
     if [ ! -z "$CLUSTER_BASE_DOMAIN" ]; then
        CLUSTER_DOMAIN="$CLUSTER_NAME"."$CLUSTER_BASE_DOMAIN"
     fi
  fi

  if [ -z "$CLUSTER_DOMAIN" ]; then
     CLUSTER_BASE_DOMAIN=`${CLI_CMD} -n kube-system get configmap cluster-config -o yaml 2> /dev/null | grep "baseDomain" | awk '{print $2}'`
     if [ ! -z $CLUSTER_BASE_DOMAIN ]; then
        CLUSTER_DOMAIN="$CLUSTER_NAME"."$CLUSTER_BASE_DOMAIN"
     fi
  fi

  # Load operator and API versions (also sets BAI_AUTO_NAMESPACE, BAI_DEPLOYMENT_NAME, BAI_DEPLOYMENT_TYPE, OLM_DEPLOYMENT)
  operatorAndAPIVersions

  export CLUSTER_NAME=$CLUSTER_NAME
  export CLUSTER_DOMAIN=$CLUSTER_DOMAIN

  echo "Cluster name                                  : $CLUSTER_NAME "
  echo "Cluster version                               : $OCP_CLUSTER_VERSION "
  echo "Console URL                                   : $OCP_CONSOLE_URL "
  echo "Logged in as user                             : $ADMIN_USER"
  echo "Using namespace                               : $BAI_AUTO_NAMESPACE"
  echo "Deployment name                               : $BAI_DEPLOYMENT_NAME"
  echo "Deployment type                               : $BAI_DEPLOYMENT_TYPE"
  echo "OLM deployment                                : $OLM_DEPLOYMENT"

  if [ -z "${BAI_AUTO_NAMESPACE}" ] || [ -z "${BAI_DEPLOYMENT_NAME}" ]; then
   echo "${RED_TEXT} *** No InsightsEngine deployment found in any namespace. ***  ${RESET_TEXT}"
   consoleFooter "${CP_FUNCTION_NAME}"
   exit
  fi
}


BAIServiceProbe()
{
    printHeaderMessage "BAI Service Readiness/Liveness"
    cd $DIR

    helper/post-install/probe/checkURL4BA.sh $CLUSTER_DOMAIN $BAI_AUTO_NAMESPACE $PROBE_USER_API_KEY $PROBE_USER_NAME $PROBE_USER_PASSWORD $PROBE_VERBOSE

    echo
    consoleFooter "${CP_FUNCTION_NAME}"
    exit
}

cleanUp()
{
 cd $DIR
 rm -Rf logs 2> /dev/null
}