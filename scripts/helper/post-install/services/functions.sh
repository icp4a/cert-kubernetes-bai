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

validateOCPAccess()
{
  printHeaderMessage "Validate OCP Access"

  OCP_CONSOLE_URL=`oc whoami --show-console 2> /dev/null`
  if [ -z  "${OCP_CONSOLE_URL}" ]; then
    echo "${RED_TEXT}${ICON_FAIL} ${RESET_TEXT} No access to cluster via oc command. PLease log in and try again...${RESET_TEXT}"
    consoleFooter "${CP_FUNCTION_NAME}"
    exit
  fi
  echo "${BLUE_TEXT}${ICON_SUCCESS} PASSED ${RESET_TEXT} Access to cluster via oc command${RESET_TEXT}"

  OCP_CLUSTER_VERSION=`oc get clusterversion 2> /dev/null | grep version | awk '{print  $2 }'`
  OCP_SERVER_VERSION=`oc get clusterversion 2> /dev/null | grep version | awk '{print  $2 }'`
  ADMIN_USER=`oc whoami`
  BAI_AUTO_NAMESPACE=`oc project -q`

  CLUSTER_NAME=`oc -n kube-system get configmap cluster-info -o yaml 2> /dev/null | grep '"name":'  | grep -v cluster-info | sed 's/"//g' | sed 's/,//g' | sed "s/name: //g" | sed "s/ //g"`
  #If cm cluster-info does not exist, check for cm cluster-config-v1
  if [ -z ${CLUSTER_NAME} ]; then
    CLUSTER_NAME=`oc -n kube-system get configmap cluster-config-v1 -o yaml 2> /dev/null | grep name | awk 'NR==3' | awk '{print $2}'`
  fi
  if [ -z ${CLUSTER_NAME} ]; then
    CLUSTER_NAME=`oc describe infrastructure/cluster 2> /dev/null | grep "Infrastructure Name" | awk '{print $3}'`
  fi

  CLUSTER_DOMAIN=`oc describe infrastructure/cluster 2> /dev/null | grep "Etcd Discovery Domain" | awk '{print $4}'`

  if [ -z "$CLUSTER_DOMAIN" ]; then
     CLUSTER_BASE_DOMAIN=`oc -n kube-system get configmap cluster-config-v1 -o yaml 2> /dev/null| grep baseDomain | awk '{print $2}'`
     if [ ! -z "$CLUSTER_BASE_DOMAIN" ]; then
        CLUSTER_DOMAIN="$CLUSTER_NAME"."$CLUSTER_BASE_DOMAIN"
     fi
  fi

  if [ -z "$CLUSTER_DOMAIN" ]; then
     CLUSTER_BASE_DOMAIN=`oc -n kube-system get configmap cluster-config -o yaml 2> /dev/null | grep "baseDomain" | awk '{print $2}'`
     if [ ! -z $CLUSTER_BASE_DOMAIN ]; then
        CLUSTER_DOMAIN="$CLUSTER_NAME"."$CLUSTER_BASE_DOMAIN"
     fi
  fi

  export BAI_AUTO_NAMESPACE=$BAI_AUTO_NAMESPACE
  export CLUSTER_NAME=$CLUSTER_NAME
  export CLUSTER_DOMAIN=$CLUSTER_DOMAIN

  echo "Cluster name                                  : $CLUSTER_NAME "
  echo "Cluster version                               : $OCP_CLUSTER_VERSION "
  echo "Console URL                                   : $OCP_CONSOLE_URL "
  echo "Logged in as user                             : $ADMIN_USER"
  echo "Using namespace                               : $BAI_AUTO_NAMESPACE"
  echo "Deployment name                               : $BAI_DEPLOYMENT_NAME"

  if [ -z ${BAI_DEPLOYMENT_NAME} ]; then
   echo "${RED_TEXT} *** No deployment found in namespace $BAI_AUTO_NAMESPACE. ***  ${RESET_TEXT}"
   consoleFooter "${CP_FUNCTION_NAME}"
   exit
  fi
}
BAI_DEPLOYMENT_NAME=`oc get InsightsEngine  2> /dev/null | awk 'NR==2' | awk '{print $1}'`
export BAI_DEPLOYMENT_NAME=$BAI_DEPLOYMENT_NAME

CS_DEPLOYMENT_NAME=`oc get commonservices  2> /dev/null | awk 'NR==2' | awk '{print $1}'`
export CS_DEPLOYMENT_NAME=$CS_DEPLOYMENT_NAME


cpfs_status()
{
printHeaderMessage "CPFS Status - Common Service Components status"
# Retrieve the JSON output
json_output=$(oc get commonservices ${CS_DEPLOYMENT_NAME} -n ${BAI_AUTO_NAMESPACE} -o json)

# Initialize an empty array
declare -A operator_array

# Extract name and version for each operator and store as key-value pairs
while IFS= read -r line; do
    name=$(echo "$line" | jq -r '.name')
    version=$(echo "$line" | jq -r '.version')
    # Removing unnecessary quotes
    name="${name//\"}"
    version="${version//\"}"
    # Storing in the array
    operator_array["$name"]=$version
done <<< "$(echo "$json_output" | jq -c '.status.bedrockOperators[]')"
VALUE_COLOUR="\e[31m"
COLOUR="\e[0m"

# Print the values in the array
for key in "${!operator_array[@]}"; do
    if [ "$key" = "ibm-iam-operator" ]; then
        echo -e "${VALUE_COLOUR}$key${COLOUR} : Installed -  Version : ${VALUE_COLOUR}${operator_array[$key]}${COLOUR}"
      elif [[ "$key" = "cloud-native-postgresql" ]]; then
        echo -e "${VALUE_COLOUR}$key${COLOUR} : Installed -  Version : ${VALUE_COLOUR}${operator_array[$key]}${COLOUR}"
      elif [[ "$key" = "ibm-bts-operator" ]]; then
        echo -e "${VALUE_COLOUR}$key${COLOUR} : Installed -  Version : ${VALUE_COLOUR}${operator_array[$key]}${COLOUR}"
      elif [[ "$key" = "ibm-elasticsearch-operator" ]]; then
        echo -e "${VALUE_COLOUR}$key${COLOUR} : Installed -  Version : ${VALUE_COLOUR}${operator_array[$key]}${COLOUR}"
      elif [[ "$key" = "ibm-opencontent-flink" ]]; then
        echo -e "${VALUE_COLOUR}$key${COLOUR} : Installed -  Version : ${VALUE_COLOUR}${operator_array[$key]}${COLOUR}"
      fi
done
}

cleanUp()
{
 cd $DIR
 rm -Rf logs 2> /dev/null
}