#!/bin/bash

###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################

# This script contains shared utility functions and environment variables.
# CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TEMP_FOLDER=${CUR_DIR}/.tmp
mkdir -p $TEMP_FOLDER

# Define the required Java version based on BAI release
REQUIRED_JAVA_MAJOR_VERSION=17  # Semeru 17 is required for BAI S 


# Directory for common service script
COMMON_SERVICES_SCRIPT_FOLDER=${CUR_DIR}/cpfs/installer_scripts/cp3pt0-deployment

COMMON_SERVICES_SCRIPT_YQ_FOLDER=${CUR_DIR}/cpfs/yq


# Start of Section for BAI Rancher specific variables

# BAI CNCF folder
BAI_CNCF_FOLDER=${PARENT_DIR}/cncf/scripts

#OLM VARIABLES while installing olm on Rancher
OLM_MINIMAL_VERSION=v0.23.1
OLM_VERSION=v0.27.0

#Licensing service related variables that required during the creation of subscription and the checks.
# NEED TO BE UPDATED WHEN WE UPDATE THE VERSIONS
LICENSING_SERVICE_CHANNEL=v4.2
LICENSING_SERVICE_TARGET_VERSION="4.2.24"

#Cert Manager related variables that required during the creation of subscription and the checks.
# NEED TO BE UPDATED WHEN WE UPDATE THE VERSIONS
CERT_MANAGER_CHANNEL=v4.2
CERT_MANAGER_TARGET_VERSION="4.2.23"
#Cert manager owner.
CERT_MANAGER_V1ALPHA1_OWNER="operator.ibm.com/v1alpha1"
CERT_MANAGER_V1_OWNER="operator.ibm.com/v1"

# CATALOG SOURCE file name
CATALOG_SOURCE_FILENAME=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
# OPERATOR GROUP file name
OPERATOR_GROUP_FILENAME=${PARENT_DIR}/descriptors/op-olm/operator_group.yaml
# SUBSCRIPTION file name
SUBSCRIPTION_FILENAME=${PARENT_DIR}/descriptors/op-olm/subscription.yaml

#The below are upgrade script variables needed for Rancher but these are currently not required for this release
licensing_service_minimal_version_for_upgrade="4.2.0"
cert_manager_minimal_version_for_upgrade="4.2.0"
cs_minimal_version_for_upgrade="4.6.2" # Minimal supported Common Service version before upgrading from 25.0.0 (version from 24.0.0)
cs_maximal_version_for_upgrade="5.0.0" # Maximal supported Common Service version before upgrading from 25.0.0
cs_minimal_version_for_ifix="4.10.0" # Minimal supported Common Service version before upgrading for ifix
cs_maximal_version_for_ifix="5.0.0" # Maximal supported Common Service version before upgrading for ifix

# Need this for the BAI S on CNCF dev mode so that we can get the image repository
BAI_S_FC_CR=${PARENT_DIR}/descriptors/patterns/ibm_cp4a_cr_production_FC_bai.yaml

#Change required each sprint for using dev mode
CURRENT_SPRINT_TAG="26.0.0-IF002"

#DBACLD-194974: This variable is used to specify the version that will block EDB option for IM ZEN BTS.The user will HAVE to use external postgres for this. It should be in the format of ${BAI_RELEASE_BASE}_${BAI_PATCH_VERSION}
# For 25.0.1_GA we will remove the Starter option and EDB option.
VERSION_TO_SKIP_EDB="26.0.0_GA"


# End of Section for BAI Rancher specific variables


PREREQUISITES_FOLDER=${CUR_DIR}/bai-prerequisites/project/$1
PREREQUISITES_FOLDER_BAK=${CUR_DIR}/bai-prerequisites-backup/project/$1
PROPERTY_FILE_FOLDER=${PREREQUISITES_FOLDER}/propertyfile
GENERATED_INGRESS_FILE_FOLDER=${PREREQUISITES_FOLDER}/ingress_template
GENERATED_API_GATEWAY_FOLDER=${PREREQUISITES_FOLDER}/api_gateway_template
PROPERTY_FILE_FOLDER_BAK=${PREREQUISITES_FOLDER_BAK}/propertyfile
CREATE_SECRET_SCRIPT_FILE=$PREREQUISITES_FOLDER/create_secret.sh

LDAP_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/ldap
ZEN_DB_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/zen_external_db
IM_DB_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/im_external_db
BTS_DB_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/bts_external_db

TEMPORARY_PROPERTY_FILE=${TEMP_FOLDER}/.TEMPORARY.property
LDAP_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/bai_LDAP.property
USER_PROFILE_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/bai_user_profile.property

# Directory and template file for secret YAML template 
SECRET_FILE_FOLDER=${PREREQUISITES_FOLDER}/secret_template

LDAP_SSL_SECRET_FOLDER=${SECRET_FILE_FOLDER}/bai_ldap_ssl_secret
ZEN_SECRET_FOLDER=${SECRET_FILE_FOLDER}/zen_external_db
ZEN_SECRET_FILE=${ZEN_SECRET_FOLDER}/ibm-zen-metastore-secret.sh
ZEN_CONFIGMAP_FILE=${ZEN_SECRET_FOLDER}/ibm-zen-metastore-cm.yaml

IM_SECRET_FOLDER=${SECRET_FILE_FOLDER}/im_external_db
IM_SECRET_FILE=${IM_SECRET_FOLDER}/ibm-im-datastore-edb-secret.sh
IM_CONFIGMAP_FILE=${IM_SECRET_FOLDER}/ibm-im-datastore-edb-cm.yaml

BTS_SECRET_FOLDER=${SECRET_FILE_FOLDER}/bts_external_db
BTS_SSL_SECRET_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-ssl-secret.sh
BTS_SECRET_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-user-secret.yaml
BTS_CONFIGMAP_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-cm.yaml

CP4A_LDAP_SSL_SECRET_FILE=${LDAP_SSL_SECRET_FOLDER}/ibm-bai-ldap-ssl-cert-secret.sh


LDAP_SECRET_FILE=${SECRET_FILE_FOLDER}/ldap-bind-secret.yaml

# Release/Patch version for BAI
# BAI_RELEASE_BASE is for fetch content/foundation operator pod, only need to change for major release.
BAI_RELEASE_BASE="26.0.0"
BAI_PATCH_VERSION="IF002"
# BAI_RELEASE_BASE_MAJOR_VERSION is used in certain checks where we used to hardcode to see if a upgrade is not ifix to ifix,change this only for major release
BAI_RELEASE_BASE_MAJOR_VERSION="26.0"
# BAI_CSV_VERSION is for checking BAI operator upgrade status, need to update for each IFIX
BAI_CSV_VERSION="v26.0.2"
# BAI_CHANNEL_VERSION is for switch BAI operator upgrade status, need to update for major release
BAI_CHANNEL_VERSION="v26.0"
# CS_OPERATOR_VERSION is for checking CPFS operator upgrade status, need to update for each IFIX
CS_OPERATOR_VERSION="v4.19.2"
# CS_CHANNEL_VERSION is for for CPFS script -c option, need to update for each IFIX
CS_CHANNEL_VERSION="v4.19"
# CS CHANNEL VERSION that is used in the KC
CS_CHANNEL_KC="4.x_cd"
# CERT_LICENSE_CHANNEL_VERSION is for for IBM cert-manager/licensing script -c option, need to update for each IFIX
CERT_LICENSE_CHANNEL_VERSION="v4.2"
# CS_CATALOG_VERSION is for CPFS script -s option, need to update for each IFIX
CS_CATALOG_VERSION="ibm-cs-install-catalog-v4-19-0"
# ZEN_OPERATOR_VERSION is for checking ZenService operator upgrade status, need to update for each IFIX
ZEN_OPERATOR_VERSION="v6.10.5"
# BTS_CHANNEL_VERSION is for for BTS, need to update for each IFIX
BTS_CHANNEL_VERSION="v3.35"
# BTS_CATALOG_VERSION is for BTS 3.35.13.
BTS_CATALOG_VERSION="ibm-bts-operator-catalog-v3-35"
# REQUIREDVER_BTS is for checking bts operator upgrade status before run removal_iaf.sh, need to update for each IFIX
REQUIREDVER_BTS="3.35.13"
# REQUIREDVER_POSTGRESQL is for checking postgresql operator upgrade status before run removal_iaf.sh, need to update for each IFIX
REQUIREDVER_POSTGRESQL="1.28.4"
# EVENTS_OPERATOR_VERSION is for checking IBM Events operator upgrade status, need to update for each IFIX
EVENTS_OPERATOR_VERSION="v5.2.1"
# List of BAI versions that are supported for upgrade to $BAI_CSV_VERSION
# When setting to an empty array, only fresh installation is supported.
# In 26.0.0-IF001, we will support upgrade from 25.0.4, 25.1.1, and 24.0.6, which means if the customer is on 24.1.x, they need to first upgrade to 25.0.4 before upgrading to 26.0.0-IF001.
MINIMUM_SUPPORTED_UPGRADE_VERSIONS=(24.0.7 25.0.4 25.1.1 26.0.0)

# UMS related variables
# UMS_CHANNEL_VERSION is for UMS, need to update for each IFIX
UMS_CHANNEL_VERSION="v1.0"
# UMS_CSV_VERSION is for UMS, need to update for each IFIX
UMS_CSV_VERSION="v1.0.7"
# UMS_CATALOG_VERSION is the current UMS catalog name.
UMS_CATALOG_VERSION="ibm-usage-metering-catalog"
# UMS connection point secret name
UMS_CONNECTION_POINT_SECRET_NAME="bai-ums-secret"
# UMS OPERATOR subscription template location
UMS_OLM_SUBSCRIPTION=${PARENT_DIR}/descriptors/op-olm/bais-metrics/subscription.yaml
# UMS static CR location
UMS_STATIC_CR_LOCATION="${PARENT_DIR}/descriptors/patterns/bais-metrics"
# UMS Connection Point Static CR location
UMS_CONNECTION_POINT_STATIC_CR_LOCATION="${PARENT_DIR}/descriptors/patterns/bais-metrics/software-central-connection"

# ILS (IBM Licensing Service) related variables for Software Central integration
# ILS connection point secret name
ILS_SWC_SECRET_NAME="bai-ils-secret"

# Zen metastore EDB configmap name
ZEN_EDB_CFG="ibm-zen-metastore-cm"
CERT_MANAGER_PROJECT="ibm-cert-manager"
LICENSE_MANAGER_PROJECT="ibm-licensing"
DEDICATED_CS_PROJECT="cs-control"
# Directory for upgrade operator and prerequisites
UPGRADE_TEMP_FOLDER=${TEMP_FOLDER}/upgrade
UPGRADE_PREREQUISITE_FOLDER=${UPGRADE_TEMP_FOLDER}/prerequisites
UPGRADE_CERT_MANAGER_FILE=${UPGRADE_PREREQUISITE_FOLDER}/cert_manager_operator.yaml
UPGRADE_IBM_LICENSE_FILE=${UPGRADE_PREREQUISITE_FOLDER}/license_operator.yaml
UPGRADE_OPERATOR_GROUP=${UPGRADE_PREREQUISITE_FOLDER}/operator_group.yaml

# Check CS is dedicated or shared
COMMON_SERVICES_CM_NAMESPACE="kube-public"
COMMON_SERVICES_CM_DEDICATED_NAME="common-service-maps"
COMMON_SERVICES_CM_SHARED_NAME="ibm-common-services-status"
COMMON_SERVICES_NAME="IBM Cloud Pak foundational services"
COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE="common-service-maps-update.yaml"
COMMON_SERVICES_CM_DEDICATE_FILE_NAME="common-service-maps.yaml"
COMMON_SERVICES_CM_DEDICATE_FILE="${PARENT_DIR}/descriptors/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME}"
COMMON_SERVICES_CM_DEDICATE_FILE_UPDATE="${PARENT_DIR}/descriptors/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE}"

# Becomes true if any SSL certificate validation fails (Used in the validate_ssl_certificates function and it's helper functions)
SSL_CERT_ERROR_TAG=false

# Becomes true if any required parameters are null or empty (Used in validate_property_file_required_fields)
MISSING_REQUIRED_PARAMETERS=false

# Global array to store all optional parameter keys
OPTIONAL_PARAMETERS_LIST=()

function prop_upgrade_property_file() {
    grep "^${1}=" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}|cut -d'=' -f2
}

function prop_tmp_property_file() {
    grep "^${1}=" ${TEMPORARY_PROPERTY_FILE}|cut -d'=' -f2
}

function prop_ldap_property_file() {
    grep "^${1}=" ${LDAP_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_user_profile_property_file() {
    grep "^${1}=" ${USER_PROFILE_PROPERTY_FILE}|cut -d'"' -f2
}

# set CLI_CMD var
if which oc >/dev/null 2>&1; then
    CLI_CMD=oc
elif which kubectl >/dev/null 2>&1; then
    CLI_CMD=kubectl
else
    printf '%b\n'  "\x1B[1;31mUnable to locate Kubernetes CLI or OpenShift CLI. You must install it to run this script.\x1B[0m" && \
    exit 1
fi

function set_global_env_vars() {
    unameOut="$(uname -s)"
    case "${unameOut}" in
        Linux*)      machine="Linux";;
        Darwin*)     machine="Mac";;
        *)           machine="UNKNOWN:${unameOut}"
    esac

    if [[ "$machine" == "Mac" ]]; then
        SED_COMMAND='sed -i ""'
        SED_COMMAND_FORMAT='sed -i "" s/^M//g'
        BASE64_DECODE='base64 --decode'
        YQ_CMD=${CUR_DIR}/helper/yq/yq_darwin_amd64
        CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/macos/yq
        COPY_CMD=/bin/cp
    else
        SED_COMMAND='sed -i'
        SED_COMMAND_FORMAT='sed -i s/\r//g'
        BASE64_DECODE='base64 -w 0 --decode'
        if [[ $(uname -m) == 'x86_64' ]]; then
            YQ_CMD=${CUR_DIR}/helper/yq/yq_linux_amd64
            CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/amd64/yq
        elif [[ $(uname -m) == 'ppc64le' ]]; then
            YQ_CMD=${CUR_DIR}/helper/yq/yq_linux_ppc64le
            CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/ppc64le/yq
        else
            YQ_CMD=${CUR_DIR}/helper/yq/yq_linux_s390x
            CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/s390x/yq
        fi
        COPY_CMD=/usr/bin/cp
    fi
}

############################
# CLI installation utilities
############################

function validate_cli(){
    which ${YQ_CMD} &>/dev/null
    [[ $? -ne 0 ]] && \
        while true; do
            echo_bold "\"yq\" Command Not Found\n"
            echo_bold "Please download \"yq\" binary file from cert-kubernetes repo\n"
            exit 0
        done
    which timeout &>/dev/null
    [[ $? -ne 0 ]] && \
        while true; do
            echo_bold "\"timeout\" Command Not Found\n"
            echo_bold "The \"timeout\" will be installed automatically\n"
            echo_bold "Do you accept (Yes/No, default: No):"
            read -erp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                install_timeout_cli
                break
                ;;
            "n"|"N"|"no"|"No"|"NO")
                printf '%b\n' "You do not accept, exiting...\n"
                exit 0
                ;;
            *)
                echo_red "You do not accept, exiting...\n"
                exit 0
                ;;
            esac
        done
}

function install_timeout_cli(){
    if [[ ${machine} = "Mac" ]]; then
        printf '%s' "Installing timeout..."; brew install coreutils >/dev/null 2>&1; sudo ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout >/dev/null 2>&1; echo "done.";
    fi
    printf "\n"
}

function install_yq_cli(){
    if [[ ${machine} = "Linux" ]]; then
        printf '%s' "Downloading..."; curl -LO https://github.com/mikefarah/yq/releases/download/3.2.1/yq_linux_amd64  >/dev/null 2>&1; echo "done.";
        printf '%s' "Installing yq..."; sudo chmod +x yq_linux_amd64 >/dev/null; sudo mv yq_linux_amd64 /usr/local/bin/yq >/dev/null; echo "done.";
    else
        printf '%s' "Installing yq..."; brew install yq >/dev/null; echo "done.";
    fi
    printf "\n"
}

function install_kubectl_cli(){
    if [[ ${machine} = "Linux" ]]; then
        printf '%s' "Downloading..."
        if [[ $(uname -m) == 'x86_64' ]]; then
            PLATFORM_ARCH='amd64'
        elif [[ $(uname -m) == 'ppc64le' ]]; then
            PLATFORM_ARCH='ppc64le'
        elif [[ $(uname -m) == 's390x' ]]; then
            PLATFORM_ARCH='s390x'
        fi
        curl -o /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${PLATFORM_ARCH}/kubectl" >/dev/null 2>&1; echo "done."
        printf '%s' "Installing Kubectl CLI..."; sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl >/dev/null; echo "done.";
    elif [[ ${machine} = "Mac" ]]; then
        printf '%s' "Downloading..."; curl -o /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl" >/dev/null 2>&1; echo "done.";
        printf '%s' "Installing Kubectl CLI..."; chmod +x /tmp/kubectl >/dev/null; sudo mv /tmp/kubectl /usr/local/bin/kubectl >/dev/null; sudo chown root: /usr/local/bin/kubectl; echo "done.";
    fi
    printf "\n"
}

function install_openssl(){
    if [[ ${machine} = "Linux" ]]; then
        printf '%s' "Installing OpenSSL..."; sudo yum install openssl -y >/dev/null; echo "done.";
    elif [[ ${machine} = "Mac" ]]; then
        printf '%s' "Installing OpenSSL..."; sudo brew install openssl >/dev/null; echo 'export PATH="/usr/local/opt/openssl/bin:$PATH"' >> ~/.bash_profile; source ~/.bash_profile; echo "done.";
    fi
    printf "\n"
}
# DBACLD-198782: Validate Java runtime and set JAVA_CMD and KEYTOOL_CMD
# $1 - (Optional) Custom Java path
function validate_java_runtime() {
    local CUSTOM_JAVA_PATH=$1
    
    # Build example command with actual namespace if available
    local EXAMPLE_NS="${TARGET_PROJECT_NAME:-bais-ns}"
    local EXAMPLE_CMD="./bai-prerequisites.sh -m validate -n ${EXAMPLE_NS} --java-path=/custom/java/path"
    
    # Step 1: Set JAVA_CMD and KEYTOOL_CMD based on CUSTOM_JAVA_PATH
    if [[ -n "$CUSTOM_JAVA_PATH" ]]; then
        # Normalize path - ensure it points to bin directory
        if [[ "$CUSTOM_JAVA_PATH" != */bin ]]; then
            CUSTOM_JAVA_PATH="${CUSTOM_JAVA_PATH}/bin"
        fi
        
        JAVA_CMD="${CUSTOM_JAVA_PATH}/java"
        KEYTOOL_CMD="${CUSTOM_JAVA_PATH}/keytool"
        
        # Verify the custom Java path exists and is executable
        if [[ ! -x "$JAVA_CMD" ]]; then
            printf '%b\n' "\x1B[1;31mError: Java executable not found at specified path: $JAVA_CMD\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease provide a valid path to Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation.\x1B[0m"
            exit 1
        fi
        
        # Verify keytool exists and is executable
        if [[ ! -x "$KEYTOOL_CMD" ]]; then
            printf '%b\n' "\x1B[1;31mError: keytool executable not found at specified path: $KEYTOOL_CMD\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease provide a valid path to Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation.\x1B[0m"
            exit 1
        fi
      else
        JAVA_CMD="java"
        KEYTOOL_CMD="keytool"
        
        # Verify that default Java is available
        if ! command -v java &> /dev/null; then
            printf '%b\n' "\x1B[1;31mUnable to locate a Java Runtime. Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher must be installed to run this script.\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease install Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher manually before continuing.\x1B[0m"
            printf '%b\n' "\x1B[1;33mInstallation instructions:\x1B[0m"
            printf '%b\n' "  - Install any compatible Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher distribution (e.g., IBM Semeru, Oracle JDK, or OpenJDK)"
            printf '%b\n' "  - Ensure the new Java version is added to your PATH environment variable"
            printf '%b\n' "  - Re-run this script"
            printf '%b\n' "\x1B[1;33mAlternatively, you can specify the path to an existing Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation:\x1B[0m"
            printf '%b\n' "  - Re-run this script with the Java (JRE) path parameter, using --java-path <path_to_java>; e.g., ${EXAMPLE_CMD}"
            exit 1
        fi
        
        # Verify that default keytool is available
        if ! command -v keytool &> /dev/null; then
            printf '%b\n' "\x1B[1;31mUnable to locate keytool. Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher must be installed to run this script.\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease install Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher manually before continuing.\x1B[0m"
            exit 1
        fi
    fi
    
    # Step 2: Validate Java version
    "$JAVA_CMD" -version &>/dev/null
    if [[ $? -ne 0 ]]; then
        printf '%b\n' "\x1B[1;31mUnable to execute Java. Please check your Java (JRE) installation.\x1B[0m"
        exit 1
    fi
    
    # Extract the full version string
    local CURRENT_JAVA_VERSION=$("$JAVA_CMD" -version 2>&1 | grep -i version | head -n 1 | awk -F '"' '{print $2}')
    
    # Extract just the major version for comparison
    local CURRENT_MAJOR_VERSION=$(echo "$CURRENT_JAVA_VERSION" | awk -F '.' '{print $1}')
    
    # If version starts with "1.", use the second number (e.g., 1.8 -> 8)
    if [[ "$CURRENT_JAVA_VERSION" == 1.* ]]; then
        CURRENT_MAJOR_VERSION=$(echo "$CURRENT_JAVA_VERSION" | awk -F '.' '{print $2}')
    fi
    
    # Check if current version is less than the required version
    if [[ -n "$CURRENT_MAJOR_VERSION" && "$CURRENT_MAJOR_VERSION" -lt "$REQUIRED_JAVA_MAJOR_VERSION" ]]; then
        printf '%b\n' "\x1B[1;31mJava version $CURRENT_JAVA_VERSION is installed but does not meet the minimum requirement (version $REQUIRED_JAVA_MAJOR_VERSION).\x1B[0m"
        printf '%b\n' "\x1B[1;31mPlease upgrade to Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher manually before continuing.\x1B[0m"
        printf '%b\n' "\x1B[1;33mJava (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher upgrade instructions:\x1B[0m"
        printf '%b\n' "  - Install any compatible Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher distribution (e.g., IBM Semeru, Oracle JDK, or OpenJDK)"
        printf '%b\n' "  - Ensure the new Java version is added to your PATH environment variable"
        printf '%b\n' "  - Re-run this script"
        printf '%b\n' "\x1B[1;33mAlternatively, you can specify the path to an existing Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation:\x1B[0m"
        printf '%b\n' "  - Re-run this script with the Java (JRE) path parameter, using --java-path <path_to_java>; e.g., ${EXAMPLE_CMD}"
        exit 1
    fi
    
    info "Using Java version: $CURRENT_JAVA_VERSION located at: $(command -v "$JAVA_CMD")"
    
    # Step 3: Validate keytool
    "$KEYTOOL_CMD" -help &>/dev/null
    if [[ $? -ne 0 ]]; then
        printf '%b\n' "\x1B[1;31mUnable to execute keytool. Keytool is required and should be part of your Java (JRE) installation.\x1B[0m"
        printf '%b\n' "\x1B[1;31mPlease ensure you have a complete Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation that includes keytool.\x1B[0m"
        exit 1
    fi
    
    # Step 4: Export the commands so they're available to child scripts
    export JAVA_CMD
    export KEYTOOL_CMD
}


###################
# Echoing utilities
###################
RED_TEXT=`tput setaf 1`
GREEN_TEXT=`tput setaf 2`
YELLOW_TEXT=`tput setaf 3`
BLUE_TEXT=`tput setaf 6`
WHITE_TEXT=`tput setaf 7`
RESET_TEXT=`tput sgr0`

printHeaderMessage()
{
 echo ""
  if [  "${#2}" -ge 1 ] ;then
      echo "${2}${1}"
  else
      echo "${WHITE_TEXT}##########################################################${RESET_TEXT}"
      echo "             ${WHITE_TEXT}${1}"
  fi
  echo "##########################################################${RESET_TEXT}"
}

printFooterMessage()
{
  echo "${WHITE_TEXT}##########################################################${RESET_TEXT}"
}

function msg() {

  printf '\n%b\n' "$1"

}



function wait_msg() {

  printf '%s\r' "${1}"

}

function success() {

  msg "\33[32m[✔] ${1}\33[0m"

}

function info() {

  msg "\x1B[33;5m[INFO] \x1B[0m${1}"

}

function INFO() {

  msg "============== ${1} =============="

}


function tips() {

  printf '%b' "\x1B[1;31m[NEXT ACTIONS]\x1B[0m${1}\n" 

}

function warning() {

  msg "\33[33m[✗] ${1}\33[0m"

}



function error() {

  msg "\33[31m[✘] ${1}\33[0m"

}


function msgRed() {

  printf '%b' "\x1B[1;31m[*] ${1}\x1B[0m\n"

}

function fail() {

  msg "\33[31m[FAILED] ${1}\33[0m"

}



function title() {

  msg "\33[1m ($step) ${1}\33[0m"
  step=$((step + 1))

}



function msgB() {

  printf '%b\n' "\x1B[1m${1}\x1B[0m\n"

}

function echo_bold() {
    # Echoes a message in bold characters
    echo_impl "${1}" "m"
}

function echo_red() {
    # Echoes a message in red bold characters
    echo_impl "${1}" ";31m"
}

function echo_impl() {
    # Echoes a message prefixed and suffixed by formatting characters
    local MSG=${1:?Missing message to echo}
    local PREFIX=${2:?Missing message prefix}
    #local SUFFIX=${3:?Missing message suffix}
    printf '%b\n' "\x1B[1${PREFIX}${MSG}\x1B[0m"
}

## <https://jsw.ibm.com/browse/DBACLD-159357> - Introduced new function to deal with pressing control keys to continune, need to clear buffer before and after reading user input.
## - - https://jsw.ibm.com/browse/DBACLD-165921 - <Press any key to continue...does not continue when "shift key" is pressed>
function prompt_press_any_key_to_continue() {
    while read -r -t 1; do :; done  # Clear the buffer
    read -rsn1 -p "Press Enter/Return to continue ${1}..."; echo # wait for user input
    read -r -t 1 # Clear any remaining escape seqence
}

############################
# check OCP version
############################
function check_platform_version(){
    currentver=$(${CLI_CMD} get nodes | awk 'NR==2{print $5}')
    requiredver="v1.17.1"
    if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
        PLATFORM_VERSION="4.4OrLater"  
    else
        # PLATFORM_VERSION="3.11"
        PLATFORM_VERSION="4.4OrLater"
        printf '%b\n' "\x1B[1;31mIMPORTANT: Only support OCp4.4 or Later, exit...\n\x1B[0m"
        exit 1
    fi
}

## <https://jsw.ibm.com/browse/DBACLD-161428> - Create a common function to check cluster login for all related scripts.
## <https://jsw.ibm.com/browse/DBACLD-187651> - Simplified check_cluster_login()
#############################
# Check Cluster Login
#############################
function check_cluster_login() {
    if [[ "$CLI_CMD" == "oc" ]]; then
        ${CLI_CMD} whoami >/dev/null 2>&1
    else
        ${CLI_CMD} auth whoami >/dev/null 2>&1
    fi
    
    if [ $? -gt 0 ]; then
        error "Not logged in to a cluster. Please login to a cluster before running this script."
        exit 1
    fi
}

#DBACLD-194974: Version to remove EDB and make external postgres mandatory for IM ZEN BTS by checking the version $BAI_PATCH_VERSION and $BAI_RELEASE_BASE 
function skip_edb_for_2501() {
    local _existing_cp4ba_version=${BAI_RELEASE_BASE}_${BAI_PATCH_VERSION}
    local _version_to_skip="$VERSION_TO_SKIP_EDB"

    if [[ "$_existing_cp4ba_version" == "$_version_to_skip" ]]; then
        return 0  # Make external Postgres mandatory
    else
        return 1  # Give the option to use external Postgres
    fi
}

## <https://jsw.ibm.com/browse/DBACLD-176036> - Moved function from helper/upgrade/upgrade_check_status.sh to helper/common.sh
#############################
# Check separation of duties
#############################
function check_bai_separate_operand(){
    local project=$1
    # Check whether the BAI is separation of operators and operands.
    # operators_namespace: openshift-operators
    # services_namespace: ibm-common-services

    # operators_namespace: ibm-common-services
    # services_namespace: ibm-common-services

    # operators_namespace: cp4a-ns
    # services_namespace: cp4a-ns

    if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $project >/dev/null 2>&1; then
        success "Found \"ibm-cp4ba-common-config\" configMap in the project \"$project\"."
    else
        status=$?
        echo "$status"
        warning "Not found \"ibm-cp4ba-common-config\" configMap in the project \"$project\"."
        while [[ $BAI_SERVICES_NS == "" ]];
        do
            printf "\n"
            printf '%b\n' "\x1B[1mWhere (namespace) did you deploy BAI Standalone operands (i.e., runtime pods)? \x1B[0m"
            read -p "Enter the name for an existing project (namespace): " BAI_SERVICES_NS
            if [ -z "$BAI_SERVICES_NS" ]; then
                printf '%b\n' "\x1B[1;31mEnter a valid project name, project name can not be blank\x1B[0m"
            elif [[ "$BAI_SERVICES_NS" == openshift* ]]; then
                printf '%b\n' "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
                BAI_SERVICES_NS=""
            elif [[ "$BAI_SERVICES_NS" == kube* ]]; then
                printf '%b\n' "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
                BAI_SERVICES_NS=""
            else
                isProjExists=`${CLI_CMD} get project $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1

                if [ "$isProjExists" -ne 2 ] ; then
                    printf '%b\n' "\x1B[1;31mInvalid project name, enter a existing project name ...\x1B[0m"
                    BAI_SERVICES_NS=""
                else
                    printf '%b\n' "\x1B[1mUsing project ${BAI_SERVICES_NS}...\x1B[0m"
                    if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $BAI_SERVICES_NS >/dev/null 2>&1; then
                        success "Found \"ibm-cp4ba-common-config\" configMap in the project \"$BAI_SERVICES_NS\"."
                    else
                        warning "Not found \"ibm-cp4ba-common-config\" configMap in the project \"$BAI_SERVICES_NS\"."
                        BAI_SERVICES_NS=""
                        if [[ ($SCRIPT_MODE == "" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "dev" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "review" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "baw-dev" && $RUNTIME_MODE == "") ]]; then
                            fail "You NEED to create \"ibm-cp4ba-common-config\" configMap first in the project (namespace) where you want to deploy CP4BA operands (i.e., runtime pods)."
                            exit 1
                        fi
                    fi
                fi
            fi
        done
    fi
    tmp_namespace_val=""
    if [[ $BAI_SERVICES_NS != "" ]]; then
        tmp_namespace_val=$BAI_SERVICES_NS
    else
        tmp_namespace_val=$project
    fi
    bai_services_namespace=$(${CLI_CMD} get configMap ibm-cp4ba-common-config -n $tmp_namespace_val --no-headers --ignore-not-found -o jsonpath='{.data.services_namespace}')
    bai_operators_namespace=$(${CLI_CMD} get configMap ibm-cp4ba-common-config -n $tmp_namespace_val --no-headers --ignore-not-found -o jsonpath='{.data.operators_namespace}')
    if [[ (! -z $BAI_SERVICES_NS) ]]; then
        if [[ $bai_services_namespace != $BAI_SERVICES_NS ]]; then
            fail "Your input value for BAI Standalone operands (i.e., runtime pods) is NOT equal to the value of \"services_namespace\" in \"ibm-cp4ba-common-config\" configMap under the project \"$BAI_SERVICES_NS\"."
            exit 1
        fi
    fi
    if [[ (! -z $bai_services_namespace) && (! -z $bai_operators_namespace) ]]; then
        # The IF condition below checks for separation of duties scenario (note: all-ns and shared CPfs are not considered separation of duties):
        #  - ($bai_services_namespace != $bai_operators_namespace) -> confirms that operator and services ns are different
        #  - ($bai_operators_namespace != "openshift-operators") -> confirms that scenario is NOT all-ns
        #  - ($bai_operators_namespace != "ibm-common-services") -> confirms that scenario is NOT shared/cluster-scoped CPfs scenario
        if [[ ($bai_services_namespace != $bai_operators_namespace) && ($bai_operators_namespace != "openshift-operators" && $bai_operators_namespace != "ibm-common-services") ]]; then
            info "This BAI Standalone deployment has separate operators and operands"
            SEPARATE_OPERAND_FLAG="Yes"
            BAI_SERVICES_NS=$bai_services_namespace
        else
            SEPARATE_OPERAND_FLAG="No"
            BAI_SERVICES_NS=$TARGET_PROJECT_NAME
        fi
    else
        warning "Not found \"operator_namespace\\services_namespace\" in \"ibm-cp4ba-common-config\" configMap under the project \"$tmp_namespace_val\""
        fail "You need to set correct value(s) in \"ibm-cp4ba-common-config\" configMap for BAI Standalone seperation of operators and operand under the project \"$tmp_namespace_val\""
        exit 1
    fi
}

set_global_env_vars

function save_log(){
    local LOG_DIR="$CUR_DIR/$1"
    LOG_FILE="$LOG_DIR/$2_$(date +'%Y%m%d%H%M%S').log"

    if [[ ! -d $LOG_DIR ]]; then
        mkdir -p "$LOG_DIR"
    fi

    # Redirect output to log-file
    exec > >(tee -a "$LOG_FILE") 2>&1

    # Open fd 3 directly to log file
    exec 3>> "$LOG_FILE"

}

function cleanup_log() {
    # Check if the log file already exists
    if [[ -e $LOG_FILE ]]; then
        # Remove ANSI escape sequences from log file
        sed -E 's/\x1B\[[0-9;]+[A-Za-z]//g' "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

## <https://jsw.ibm.com/browse/DBACLD-172803> - We are now asking user to use {xor} for special characters in password, so we need to use decode_xor_password to get the password decoded before validation.
function decode_xor_password() {

  local encoded=$1
  local operator_project_name=$2
  local operator_pod_name=$3
  local was_home="/opt/ibm/securityUtility"
  local class_path="${was_home}/plugins/com.ibm.ws.runtime.jar:${was_home}/lib/bootstrap.jar:${was_home}/plugins/com.ibm.ws.emf.jar:${was_home}/lib/ffdc.jar:${was_home}/plugins/org.eclipse.emf.ecore.jar:${was_home}/plugins/org.eclipse.emf.common.jar:${was_home}/glassfish-corba-omgapi-4.2.4.jar"
  if [[ $encoded != "" ]] && [[ "$encoded" == *"{xor}"* ]]; then
    local decoded=$( ${CLI_CMD} exec -i -n $operator_project_name $operator_pod_name -- bash -c "java -cp \"${class_path}\" com.ibm.ws.security.util.PasswordDecoder \"$encoded\"")
    echo "$decoded" | grep -i 'decoded password == ' | awk '{print $8}' | sed -e 's/^"//' -e 's/"$//'
  else
    echo "$encoded"
  fi
}

function allocate_operator_pvc(){
    # For dynamic storage classname
    printf "\n"
    printf '%b\n' "\x1B[1mApplying the persistent volumes for the Cloud Pak operator by using the storage classname: ${STORAGE_CLASS_NAME}...\x1B[0m"

    printf "\n"
    if [[ $DEPLOYMENT_TYPE == "starter" && ($PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "other") ]] ;
    then
        sed "s/<StorageClassName>/$STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_BAK} > ${OPERATOR_PVC_FILE_TMP1}
        sed "s/<Fast_StorageClassName>/$STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_TMP1}  > ${OPERATOR_PVC_FILE_TMP} # &> /dev/null

    elif [[ ($DEPLOYMENT_TYPE == "production" && ($PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "other")) || $PLATFORM_SELECTED == "ROKS" ]];
    then
        sed "s/<StorageClassName>/$SLOW_STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_BAK} > ${OPERATOR_PVC_FILE_TMP1} # &> /dev/null
        sed "s/<Fast_StorageClassName>/$FAST_STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_TMP1} > ${OPERATOR_PVC_FILE_TMP} # &> /dev/null
    fi

    ${COPY_CMD} -rf ${OPERATOR_PVC_FILE_TMP} ${OPERATOR_PVC_FILE_BAK}
    # Create Operator Persistent Volume.
    CREATE_PVC_CMD="${CLI_CMD} apply -f ${OPERATOR_PVC_FILE_TMP}"
    if $CREATE_PVC_CMD ; then
        printf '%b\n' "\x1B[1mDone\x1B[0m"
    else
        printf '%b\n' "\x1B[1;31mFailed\x1B[0m"
    fi
   # Check Operator Persistent Volume status every 5 seconds (max 10 minutes) until allocate.
    ATTEMPTS=0
    TIMEOUT=60
    printf "\n"
    printf '%b\n' "\x1B[1mWaiting for the persistent volumes to be ready...\x1B[0m"
    until ${CLI_CMD} get pvc | grep cp4a-shared-log-pvc | grep -q -m 1 "Bound" || [ $ATTEMPTS -eq $TIMEOUT ]; do
        ATTEMPTS=$((ATTEMPTS + 1))
        printf '%b\n' "......"
        sleep 10
        if [ $ATTEMPTS -eq $TIMEOUT ] ; then
            printf '%b\n' "\x1B[1;31mFailed to allocate the persistent volumes!\x1B[0m"
            printf '%b\n' "\x1B[1;31mRun the following command to check the claim '${CLI_CMD} describe pvc operator-shared-pvc'\x1B[0m"
            exit 1
        fi
    done
    if [ $ATTEMPTS -lt $TIMEOUT ] ; then
            printf '%b\n' "\x1B[1mDone\x1B[0m"
    fi
}
# For https://jsw.ibm.com/browse/DBACLD-157020
# Function that base64 encodes the password in the generated secret template and moves it to the data section of the template
# We cant directy use the base64 value in the stringData field as when the secret template is applied the cluster automatically base64 encodes it again and this will result in a wrong password being used by the operator code
# This was code that was repeating in numerous places so it was made a common function
# password_value is the value to base64 and update in the secret template
# secret template field is the property field in the secret template who's value will be the value in password_value
# secret_file is the name of the secret template file. (this file is already created prior to this function call)
# new_secret_template_field is the name of a new secret field to be added. This is only passed for the fncm secret where we add password fields to the existing template
# for new_secret_template_field to be used, secret template field must be osDBpassword as the current logic will append the new field after osDBpassword . 
# Other than for fncm secret the new_secret_template_field field is empty and not needed
function update_secret_template_passwords(){
    local password_value=$1
    local secret_template_field=$2
    local secret_file=$3
    local new_secret_template_field=$4
    # Checking if the password in the property file is base64 encoded and if so we just remove the prefix.
    # IF the password is plaintext we base64 encode it

    if [[ "${password_value:0:8}" == "{Base64}"  ]]; then
        temp_val=$(echo "$password_value" | sed -e "s/^{Base64}//" )
    else
        local machine_lower=$(echo "${machine}" | tr '[:upper:]' '[:lower:]')
        if [[ "$machine_lower" == "linux" ]]; then
            temp_val=$(printf '%s' "$password_value" | base64 -w 0 )
        else
            temp_val=$(printf '%s' "$password_value" | base64 )
        fi
    fi
    if ${YQ_CMD} r "$secret_file" "stringData.$secret_template_field" >/dev/null 2>&1; then
        # Remove the field from stringData and add it to data with the new encoded value
        # Use yq to delete and add the field in a more compatible way without eval
        if [[ "$secret_template_field" != "osDBPassword" ]]; then
            ${YQ_CMD} w -i "$secret_file" "data.$secret_template_field" "$temp_val"
            ${YQ_CMD} d -i "$secret_file" "stringData.$secret_template_field"
        else
            ${YQ_CMD} w -i "$secret_file" "data.$new_secret_template_field" "$temp_val"
        fi
    else
        echo "Field $secret_template_field not found in stringData."
    fi
}



# This function is used to display a latency warning based on the time taken for a DB/LDAP connection
# Takes in 2 parameters
# 1. time_taken which is used to display the latency and make comparisons using bc -l which allows for float point based comparisons
# connection_type which is used to display if the connection is for a DB or LDAP
# DBACLD-159742
function display_latency_warning() {
    local time_taken=$1
    local connection_type=$2
    echo "Latency: $time_taken ms"
    # Check if elapsed time is greater than 10 ms using awk. [[ ]] not used since it doesnt do float point comparisons correctly
    # If tt is between 10 and 30, it exits with 0 (success)
    if awk -v tt="$time_taken" 'BEGIN { exit !(tt < 10) }'; then
        echo "The latency is less than 10ms, which is acceptable performance for a simple $connection_type operation."
    elif awk -v tt="$time_taken" 'BEGIN { exit !(tt >= 10 && tt <= 30) }'; then
        echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple $connection_type operation, but the service is still accessible."
    else
        echo "The latency exceeds 30ms for a simple $connection_type operation, which indicates potential for failures."
    fi
}

# Function used to check if a specific value is present in a list of values 
function containsElement(){
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}


# Function to clean up old files that are not required
# Used in cp4a-prerequisites.sh script
function clean_up_temp_file(){
    local files=()
    files=($(find $PREREQUISITES_FOLDER -name '*.*""'))
    for item in ${files[*]}
    do
        rm -rf $item >/dev/null 2>&1
    done
    
    # deletes all temporary files i.e files ending with ""
    files=($(find $TEMP_FOLDER -name '*.*""'))
    for item in ${files[*]}
    do
        rm -rf $item >/dev/null 2>&1
    done
}

# Function that loads certain properties from the temp property file
# Used in bai-prerequisites.sh script (generate and validate mode) and bai-deployment.sh for fresh install

function load_properties_from_temp_file(){
    if [[ ! -f $TEMPORARY_PROPERTY_FILE || ! -f $USER_PROFILE_PROPERTY_FILE ]]; then
        fail "Not Found existing property file under \"$PROPERTY_FILE_FOLDER\" .Run \"bai-prerequisites.sh\" in property mode to complete the generation of property files"
        exit 1
    fi

    # load the flag that stores whether ldap was selected or not
    selected_ldap_flag="$(prop_tmp_property_file SELECTED_LDAP_FLAG)"

    # load ldap type
    LDAP_TYPE="$(prop_tmp_property_file LDAP_TYPE)"

    # load external postgres DB for IM Flag
    EXTERNAL_POSTGRESDB_FOR_IM_FLAG=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    EXTERNAL_POSTGRESDB_FOR_IM_FLAG=$(echo "$EXTERNAL_POSTGRESDB_FOR_IM_FLAG" | tr '[:upper:]' '[:lower:]')

    # Load external postgres DB for Zen Flag
    EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG=$(echo "$EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG" | tr '[:upper:]' '[:lower:]')

    # Load external postgres DB for BTS Flag
    EXTERNAL_POSTGRESDB_FOR_BTS_FLAG=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
    EXTERNAL_POSTGRESDB_FOR_BTS_FLAG=$(echo "$EXTERNAL_POSTGRESDB_FOR_BTS_FLAG" | tr '[:upper:]' '[:lower:]')


    # load pattern into pattern_cr_arr
    pattern_list="$(prop_tmp_property_file PATTERN_LIST)"
    pattern_name_list="$(prop_tmp_property_file PATTERN_NAME_LIST)"
    optional_component_list="$(prop_tmp_property_file OPTION_COMPONENT_LIST)"
    optional_component_name_list="$(prop_tmp_property_file OPTION_COMPONENT_NAME_LIST)"
    foundation_list="$(prop_tmp_property_file FOUNDATION_LIST)"
    
    OIFS=$IFS
    IFS=',' read -ra pattern_cr_arr <<< "$pattern_list"
    IFS=',' read -ra PATTERNS_CR_SELECTED <<< "$pattern_list"
    
    IFS=',' read -ra pattern_arr <<< "$pattern_name_list"
    IFS=',' read -ra optional_component_cr_arr <<< "$optional_component_list"
    IFS=',' read -ra optional_component_arr <<< "$optional_component_name_list"
    IFS=',' read -ra foundation_component_arr <<< "$foundation_list"    
    IFS=$OIFS

    # load profile size  flag
    PROFILE_TYPE=$(prop_tmp_property_file PROFILE_SIZE_FLAG) 


}


# Function that loads certain variables from the temp property file
#function load_property_before_generate(){
#    if [[ ! -f $TEMPORARY_PROPERTY_FILE || ! -f $USER_PROFILE_PROPERTY_FILE ]]; then
#        fail "Not Found existing property file under \"$PROPERTY_FILE_FOLDER\". Run \"cp4a-prerequisites.sh\" to complete prerequisites"
#        exit 1
#    fi
#
#    # load pattern into pattern_cr_arr
#    pattern_list="$(prop_tmp_property_file PATTERN_LIST)"
#    pattern_name_list="$(prop_tmp_property_file PATTERN_NAME_LIST)"
#    optional_component_list="$(prop_tmp_property_file OPTION_COMPONENT_LIST)"
#    optional_component_name_list="$(prop_tmp_property_file OPTION_COMPONENT_NAME_LIST)"
#    foundation_list="$(prop_tmp_property_file FOUNDATION_LIST)"
#
#    # Loading the LDAP_FLAG that will help the script know if the ldap section in the CR is required or not
#    # DBACLD-168779
#
#    selected_ldap_flag="$(prop_tmp_property_file SELECTED_LDAP_FLAG)"
#
#    OIFS=$IFS
#    IFS=',' read -ra pattern_cr_arr <<< "$pattern_list"
#    IFS=',' read -ra PATTERNS_CR_SELECTED <<< "$pattern_list"
#    
#    IFS=',' read -ra pattern_arr <<< "$pattern_name_list"
#    IFS=',' read -ra optional_component_cr_arr <<< "$optional_component_list"
#    IFS=',' read -ra optional_component_arr <<< "$optional_component_name_list"
#    IFS=',' read -ra foundation_component_arr <<< "$foundation_list"    
#    IFS=$OIFS
#
#    # load db_name_full_array and db_user_full_array
#    #db_name_list="$(prop_tmp_property_file DB_NAME_LIST)"
#    #db_user_list="$(prop_tmp_property_file DB_USER_LIST)"
#    #db_user_pwd_list="$(prop_tmp_property_file DB_USER_PWD_LIST)"
#
#    #OIFS=$IFS
#    #IFS=',' read -ra db_name_full_array <<< "$db_name_list"
#    #IFS=',' read -ra db_user_full_array <<< "$db_user_list"
#    #IFS=',' read -ra db_user_pwd_full_array <<< "$db_user_pwd_list"
#    #IFS=$OIFS
#
#    # load db ldap type
#    LDAP_TYPE="$(prop_tmp_property_file LDAP_TYPE)"
#    #DB_TYPE="$(prop_tmp_property_file DB_TYPE)"
#
#    # load CONTENT_OS_NUMBER
#    #content_os_number=$(prop_tmp_property_file CONTENT_OS_NUMBER)
#
#    # load DB_SERVER_NUMBER
#    #db_server_number=$(prop_tmp_property_file DB_SERVER_NUMBER)
#
#    # load limited CPE storage support flag
#    #CPE_FULL_STORAGE=$(prop_tmp_property_file CPE_FULL_STORAGE_ENABLED)
#
#    # load GPU enabled worker nodes flag
#    #ENABLE_GPU_ARIA=$(prop_tmp_property_file ENABLE_GPU_ARIA_ENABLED)
#    #nodelabel_key=$(prop_tmp_property_file NODE_LABEL_KEY)
#    #nodelabel_value=$(prop_tmp_property_file NODE_LABEL_VALUE)
#
#    # load LDAP/DB required flag for wfps
#    #LDAP_WFPS_AUTHORING=$(prop_tmp_property_file LDAP_WFPS_AUTHORING_FLAG)
#    #EXTERNAL_DB_WFPS_AUTHORING=$(prop_tmp_property_file EXTERNAL_DB_WFPS_AUTHORING_FLAG)
#
#    # load fips enabled flag
#    FIPS_ENABLED="false"
#
#    # load profile size  flag
#    PROFILE_TYPE=$(prop_tmp_property_file PROFILE_SIZE_FLAG)   
#}

# Function to update repository and tag sections in the CR with the staging repository and current sprint tag
# This function is used by the bai-deployment.sh only in 
# 1.For OTHER type of platform
# 2.DEV mode
function update_repository_and_tags(){
    component_path=$1  
    if [[ "$component_path" == *"keytool_init_container"* ]]; then
        repository_path="$component_path.repository"
        tag_path="$component_path.tag"
    else
        repository_path="$component_path.image.repository"
        tag_path="$component_path.image.tag"
    fi
    repo_value=$(${YQ_CMD} r ${BAI_S_FC_CR} $repository_path || echo "")
    updated_value=$(echo "$repo_value" | sed 's|cp.icr.io/cp|cp.stg.icr.io/cp|')
    ${YQ_CMD} w -i "$BAI_PATTERN_FILE_TMP" "$repository_path" "\"$updated_value\""
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} "$tag_path" "\"$CURRENT_SPRINT_TAG\""

    
}


# Function to get the domain name 
# Used only for OTHER type of platform
# 1.To cupdate the property file as part of the property mode of bai-prerequisites.sh
function get_domain_name() {
    local namespace=$1
    local configmap_name=$2
    domain_name=""
    # Check if the ConfigMap exists
    if ${CLI_CMD} get configmap "$configmap_name" -n "$namespace" &>/dev/null; then
        # Retrieve the parameter from the data section
        domain_name=$(${CLI_CMD} get configmap "$configmap_name" -n "$namespace" -o jsonpath="{.data.domain_name}" 2>/dev/null)

        if [ -n "$domain_name" ]; then
            success "\033[1;32mConfigMap '$configmap_name' found and Domain Name was retrieved sucessfully\033[0m"
        else
            error "\033[1;31mConfigMap '$configmap_name' found, but key 'domain_name' is missing.\033[0m"
            info  "\033[1;33m The ConfigMap '$configmap_name' is created during the execution of ${CUR_DIR}/bai-clusteradmin-setup.sh script\033[0m"

        fi
    else
        # Prompt the user to create the ConfigMap
        error  "\033[1;31mError: ConfigMap '$configmap_name' not found in namespace '$namespace'.\033[0m"
        info  "\033[1;33m The ConfigMap '$configmap_name' is created during the execution of ${CUR_DIR}/bai-clusteradmin-setup.sh script\033[0m"
    fi
}

#This function is used to validate the docker and podman CLI
# Used by both bai-clusteradmin-setup script and bai-deployment.sh so its being moved here
function validate_docker_podman_cli(){
    if [[ $OCP_VERSION == "3.11" || "$machine" == "Mac" ]];then
        which podman &>/dev/null
        if [[ $? -ne 0 ]]; then
            PODMAN_FOUND="No"

            which docker &>/dev/null
            [[ $? -ne 0 ]] && \
                DOCKER_FOUND="No"
            if [[ $DOCKER_FOUND == "No" && $PODMAN_FOUND == "No" ]]; then
                printf '%b\n' "\x1B[1;31mUnable to locate docker and podman. Install either of them first.\x1B[0m" && \
                exit 1
            fi
        fi
    elif [[ $OCP_VERSION == "4.4OrLater" ]]
    then
        which podman &>/dev/null
        [[ $? -ne 0 ]] && \
            printf '%b\n' "\x1B[1;31mUnable to locate podman. Install it first.\x1B[0m" && \
            exit 1
    fi
}

# Function to prompt the license to be accepted before proceeding
# Function takes 2 parameters
# 1. message -> display message after the license is accepted
# 2. license -> contains the license link to be displayed
function prompt_license(){
    clear
    echo
    local message=$1
    local license=$2
    printf '%b\n' "\x1B[1;31mIMPORTANT: Review the IBM Business Automation Insights standalone license information here: \n\x1B[0m"
    printf '%b\n' "\x1B[1;31m$license\n\x1B[0m" 
    INSTALL_BAW_ONLY="No"
    
    printf "\n"
    while true; do
        printf "\x1B[1mDo you accept the IBM Business Automation Insights standalone license (Yes/No, default: No): \x1B[0m"

        read -erp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            printf "\n"
            # New license message from 26.0.0 GA for https://jsw.ibm.com/browse/DBACLD-218047
            printf '%b\n' "${BOLD_TEXT}${RED_TEXT}IMPORTANT: By accepting the license, you agree and understand that by default the program collects certain data and metrics regarding deployment and usage.\nFor more information, please consult the License Information for Business Automation Insights standalone.${RESET_TEXT}"
            echo
            prompt_press_any_key_to_continue
            echo
            printf '%b\n' "$message"
            IBM_LICENSE="Accept"
            validate_cli
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            echo
            printf '%b\n' "The license agreement was not accepted. The license agreement must be accepted to continue. The script is exiting...\n"
            exit 0
            ;;
        *)
            printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}


# Function that validates if a specific CLI is present based on the platform type
function validate_kube_oc_cli(){
    if  [[ $PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "ROKS" ]]; then
        which oc &>/dev/null
        [[ $? -ne 0 ]] && \
        printf '%b\n'  "\x1B[1;31mUnable to locate the OpenShift CLI. You must install it to run this script.\x1B[0m" && \
        exit 1
    fi
    if  [[ $PLATFORM_SELECTED == "other" ]]; then
        which kubectl &>/dev/null
        [[ $? -ne 0 ]] && \
        printf '%b\n'  "\x1B[1;31mUnable to locate the Kubernetes CLI, You must install it to run this script.\x1B[0m" && \
        exit 1
    fi
}

# Function that takes in namespace value passed in the -n parameter and checks if it is a valid namespace
# Function used in bai-deployment.sh
function validate_namespace() {
    
    printf "\n"
    printf '%b\n' "\x1B[1mValidating the Namespace used to deploy IBM Business Automation Insights standalone...\x1B[0m"
    printf "\n"
    #read -p "Enter the name for an existing project (namespace): " TARGET_PROJECT_NAME
    if [[ "$TARGET_PROJECT_NAME" == openshift* ]]; then
        error  "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
        exit
    elif [[ "$TARGET_PROJECT_NAME" == kube* ]]; then
        error "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
        exit
    else
        check_cluster_login
        isProjExists=`${CLI_CMD} get namespace $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1

        if [ "$isProjExists" -ne 2 ] ; then
            error "\x1B[1;31mInvalid project name "$TARGET_PROJECT_NAME" , enter an existing project name ...\x1B[0m"
            exit
        else
            success "\x1B[1mUsing project ${TARGET_PROJECT_NAME}...\x1B[0m"
        fi
    fi

}

# Function to select the project , in case the user wants to use a different project name from what was entered or passed
function select_project() {
    while [[ $TARGET_PROJECT_NAME == "" ]]; 
    do
        printf "\n"
        printf '%b\n' "\x1B[1mWhere do you want to deploy IBM Business Automation Insights standalone?\x1B[0m"
        read -p "Enter the name for an existing project (namespace): " TARGET_PROJECT_NAME
        if [ -z "$TARGET_PROJECT_NAME" ]; then
            printf '%b\n' "\x1B[1;31mEnter a valid project name, project name can not be blank\x1B[0m"
        elif [[ "$TARGET_PROJECT_NAME" == openshift* ]]; then
            printf '%b\n' "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
            TARGET_PROJECT_NAME=""
        elif [[ "$TARGET_PROJECT_NAME" == kube* ]]; then
            printf '%b\n' "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
            TARGET_PROJECT_NAME=""
        else
            isProjExists=`${CLI_CMD} get namespace $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1

            if [ "$isProjExists" -ne 2 ] ; then
                printf '%b\n' "\x1B[1;31mInvalid project name, enter a existing project name ...\x1B[0m"
                TARGET_PROJECT_NAME=""
            else
                printf '%b\n' "\x1B[1mUsing project ${TARGET_PROJECT_NAME}...\x1B[0m"
            fi
        fi
    done
}

# Function to check for OCP version
function check_ocp_version(){
    if [[ ${PLATFORM_SELECTED} == "OCP" || ${PLATFORM_SELECTED} == "ROKS" ]];then
        temp_ver=`${CLI_CMD} version | grep v[1-9]\.[1-9][0-9] | tail -n1`
        if [[ $temp_ver == *"Kubernetes Version"* ]]; then
            currentver="${temp_ver:20:7}"
        else
            currentver="${temp_ver:11:7}"
        fi
        requiredver="v1.17.1"
        if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
            OCP_VERSION="4.4OrLater"
        else
            # OCP_VERSION="3.11"
            OCP_VERSION="4.4OrLater"
            printf '%b\n' "\x1B[1;31mIMPORTANT: The apiextensions.k8s.io/v1beta API has been deprecated from k8s 1.16+, OCP 4.3 is using k8s 1.16.x. recommend you to upgrade your OCP to version 4.4 or later\n\x1B[0m"
            prompt_press_any_key_to_continue
            # exit 0
        fi
    fi
}

# All inputs were made to lowercase, default was set to false if no input was given and a message is displayed before the script actually exits
# For https://jsw.ibm.com/browse/DBACLD-201592
function prompt_to_continue() {
    while true; do
        printf "\x1B[1mPlease confirm that you are ready to continue.  Enter Yes to continue or No to exit (Yes/No, default: No): \x1B[0m"
        read -erp "" ans
        ans=$(echo "$ans" | tr '[:upper:]' '[:lower:]')
        if [ -z "$ans" ]; then
            ans="no"
        fi
        case "$ans" in
        "y"|"yes")
            break
            ;;
        "n"|"no")
            info "The script will now exit...\n"
            exit
            ;;
        *)
            printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}


# Function that retrieves the networktype and network cidr range
# This function is used in the cp4a-clusteradmin-setup.sh for fresh install ( mode is "fresh_install")
# This function is used in the cp4a-deployment script in upgradeDeployment mode for upgrade ( mode is "upgrade")
# https://jsw.ibm.com/browse/DBACLD-173602
function retrieve_network_details(){
    local mode=$1
    local namespace=$2
    network_type=""
    network_cidr=""
    if ! network_configuration_output=$(${CLI_CMD} get network cluster -o yaml 2>/dev/null) ; then
        printf "${YELLOW_TEXT}[IMPORTANT]${RESET_TEXT}"
        printf "\n"
        printf "The user does not have sufficient permissions to retrieve cluster network details. As a result, the \"ibm-cp4a-common-configmap\" ConfigMap must be manually updated with the correct network CIDR and network type. This step is required before applying the custom resource file."
        printf "\n"
        printf "${YELLOW_TEXT}[NOTE]:${RESET_TEXT} In OCP or ROKS, this information can be obtained by querying the Network resource \"${CLI_CMD} get network cluster -o yaml\" or by retrieving the details from the OCP Console."
        printf "Then update the 'ibm-cp4ba-common-config' configMap in the namespace where BAI Standalone is deployed with the following command: \" ${CLI_CMD} patch configmap ibm-cp4ba-common-config -n <BAI-namespace> --type merge -p \"{ \"data\": { \"network_cidr\": \"<cidr range from command>\", \"network_type\": \"<networkType from command>\" } } \" where the values being patched are the CIDR range and networkType that you obtained from the command above respectively."
        printf "\n"
    else
        network_cidr=$(${YQ_CMD} r - <<< "$network_configuration_output" 'spec.clusterNetwork[0].cidr')
        network_type=$(${YQ_CMD} r - <<< "$network_configuration_output" 'spec.networkType')
    fi

    if [[ "$mode" == "upgrade" && ( ! -z $network_cidr ) && ( ! -z $network_type )  ]]; then
        printf "\n"
        info " Patching the ibm-cp4ba-common-config configMap with the Cluster Network details... "
        printf "\n"
        if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $namespace >/dev/null 2>&1; then
            ${CLI_CMD} patch configmap ibm-cp4ba-common-config -n $namespace --type merge -p "{ \"data\": { \"network_cidr\": \"${network_cidr}\", \"network_type\": \"${network_type}\" } }"
        fi
    fi


}

# This function is to generate a truststore password for DB and LDAP verification
# DBACLD-167057
function generate_truststore_password() {
    local pwd_length="${1:-8}"
    local pwd_charset="${2:-A-Za-z0-9}"

    openssl rand -base64 64 | tr -dc "$pwd_charset" | head -c "$pwd_length"

    echo
}

# Helper function for (validate_ssl_certificates) to check a single SSL certificate
# check type -> either certificate or key as the validation command for both are different
# config_name -> the configuration for which we are doing the check for i.e LDAP or DB etc
# cert_path -> full cert path including the required name of the cert to check for
# missing_msg -> display message if the cert is not found
# invalid_msg -> display message if the cert is invalid
# valid_msg -> display message if the cert is valid
function check_ssl_cert() {
    local check_type="$1"
    local config_name="$2"
    local cert_path="$3"
    local missing_msg="$4"
    local invalid_msg="$5"
    local valid_msg="$6"

    
    if [[ ! -f "$cert_path" ]]; then
        MISSING_CERTS+=("$config_name|$cert_path")
        error "$missing_msg"
    else
        if [[ "$check_type" == "certificate" ]]; then
            if openssl x509 -in "$cert_path" -noout -text >/dev/null 2>&1; then
                success "$valid_msg"
            else
                error "$invalid_msg"
                FAILING_CERTS+=("$config_name|$cert_path")
            fi
        else
            #https://jsw.ibm.com/browse/DBACLD-194329
            # Updated command that will tackle all types of formats of a private key
            if openssl rsa -in "$cert_path" -check -noout >/dev/null 2>&1 || openssl ec -in "$cert_path" -check -noout >/dev/null 2>&1 || openssl pkcs8 -in "$cert_path" -inform PEM -nocrypt -noout >/dev/null 2>&1; then
                success "$valid_msg"
            else
                error "$invalid_msg"
                FAILING_CERTS+=("$config_name|$cert_path")
            fi
        fi
    fi
    
}

# Helper function for (validate_ssl_certificates) to print summary of cert check results
function print_cert_summary() {
    if [[ ${#MISSING_CERTS[@]} -gt 0 ]]; then
        error "The following SSL certificates are missing or incorrectly named. Please ensure these files are present and correctly named before proceeding:\n"
        printf "%-28s | %-80s\n" "Configuration" "Missing Certificate Path"
        printf -- "-----------------------------------------------------------------------------------------------------------------------------------------------\n"
        for entry in "${MISSING_CERTS[@]}"; do
            IFS="|" read -r config path <<< "$entry"
            printf "%-28s | %-80s\n" "$config" "$path"
        done
    fi
    if [[ ${#FAILING_CERTS[@]} -gt 0 ]]; then
        error "The following SSL certificates are present but failed validation. Please check the certificate files and replace them if necessary:\n"
        printf "%-28s | %-80s\n" "Configuration" "Invalid Certificate Path"
        printf -- "-----------------------------------------------------------------------------------------------------------------------------------------------\n"
        for entry in "${FAILING_CERTS[@]}"; do
            IFS="|" read -r config path <<< "$entry"
            printf "%-28s | %-80s\n" "$config" "$path"
        done
    fi
    if [[ ${#MISSING_CERTS[@]} -gt 0 || ${#FAILING_CERTS[@]} -gt 0 ]]; then
        error "Resolve the above SSL certificate issues before continuing with the \"generate\" mode of the bai-prerequisites.sh script."
        SSL_CERT_ERROR_TAG=true
    else
        success "All required certificates are present and valid."
        SSL_CERT_ERROR_TAG=false
    fi
}

# Validates the presence and format of required LDAP and external PostgreSQL SSL certificates.
# Logs status for each cert, and prints a summary table of any missing or invalid ones before exiting.
# https://jsw.ibm.com/browse/DBACLD-180201
function validate_ssl_certificates() {
    INFO "Checking if all LDAP and external PostgreSQL certificates have been copied and are in a valid format"

    SSL_CERT_ERROR_TAG=false

    MISSING_CERTS=()
    FAILING_CERTS=()

    # Read LDAP SSL flag only if LDAP is enabled for BAI S.
    # BAI S can be deployed without an LDAP 
    if [[ -f "$LDAP_PROPERTY_FILE" ]]; then
        ldap_ssl_enabled=$(prop_ldap_property_file LDAP_SSL_ENABLED | tr '[:upper:]' '[:lower:]')
    else
        ldap_ssl_enabled="false"
    fi

    # LDAP certificate check (or skip if SSL isn’t enabled)
    if [[ "$ldap_ssl_enabled" != "true" ]]; then
        info "Skipping SSL certificate validation for LDAP, as SSL is not enabled for LDAP configuration in the current setup."
        #SSL_CERT_ERROR_TAG=false
    else
        check_ssl_cert \
        "certificate" \
        "LDAP" \
        "${LDAP_SSL_CERT_FOLDER}/ldap-cert.crt" \
        "LDAP SSL certificate is missing." \
        "LDAP SSL certificate is invalid." \
        "LDAP SSL certificate is valid."
    fi

    # External PostgreSQL cert checks for IM, ZEN, BTS
    for ext_db in IM ZEN BTS; do
        flag_var="EXTERNAL_POSTGRESDB_FOR_${ext_db}_FLAG"
        external_flag=$(prop_tmp_property_file "$flag_var" \
                        | tr -d '"' \
                        | tr '[:upper:]' '[:lower:]')

        # If the flag is true, we must have a valid cert
        # External postgres DB for BTS/IM/ZEN if enabled should have three certs root.crt, client.crt and client.key
        if [[ "$external_flag" == "true" ]]; then

            cert_folder_var="${ext_db}_DB_SSL_CERT_FOLDER"
            cert_folder="${!cert_folder_var}"
            server_cert_path="${cert_folder}/root.crt"
            clientkey_cert_path="${cert_folder}/client.key"
            client_cert_path="${cert_folder}/client.crt"

            check_ssl_cert \
            "certificate" \
            "External Postgres for $ext_db" \
            "$server_cert_path" \
            "SSL certificate for the external database to be used by $ext_db is missing." \
            "SSL certificate for the external database to be used by $ext_db is invalid." \
            "SSL certificate for the external database to be used by $ext_db is valid."
            
            check_ssl_cert \
            "key" \
            "External Postgres for $ext_db" \
            "$clientkey_cert_path" \
            "Client Key for the external database to be used by $ext_db is missing." \
            "Client Key for the external database to be used by $ext_db is invalid." \
            "Client Key for the external database to be used by $ext_db is valid."
            
            check_ssl_cert \
            "certificate" \
            "External Postgres for $ext_db" \
            "$client_cert_path" \
            "Client SSL certificate for the external database to be used by $ext_db is missing." \
            "Client SSL certificate for the external database to be used by $ext_db is invalid." \
            "Client SSL certificate for the external database to be used by $ext_db is valid."
        else
            info "Skipping SSL certificate validation for external Postgres for ${ext_db}, as external Postgres for ${ext_db} is not enabled in the current setup."
        fi
    done

    print_cert_summary
}

# Fixes: https://jsw.ibm.com/browse/DBACLD
# Validates that all required fields in a property file have valid values.
# Marks all entries in "OPTIONAL_PARAMETERS_LIST" as optional by appending them to the TEMPORARY_PROPERTY_FILE under "OPTIONAL_PARAMETERS:"
# These optional parameters are skipped in validate_property_file_required_fields()
function mark_optional() {
  if grep -q '^OPTIONAL_PARAMETERS:' "$TEMPORARY_PROPERTY_FILE"; then
    # Get the existing line and remove SSL parameters from it
    local existing_line=$(grep '^OPTIONAL_PARAMETERS:' "$TEMPORARY_PROPERTY_FILE")
    local existing_params=$(echo "$existing_line" | sed 's/^OPTIONAL_PARAMETERS://')
    
    # Remove SSL parameters from existing params
    local cleaned_params=$(echo "$existing_params" | sed 's/,LDAP_SSL_SECRET_NAME//g' | sed 's/LDAP_SSL_SECRET_NAME,//g' | sed 's/LDAP_SSL_SECRET_NAME//g')
    cleaned_params=$(echo "$cleaned_params" | sed 's/,LDAP_SSL_CERT_FILE_FOLDER//g' | sed 's/LDAP_SSL_CERT_FILE_FOLDER,//g' | sed 's/LDAP_SSL_CERT_FILE_FOLDER//g')
    
    # Remove the old line
    ${SED_COMMAND} '/^OPTIONAL_PARAMETERS:/d' "$TEMPORARY_PROPERTY_FILE"
    
    # Add new parameters to the cleaned list
    local final_params="$cleaned_params"
    for key in "${OPTIONAL_PARAMETERS_LIST[@]}"; do
      if [[ -n "$final_params" ]]; then
        final_params="$final_params,$key"
      else
        final_params="$key"
      fi
    done
    
    # Remove leading/trailing commas and write the new line
    final_params=$(echo "$final_params" | sed 's/^,//' | sed 's/,$//')
    if [[ -n "$final_params" ]]; then
      printf 'OPTIONAL_PARAMETERS:%s\n' "$final_params" >> "$TEMPORARY_PROPERTY_FILE"
    fi
  else
    if [[ ${#OPTIONAL_PARAMETERS_LIST[@]} -gt 0 ]]; then
      local joined_keys
      joined_keys=$(printf '%s,' "${OPTIONAL_PARAMETERS_LIST[@]}")
      joined_keys=${joined_keys%,}
      printf 'OPTIONAL_PARAMETERS:%s\n' "$joined_keys" >> "$TEMPORARY_PROPERTY_FILE"
    fi
  fi
}

# Empty values or {Base64} are considered invalid.
# For comma-separated values, each part must be non-empty.
function validate_property_file_required_fields() {

    local property_file="$1"

    # Load optional parameters from file
    local optional_line
    optional_line=$(grep '^OPTIONAL_PARAMETERS:' "$TEMPORARY_PROPERTY_FILE" | sed 's/^OPTIONAL_PARAMETERS://')
    
    # Split into array
    local OPTIONAL_PARAMETERS=()
    if [[ -n "$optional_line" ]]; then
        local IFS=','
        for param in $optional_line; do
            OPTIONAL_PARAMETERS+=("$param")
        done
    fi

    # Find all non-comment, non-blank property keys that are empty and not optional
    local missing_required=()

    while IFS='=' read -r key value; do
        # Remove whitespace and quotes
        key=$(echo "$key" | sed -e 's/^ *//' -e 's/ *$//')
        value=$(echo "$value" | sed -e 's/^ *//' -e 's/"//g' -e 's/ *$//')

        # Skip comments and blank lines
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue

        # Skip if key is in OPTIONAL_PARAMETERS
        local is_optional=false
        for optional_param in "${OPTIONAL_PARAMETERS[@]}"; do
            if [[ "$optional_param" == "$key" ]]; then
                is_optional=true
                break
            fi
        done

        if [[ "$is_optional" == true ]]; then
            continue
        fi

        # Fail early if value is <Required>, {Base64}
        if [[ "$value" == "<Required>" || "$value" == "{Base64}" ]]; then
            MISSING_REQUIRED_PARAMETERS=true
            break
        fi

        # Check if the value is empty
        local invalid=0
        if [[ -z "$value" ]]; then
            invalid=1
        fi

        if [[ $invalid -eq 1 ]]; then
            missing_required+=("$key")
        fi
    done < "$property_file"

    if [[ "$MISSING_REQUIRED_PARAMETERS" != true ]]; then
        if (( ${#missing_required[@]} )); then
            local uniq_missing=()
            local temp_file="/tmp/validate_temp.$$"
            printf "%s\n" "${missing_required[@]}" | sort -u > "$temp_file"
            while IFS= read -r line; do
                uniq_missing+=("$line")
            done < "$temp_file"
            rm -f "$temp_file"
            
            error "The following required properties are missing values in $property_file:"
            INFO "Parameter Name"
            for param in "${uniq_missing[@]}"; do
                printf "$param\n"
            done
            error "Please provide a non-empty value for each of the above parameters."
            MISSING_REQUIRED_PARAMETERS=true
        else
            success "All required properties in $property_file have valid values."
        fi
    fi
}

#DBACLD-187443: Skip the creation of `ibm-cert-manager` project if cert-manager is already installed
# This function will detect if there's an existing cert-manager (eg: Redhat Openshift cert-manger or Helm cert-manager) installed in the cluster.  If it is, we'll skip creating the ibm-cert-manager ns.
# this function should return 0 if cert-manager is found, 1 otherwise
function is_cert_manager_installed(){

    info "Checking to see if any cert-manager is installed\n"
    "$CLI_CMD" get subscription.operators.coreos.com -A |grep  "cert-manager"  >  /dev/null 2>&1 # this will catch the packagenames of all cert-manager-operators
    if [ $? -eq 0 ]; then
        warning "There is a cert-manager Subscription already existed\n"
    fi

    local webhook_ns=$("$CLI_CMD" get deployments -A | grep cert-manager-webhook | cut -d ' ' -f1)
    if [ ! -z "$webhook_ns" ]; then
        warning "There is a cert-manager-webhook pod Running, so most likely another cert-manager is already installed\n"
        info "Continue to check further\n"

        # Check if the cert-manager-webhook is owned by ibm-cert-manager-operator
        local api_version=$("$CLI_CMD" get deployments -n "$webhook_ns" cert-manager-webhook -o jsonpath='{.metadata.ownerReferences[*].apiVersion}' --ignore-not-found)
        if [ ! -z "$api_version" ]; then
            if [ "$api_version" == "$CERT_MANAGER_V1ALPHA1_OWNER" ]; then
                error "Cluster has not deactivated LTSR ibm-cert-manager-operator yet.  Please do so before proceeding."
                return 0
                exit 1
            fi

            if [ "$api_version" != "$CERT_MANAGER_V1_OWNER" ]; then
                warning "Cluster has a non ibm-cert-manager-operator already installed, skipping"
                return 0
            fi

            # IBM cert-manager is installed (regardless of namespace)
            if [[ "$webhook_ns" != "$CERT_MANAGER_PROJECT" ]]; then
                warning "IBM cert-manager is installed but in namespace: $webhook_ns (expected: $CERT_MANAGER_PROJECT)"
            else
                info "IBM cert-manager is already installed in the correct namespace: $webhook_ns"
            fi
            return 0
        else
            warning "Cluster has a RedHat cert-manager or Helm cert-manager, skipping"
            return 0
        fi
    else
        info "There is no cert-manager-webhook pod running\n"
        return 1
    fi
}
#DBACLD-187443: Skip the creation of `ibm-cert-manager` project if cert-manager is already installed
# This function will remove the any catalog entry out of the catalog source list if it exists
# There are three parameters:
# 1. input_file: The input YAML file containing the catalog sources
# 2. output_file: The output YAML file to write the modified catalog sources
# 3. name_to_be_removed: The name of the catalog source to be removed. (eg: ibm-cert-manager-catalog)
function remove_item_from_cs() {
    local input_file="$1"
    local output_file="$2"
    local name_to_be_removed="$3"


    # Create an empty output file
    > "$output_file"

    # Process documents one by one (yq v3.3.0 approach)
    doc_index=0
    first_doc=true

    while true; do
        # Try to read the document at current index
        doc_content=$($YQ_CMD r "$input_file" --doc $doc_index 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$doc_content" ]; then
            break
        fi

        # Get the catalog name
        catalog_name=$($YQ_CMD r "$input_file" --doc $doc_index metadata.name 2>/dev/null)

        # If this is not the cert-manager catalog, include it
        if [ "$catalog_name" != "$name_to_be_removed" ]; then
            if [ "$first_doc" = true ]; then
                echo "$doc_content" >> "$output_file"
                first_doc=false
            else
                echo "---" >> "$output_file"
                echo "$doc_content" >> "$output_file"
            fi
        fi

        ((doc_index++))
    done
}

# This function is to patch the kafka strimzi podset for an upgrade to a version having Events Operator 5.2 or higher
# The function checks if events operator subscription is on channel 5.2 and if so gets the kafka strimzi podset and replaces an annotation which will allow the zen upgrade to complete
# The subscription for events operator is updated after the new CR is applied and the foundation-operator applies the new operand request, so this function is called during upgradeDeploymentStatus
# For https://jsw.ibm.com/browse/DBACLD-199163 https://jsw.ibm.com/browse/DBACLD-199093
function patch_strimzi_podset(){
    local operator_namespace=$1
    local services_namespace=$2

    echo "Checking ibm-events-operator subscription channel..."
    # Check if the subscription exists
    events_operator_subscription_exists=$(${CLI_CMD} get subscription.operators.coreos.com ibm-events-operator -n $operator_namespace -o name --no-headers 2>/dev/null || echo "")

    if [[ -z "$events_operator_subscription_exists" ]]; then
        echo "Subscription 'ibm-events-operator' not found, skipping"
        strimzi_patched=true
        return
    fi

    # Get the subscription channel - YQ 3.3 compatible syntax
    events_operator_channel=$(${CLI_CMD} get subscription.operators.coreos.com ibm-events-operator -n $operator_namespace -o yaml | ${YQ_CMD} read - spec.channel)

    echo "Current channel: $events_operator_channel"

    # Check if channel is v5.2
    if [[ "$events_operator_channel" == "v5.2" ]]; then
        echo "Events Operator Channel is v5.2, proceeding to check if the events operator is running..."

        # Find the operator pod that starts with ibm-events-operator-v5.2
        events_operator_pod=$(${CLI_CMD} get pods --no-headers -n $operator_namespace -o custom-columns=":metadata.name" | grep "^ibm-events-operator-v5.2" || echo "")

        if [[ -z "$events_operator_pod" ]]; then
            echo "'ibm-events-operator-v5.2' pod is not found"
            return
        fi

        echo "Found operator pod: $events_operator_pod"

        # Check if the pod is in Ready state
        events_operator_pod_ready=$(${CLI_CMD} get pod "$events_operator_pod" -n $operator_namespace -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

        if [[ "$events_operator_pod_ready" != "True" ]]; then
            echo "Operator pod '$events_operator_pod' is not in Ready state"
            return
        fi

        # Get the StrimziPodSet resource
        kafka_podset_exists=$(${CLI_CMD} get strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n $services_namespace -o name --no-headers 2>/dev/null || echo "")

        if [[ -z "$kafka_podset_exists" ]]; then
            echo "StrimziPodSet 'iaf-system-kafka' not found"
            return
        fi

        echo "Found StrimziPodSet 'iaf-system-kafka'"

        # Get the current kafka version from the annotation - YQ 3.3 compatible syntax
        kafka_annotation_value=$(${CLI_CMD} get strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n $services_namespace -o yaml | ${YQ_CMD} read - "metadata.annotations[strimzi.io/kafka-version]" 2>/dev/null || echo "")

        if [[ -z "$kafka_annotation_value" || "$kafka_annotation_value" == "null" ]]; then
            strimzi_patched=true
            return
        fi

        echo "Current kafka version: $kafka_annotation_value"

        # Apply the patch directly
        echo "Applying patch to update annotations..."
        ${CLI_CMD} patch strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n $services_namespace --type=merge -p "{\"metadata\":{\"annotations\":{\"strimzi.io/kafka-version\":null,\"ibmevents.ibm.com/kafka-version\":\"$kafka_annotation_value\"}}}"

        echo "Successfully updated annotations:"
        echo "- Removed: strimzi.io/kafka-version"
        echo "- Added: ibmevents.ibm.com/kafka-version: $kafka_annotation_value"
        strimzi_patched=true
    else
        echo "Events operator is not at channel v5.2"
    fi
}


#############################################################
##### Functions to install IBM Usage Metering Operator ######
# Function to create the ibm usage metering connection point secret
# It uses the Entitlement key to generate a secret named bai-ums-secret
# In the future the entitlement key secret already created would be used
# Function to extract entitlement key password from ibm-entitlement-key secret
# Enhanced to support global pull-secret fallback for OpenShift clusters
# https://jsw.ibm.com/browse/DBACLD-225399
function get_entitlement_key_from_secret() {
    local secret_name="$1"
    local namespace="$2"
    local source_secret_name=""
    local source_namespace=""
    local dockerconfigjson=""

    info "Extracting entitlement key from secret '$secret_name' in namespace '$namespace'..."

    # Step 1: Check whether the requested secret exists in the provided namespace
    if ${CLI_CMD} get secret "$secret_name" -n "$namespace" &>/dev/null; then
        source_secret_name="$secret_name"
        source_namespace="$namespace"
        info "Found secret '$source_secret_name' in namespace '$source_namespace'"
    else
        warning "Secret '$secret_name' not found in namespace '$namespace'. Checking 'pull-secret' in namespace 'openshift-config'..."

        # Step 2: If the original secret is not present, fall back to the cluster pull-secret.
        if ${CLI_CMD} get secret pull-secret -n openshift-config &>/dev/null; then
            source_secret_name="pull-secret"
            source_namespace="openshift-config"
            info "Found fallback secret '$source_secret_name' in namespace '$source_namespace'"
        else
            error "Neither secret '$secret_name' in namespace '$namespace' nor secret 'pull-secret' in namespace 'openshift-config' was found."
            return 1
        fi
    fi

    # Step 3: Extract .dockerconfigjson using oc's go-template (bypasses yq key-escaping issues)
    dockerconfigjson=$(${CLI_CMD} get secret "$source_secret_name" -n "$source_namespace" \
        -o go-template='{{index .data ".dockerconfigjson" | base64decode}}' 2>/dev/null)

    if [[ -z "$dockerconfigjson" ]]; then
        error "Failed to extract .dockerconfigjson from secret '$source_secret_name' in namespace '$source_namespace'."
        return 1
    fi

    # Step 3: Extract password for cp.icr.io (yq v3 handles the nested path fine)
    entitlement_key=$(printf '%s' "$dockerconfigjson" | ${YQ_CMD} r - 'auths."cp.icr.io".password')

    # Step 4: If password field missing, decode the auth field
    if [[ -z "$entitlement_key" ]] || [[ "$entitlement_key" == "null" ]]; then
        local auth_value=$(printf '%s' "$dockerconfigjson" | ${YQ_CMD} r - 'auths."cp.icr.io".auth')
        if [[ -n "$auth_value" ]] && [[ "$auth_value" != "null" ]]; then
            local decoded_auth=$(printf '%s' "$auth_value" | base64 -d)
            entitlement_key=$(printf '%s' "$decoded_auth" | sed 's/^[^:]*://')
        fi
    fi

    # Step 6: Final validation
    if [[ -z "$entitlement_key" ]] || [[ "$entitlement_key" == "null" ]]; then
        error "Failed to extract entitlement key from secret '$source_secret_name' in namespace '$source_namespace'."
        return 1
    fi

    success "Entitlement key extracted successfully from '$source_secret_name' in namespace '$source_namespace'"
    return 0
}

# Function to patch UMS subscription with new channel
# https://jsw.ibm.com/browse/DBACLD-225399
function patch_ums_subscription() {
    local operator_namespace=$1
    local channel=$2
    local catalog_namespace=$3
    
    # Find subscription with "ibm-usage-metering" in the name
    local subscription_name=$(${CLI_CMD} get subscription -n "$operator_namespace" --no-headers 2>/dev/null | grep "ibm-usage-metering" | awk '{print $1}' | head -n 1)
    
    if [ -z "$subscription_name" ]; then
        error "No subscription containing 'ibm-usage-metering' found in namespace '$operator_namespace'"
        return 1
    fi
    
    info "Found subscription: $subscription_name"
    
    # Patch channel
    info "Patching subscription with channel '$channel'..."
    ${CLI_CMD} patch subscription "$subscription_name" -n "$operator_namespace" \
        --type='json' \
        -p='[{"op": "replace", "path": "/spec/channel", "value": "'$channel'"}]'
    
    if [ $? -ne 0 ]; then
        error "Failed to patch subscription '$subscription_name' with channel"
        return 1
    fi
    
    success "Subscription '$subscription_name' patched successfully with channel '$channel'"
    
    # Patch sourceNamespace if provided
    if [ -n "$catalog_namespace" ]; then
        info "Patching subscription with sourceNamespace '$catalog_namespace'..."
        ${CLI_CMD} patch subscription "$subscription_name" -n "$operator_namespace" \
            --type='json' \
            -p="[{'op': 'replace', 'path': '/spec/sourceNamespace', 'value': '$catalog_namespace'}]"
        
        if [ $? -eq 0 ]; then
            success "Subscription '$subscription_name' patched successfully with sourceNamespace '$catalog_namespace'"
        else
            error "Failed to patch subscription '$subscription_name' with sourceNamespace"
            return 1
        fi
    fi
    
    return 0
}
# Function to create the connection point secret
# https://jsw.ibm.com/browse/DBACLD-216413
function create_connection_point_secret(){
    local secret_name=$1
    local services_namespace=$2
    local entitlement_key=$3
    # Use a variable to detect if the connection point creation passed 
    connection_point_secret_creation="false"

    if ${CLI_CMD} get secret "$secret_name" -n "${services_namespace}" >/dev/null 2>&1; then
        success "Secret $secret_name already exists in namespace $services_namespace, skipping recreation."
        connection_point_secret_creation="true"
        return 0
    fi
    info "Creating the $secret_name secret using the Entitlement key which will be used for configuring the connection point in the project $services_namespace..."
    echo

    if ${CLI_CMD} create secret generic "$secret_name" --from-literal="token=$entitlement_key" -n "$services_namespace"; then
    success "Secret $secret_name has been successfully created"
    connection_point_secret_creation="true"
    else
        fail "Failed to create secret $secret_name."
    fi

}

# Function to process and apply IBMServiceMeterDefinition YAMLs
# Parameters:
#   $1 - namespace
#   $2 - file location (directory containing YAML files)
# https://jsw.ibm.com/browse/DBACLD-216414
function apply_service_meter_definitions() {
    local namespace="$1"
    local file_location="$2"

    if [[ -z "$file_location" ]]; then
        error "File location parameter is required"
        return 1
    fi

    if [[ ! -d "$file_location" ]]; then
        error "Directory '$file_location' does not exist"
        return 1
    fi

    info "Processing IBMServiceMeterDefinition YAMLs in: $file_location"
    info "Target namespace for the YAMLs to be applied in: $namespace"

    # Process each YAML file in the directory
    for yaml_file in "$file_location"/*.yaml "$file_location"/*.yml; do
        # Skip if no files match
        [[ -e "$yaml_file" ]] || continue

        local filename=$(basename "$yaml_file")

        # Check if the file is of kind IBMServiceMeterDefinition
        local kind=$(${YQ_CMD} r "$yaml_file" 'kind' 2>/dev/null)

        if [[ "$kind" != "IBMServiceMeterDefinition" ]]; then
            #echo "Skipping $filename - not an IBMServiceMeterDefinition (kind: $kind)"
            continue
        fi

        # Create a temporary file for modifications
        local temp_file="${TEMP_FOLDER}/${filename}"
        cp "$yaml_file" "$temp_file"

        # Update namespace
        ${YQ_CMD} w -i "$temp_file" "metadata.namespace" "$namespace"

        # Apply the modified YAML
        info "  - Applying $filename to namespace $namespace"
        if ${CLI_CMD} apply -f "$temp_file" -n "$namespace"; then
            success "Successfully applied $filename"
        else
            error "Failed to apply $filename"
        fi

        # Clean up temp file
        rm -f "$temp_file"
        echo ""
    done

    success "All IBMServiceMeterDefinition Static CRs for the Usage Metering Service have been applied."
    echo
}


# Function to process and apply IBMUsageMetering YAMLs. As of right now there is only 1 yaml to be applied but function can handle multiple
# Parameters:
#   $1 - namespace (replaces REPLACE_NAMESPACE)
#   $3 - file location (directory containing YAML files)
# https://jsw.ibm.com/browse/DBACLD-216413
function apply_usage_metering_definition () {
    local namespace="$1"
    local secret_name="$2"
    local file_location="$3"
    local mode="$4"
    local airgap_mode="$5"


    if [[ -z "$file_location" ]]; then
        error "File location parameter is required"
        return 1
    fi

    if [[ ! -d "$file_location" ]]; then
        error "Directory '$file_location' does not exist"
        return 1
    fi

    # Create temp folder if it doesn't exist
    mkdir -p "$TEMP_FOLDER"

    info "Processing IBMUsageMetering YAMLs in: $file_location"
    info "Target namespace: $namespace"

    # Process each YAML file in the directory
    for yaml_file in "$file_location"/*.yaml "$file_location"/*.yml; do
        # Skip if no files match
        [[ -e "$yaml_file" ]] || continue

        local filename=$(basename "$yaml_file")

        # Check if the file is of kind IBMUsageMetering
        local kind=$(${YQ_CMD} r "$yaml_file" 'kind' 2>/dev/null)

        if [[ "$kind" != "IBMUsageMetering" ]]; then
            echo "Skipping $filename - not an IBMUsageMetering (kind: $kind)"
            continue
        fi


        # Create a temporary file for modifications
        local temp_file="${TEMP_FOLDER}/${filename}"
        cp "$yaml_file" "$temp_file"

        # Check and replace namespace if it contains REPLACE_NAMESPACE
        local current_namespace=$(${YQ_CMD} r "$temp_file" 'metadata.namespace' 2>/dev/null)
        if [[ "$current_namespace" == "REPLACE_NAMESPACE" ]]; then
            ${YQ_CMD} w -i "$temp_file" "metadata.namespace" "$namespace"
        fi

        if [[ "$airgap_mode" == "true" || "$airgap_mode" == "yes" || "$airgap_mode" == "Yes" ]]; then
            ${YQ_CMD} d -i "$temp_file" "spec.sender.softwareCentral"
        else
            # Check and replace secret name if it contains REPLACE_SECRET_NAME
            local current_secret=$(${YQ_CMD} r "$temp_file" 'spec.sender.softwareCentral.entitlementKeySecret' 2>/dev/null)
            if [[ "$current_secret" == "REPLACE_SECRET_NAME" ]]; then
                ${YQ_CMD} w -i "$temp_file" "spec.sender.softwareCentral.entitlementKeySecret" "$secret_name"
            fi

            # If mode is dev, set sandbox to true
            # https://jsw.ibm.com/browse/DBACLD-225399
            if [[ "$mode" == "dev" ]]; then
                ${YQ_CMD} w -i "$temp_file" "spec.sender.softwareCentral.sandbox" "true"
            fi
        fi

        # Apply the modified YAML
        info "  - Applying $filename to namespace $namespace"
        if ${CLI_CMD} apply -f "$temp_file" -n "$namespace"; then
            success "Successfully applied $filename"
        else
            error "Failed to apply $filename"
        fi

        # Clean up temp file
        rm -f "$temp_file"
        echo ""
    done

    success "All IBM Usage Metering Static CRs for the Usage Metering Service have been applied."
    echo
}

#############################################################

# Function to apply Subscription for the UMS Operator
# https://jsw.ibm.com/browse/DBACLD-216414
function apply_subscription() {
    local namespace="$1"
    local channel="$2"
    local catalog_name="$3"
    local catalog_namespace="$4"
    UMS_OLM_SUBSCRIPTION_TMP=${TEMP_FOLDER}/.ums_subscription.yaml

    info "Creating IBM Usage Metering Subscription in namespace: $namespace"

    if [ ! -f "$UMS_OLM_SUBSCRIPTION" ]; then
        error "Template file $UMS_OLM_SUBSCRIPTION not found"
        exit 1
    fi

    # Copy template to temp file
    cp "$UMS_OLM_SUBSCRIPTION" "$UMS_OLM_SUBSCRIPTION_TMP"

    # Replace placeholders using sed
    ${SED_COMMAND} "s/REPLACE_NAMESPACE/${namespace}/g" "$UMS_OLM_SUBSCRIPTION_TMP"
    ${SED_COMMAND} "s/REPLACE_CHANNEL/${channel}/g" "$UMS_OLM_SUBSCRIPTION_TMP"

    # Set sourceNamespace and source using yq
    ${YQ_CMD} w -i "$UMS_OLM_SUBSCRIPTION_TMP" "spec.sourceNamespace" "$catalog_namespace"
    ${YQ_CMD} w -i "$UMS_OLM_SUBSCRIPTION_TMP" "spec.source" "$catalog_name"

    ${CLI_CMD} apply -f ${UMS_OLM_SUBSCRIPTION_TMP}
    if [ $? -eq 0 ]
        then
        success "UMS Operator Subscription Created!"
    else
        error "UMS Operator Subscription creation failed"
        exit 1
    fi
}

# Main installation function for UMS either the freshinstall or the upgrade
# based on argument 3 the function is able to perform the required steps for either of those scenarios
# $1 Operator namespace
# $2 Services namespace
# $3 scenario i.e fresh_install or upgrade
# $4 entitlement_key which is the key used to generate the connection point secret
# $5 airgap_mode which tells us if the user is using airgap (we will only get this data during fresh install and for upgrade we will get to know this based on the contents of the ibm-entitlement-key)
# https://jsw.ibm.com/browse/DBACLD-224820
function install_ibm_usage_metering() {
    local operator_namespace=$1
    local services_namespace=$2
    local scenario=$3
    local entitlement_key=$4
    local runtime_mode=$5
    local catalog_namespace=$6
    local airgap_mode=$7
    local create_secret="true"
    echo ""
    echo "=========================================="
    echo "IBM Usage Metering Operator Installation"
    echo "=========================================="
    echo ""

    # Step 1: Check if CatalogSource exists
    echo "Step 1: Checking CatalogSource..."
    if ! ${CLI_CMD} get catalogsource "$UMS_CATALOG_VERSION" -n "$catalog_namespace" &>/dev/null; then
        error "CatalogSource '$UMS_CATALOG_VERSION' not found in namespace '$catalog_namespace'"
        echo ""
        return 1
    fi

    # Wait for CatalogSource to be ready
    echo "Waiting for CatalogSource to be READY..."
    local timeout=300
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local state=$(${CLI_CMD} get catalogsource "$UMS_CATALOG_VERSION" -n "$catalog_namespace" -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null)
        if [ "$state" = "READY" ]; then
            info "IBM Usage Metering CatalogSource is ready."
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [ $elapsed -ge $timeout ]; then
        error "IBM Usage Metering CatalogSource did not become ready in time."
        exit 1
    fi
    echo ""

    # Step 2: Handle Subscription based on scenario
    if [[ "$scenario" == "fresh_install" ]]; then
        # Step 2: Apply Subscription
        info "Creating the IBM Usage Metering Subscription..."
        apply_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$UMS_CATALOG_VERSION" "$catalog_namespace"
        echo ""
    elif [[ "$scenario" == "upgrade" ]]; then
        # For upgrade scenario we might have to apply a new subscription or patch it based on the version
        info "Checking for existing IBM Usage Metering subscription..."
        local subscription_exists=$(${CLI_CMD} get subscription -n "$operator_namespace" --no-headers 2>/dev/null | grep "ibm-usage-metering" | wc -l)
        
        if [ "$subscription_exists" -gt 0 ]; then
            info "Patching existing IBM Usage Metering subscription..."
            patch_ums_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$catalog_namespace"
            if [ $? -ne 0 ]; then
                exit 1
            fi
        else
            info "No IBM Usage Metering subscription found. Creating new subscription..."
            apply_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$UMS_CATALOG_VERSION" "$catalog_namespace"
        fi
        echo ""
    fi

    # Step 3: Wait for UMS operator to be ready
    echo "Waiting for the UMS operator to be ready and in running state"
    timeout=600
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ${CLI_CMD} get csv -n "$operator_namespace" 2>/dev/null | grep -q "ibm-usage-metering.*Succeeded"; then
            echo "Operator is ready"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo " Waiting... (${elapsed}s/${timeout}s)"
    done

    if [ $elapsed -ge $timeout ]; then
        echo "ERROR: Operator did not become ready in time"
        exit 1
    fi
    echo ""

    # This block makes sure the UMS operator pod is running
    timeout=300
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ${CLI_CMD} get pods -n "$operator_namespace" -l app.kubernetes.io/name=ibm-usage-metering-operator --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
            echo "Operator pod is running"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [ $elapsed -ge $timeout ]; then
        echo "WARNING: Operator pod not running yet, but continuing..."
    fi
    echo ""

    # Step 4: Applying the service metering definition static CRs from the descriptors folder
    apply_service_meter_definitions "$services_namespace" "$UMS_STATIC_CR_LOCATION"
    
    # Step 5 which is to create the connection point secret and connection point CR
    # Step 5(a) For airgap deployments, do not create the UMS secret and apply the UsageMetering CR without the softwareCentral section.
    # Step 5(b) For non-airgap deployments, create the secret only when needed and only apply the CR if the secret exists or was created successfully.
    if [[ "$airgap_mode" == "true" || "$airgap_mode" == "yes" || "$airgap_mode" == "Yes" || "$runtime_mode" == "dev" ]]; then
        info "Airgap mode detected. Skipping creation of secret '$UMS_CONNECTION_POINT_SECRET_NAME' and applying UsageMetering CR."
        apply_usage_metering_definition "$services_namespace" "$UMS_CONNECTION_POINT_SECRET_NAME" "$UMS_CONNECTION_POINT_STATIC_CR_LOCATION" "$runtime_mode" "$airgap_mode"
    else
        # Production non-airgap mode only
        if ${CLI_CMD} get secret "$UMS_CONNECTION_POINT_SECRET_NAME" -n "$services_namespace" >/dev/null 2>&1; then
            info "UMS connection point secret '$UMS_CONNECTION_POINT_SECRET_NAME' already exists in namespace '$services_namespace', skipping creation"
            connection_point_secret_creation="true"
        else
            info "UMS connection point secret '$UMS_CONNECTION_POINT_SECRET_NAME' not found in namespace '$services_namespace', the script will now proceed to creating it using the Entitlement key present in the \"ibm-entitlement-key\" secret"

            # For upgrade non-airgap, if the entitlement key was not passed in, retrieve it from an existing secret.
            if [[ -z "$entitlement_key" && "$scenario" == "upgrade" ]]; then
                get_entitlement_key_from_secret "ibm-entitlement-key" "$services_namespace"
                if [ $? -ne 0 ]; then
                    warning "Failed to extract entitlement key from secret.Refer to https://www.ibm.com/docs/en/bai/$BAI_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point custom resource file."
                    create_secret="false"
                fi
            fi

            # For fresh install non-airgap, entitlement key is expected to be passed in. If not present, do not create the secret or CR.
            if [[ -z "$entitlement_key" ]]; then
                warning "[IMPORTANT]The IBM Entitlement key is not available, so the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file will not be created.Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file."
                create_secret="false"
            fi
            
            # Creating the connection point secret only if we were able to retrieve the entitlement key
            if [[ "$create_secret" == "true" ]]; then
                create_connection_point_secret "$UMS_CONNECTION_POINT_SECRET_NAME" "$services_namespace" "$entitlement_key"
                # Note: create_connection_point_secret sets connection_point_secret_creation="true" on success
            fi
        fi
        
        # Apply CR only if secret exists or was successfully created
        # The connection_point_secret_creation flag is set by create_connection_point_secret function
        if [[ "$connection_point_secret_creation" == "true" ]]; then
            info "Applying the usage metering static CRs from the descriptors folder"
            apply_usage_metering_definition "$services_namespace" "$UMS_CONNECTION_POINT_SECRET_NAME" "$UMS_CONNECTION_POINT_STATIC_CR_LOCATION" "$runtime_mode" "$airgap_mode"
        else
            warning "[IMPORTANT]Since the $UMS_CONNECTION_POINT_SECRET_NAME could not be created, the UsageMetering connection point Custom Resource file will not be created.Refer to https://www.ibm.com/docs/en/bai/$BAI_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file."
        fi
    fi
        
    echo "================================================="
    echo "Usage Metering Operator Installation Complete!"
    echo "================================================="
    echo ""

}

# Patch an existing IBMLicensing resource to configure Software Central uploads.
# Arguments:
#   $1 - secret name to set in spec.softwareCentral.entitlementKeySecret
#   $2 - IBMLicensing resource name
function patch_ils_instance() {
    local secret_name="$1"
    local licensing_name="$2"
    local patch_payload=""

    # Build the merge patch payload with sandbox=false for GA
    patch_payload=$(cat <<EOF
{
  "spec": {
      "softwareCentral": {
        "enable": true,
        "frequency": "5 0 * * *",
        "entitlementKeySecret": "$secret_name"
      }
    }
}
EOF
)

    # Add sandbox only in dev mode
    if [[ "$mode" == "dev" ]]; then
        info "Runtime mode is dev, setting spec.softwareCentral.sandbox=true"
        patch_payload=$(cat <<EOF
{
  "spec": {
      "softwareCentral": {
        "enable": true,
        "frequency": "5 0 * * *",
        "entitlementKeySecret": "$secret_name",
        "sandbox": true
      }
  }
}
EOF
)
    fi

    # Patch the IBMLicensing custom resource
    info "Patching IBMLicensing resource \"$licensing_name\""
    if ${CLI_CMD} patch IBMLicensing "$licensing_name" --type=merge -p "$patch_payload"; then
        success "Successfully patched IBMLicensing resource \"$licensing_name\""
        return 0
    else
        error "Failed to patch IBMLicensing resource \"$licensing_name\""
        return 1
    fi
}


# Configure Software Central integration for an existing IBMLicensing resource.
#
# Flow:
#   1. Check whether an IBMLicensing resource exists.
#   2. If no IBMLicensing resource exists, skip the configuration.
#   3. Check whether the ILS connection point secret already exists.
#   4. If the secret does not exist:
#      - use the provided entitlement key if available
#      - otherwise, for upgrade scenario only, try to retrieve it from ibm-entitlement-key
#      - if no entitlement key can be obtained, skip secret creation and CR patching
#      - if entitlement key is available, create the secret
#   5. Patch the IBMLicensing resource to enable Software Central uploads.
#
# Arguments:
#   $1 - namespace where the ILS connection point secret should exist
#   $2 - services namespace where ibm-entitlement-key may exist
#   $3 - entitlement key value; may be empty during upgrade
#   $4 - scenario value such as "upgrade" or "fresh_install"
function setup_ils_configuration_for_vpc_metrics() {
    local licensing_namespace="$1"
    local services_namespace="$2"
    local entitlement_key="$3"
    local scenario="$4"
    local mode="$5"
    local licensing_name=""
    local mode_lower=""
    local create_secret="true"

    # Normalize runtime mode to lowercase for comparison
    mode_lower=$(echo "$mode" | tr '[:upper:]' '[:lower:]')

    # Step 1: Check whether an IBMLicensing resource exists
    info "Checking for IBMLicensing resource..."
    licensing_name=$(${CLI_CMD} get IBMLicensing --no-headers --ignore-not-found 2>/dev/null | awk 'NR==1{print $1}')

    if [[ -z "$licensing_name" ]]; then
        warning "No IBMLicensing resource found. Skipping ILS Software Central configuration."
        return 0
    fi

    success "Found IBMLicensing resource: $licensing_name"

    # Step 2: Check whether the ILS connection point secret already exists
    if ${CLI_CMD} get secret "$ILS_SWC_SECRET_NAME" -n "$licensing_namespace" >/dev/null 2>&1; then
        success "ILS connection point secret '$ILS_SWC_SECRET_NAME' already exists in namespace '$licensing_namespace'."

        # Step 3: Patch the IBMLicensing resource even if the secret already exists
        patch_ils_instance "$ILS_SWC_SECRET_NAME" "$licensing_name" "$mode_lower"
        return $?
    fi

    info "ILS connection point secret '$ILS_SWC_SECRET_NAME' not found in namespace '$licensing_namespace'. The script will attempt to create it."

    # Step 4: If no entitlement key was passed and this is an upgrade, try retrieving it
    if [[ -z "$entitlement_key" && "$scenario" == "upgrade" ]]; then
        info "Entitlement key was not passed in upgrade scenario. Attempting to retrieve it from secret \"ibm-entitlement-key\" in namespace \"$services_namespace\"."

        get_entitlement_key_from_secret "ibm-entitlement-key" "$services_namespace"
        if [ $? -ne 0 ]; then
            warning "Failed to extract entitlement key from secret. Refer to https://www.ibm.com/docs/en/bai/$BAI_RELEASE_BASE for more information on how to create the $ILS_SWC_SECRET_NAME secret and update the IBMLicensing custom resource."
            create_secret="false"
        fi
    fi

    # Step 5: If entitlement key is still empty, do not create the secret or patch the CR
    if [[ -z "$entitlement_key" ]]; then
        warning "Entitlement key is empty. Skipping creation of secret '$ILS_SWC_SECRET_NAME' and the script will skip the patch of IBMLicensing."
        return 0
    fi

    # Step 6: Create the secret only if allowed
    if [[ "$create_secret" == "true" ]]; then
        info "Creating ILS connection point secret '$ILS_SWC_SECRET_NAME' in namespace '$licensing_namespace'"
        create_connection_point_secret "$ILS_SWC_SECRET_NAME" "$licensing_namespace" "$entitlement_key"

        if [[ "$connection_point_secret_creation" == "true" ]]; then
            # Step 7: Patch the IBMLicensing resource after secret creation
            patch_ils_instance "$ILS_SWC_SECRET_NAME" "$licensing_name" "$mode_lower"
            return $?
        else
            warning "[IMPORTANT]Since the $ILS_SWC_SECRET_NAME could not be created, the IBMLicensing instance will not be patched by the script.Refer to https://www.ibm.com/docs/en/bai/$BAI_RELEASE_BASE for more information on how to create the $ILS_SWC_SECRET_NAME secret and patch the IBMLicensing Instance."
        fi
    fi

    return 0
}


# Function to update BTS datastore configuration for tls.key to tls.pk8 migration
# This function checks for the ConfigMap 'ibm-bts-config-extension' and Secret 'bts-datastore-edb-secret'
# and updates tls.key references to tls.pk8 where needed.
#
# Usage: update_bts_datastore_resources $services_namespace
#
# Parameters:
#   $1 - namespace: The CP4BA namespace to check

function update_bts_datastore_resources() {
    local namespace="$1"
    local bts_configmap_name="ibm-bts-config-extension"
    local bts_secret_name="bts-datastore-edb-secret"

    info "Checking if the current deployment has the Secret '$bts_secret_name' and ConfigMap '$bts_configmap_name' created in the namespace: $namespace"
    echo
    # Check if ConfigMap exists
    local cm_exists=false
    if ${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" &> /dev/null; then
        cm_exists=true
        info "ConfigMap '$bts_configmap_name' found in namespace '$namespace'"
    else
        info "ConfigMap '$bts_configmap_name' not found in namespace '$namespace'"
    fi

    # Check if Secret exists
    local secret_exists=false
    if ${CLI_CMD} get secret "$bts_secret_name" -n "$namespace" &> /dev/null; then
        secret_exists=true
        info "Secret '$bts_secret_name' found in namespace '$namespace'"
    else
        info "Secret '$bts_secret_name' not found in namespace '$namespace'"
    fi

    # Exit if neither resource exists
    if [[ "$cm_exists" == "false" && "$secret_exists" == "false" ]]; then
        info "Neither ConfigMap '$bts_configmap_name' nor Secret '$bts_secret_name' exist in this deployment. Skipping the resource updates as they are not required."
        return 0
    fi
    echo
    # Process Secret if it exists
    if [[ "$secret_exists" == "true" ]]; then
        info "Processing Secret '$bts_secret_name' to check for 'tls.key' field..."

        # Check if secret has tls.key using jsonpath
        local has_tls_key=$(${CLI_CMD} get secret "$bts_secret_name" -n "$namespace" -o jsonpath='{.data.tls\.key}' 2>/dev/null)

        if [[ -n "$has_tls_key" ]]; then
            warning "Found 'tls.key' field in Secret '$bts_secret_name'. This field needs to be renamed to 'tls.pk8' for compatibility with the latest BTS version."
            info "Applying patch to rename 'tls.key' to 'tls.pk8' in Secret '$bts_secret_name'..."

            # Create a patch to rename tls.key to tls.pk8
            ${CLI_CMD} patch secret "$bts_secret_name" -n "$namespace" --type=json -p="[
                {\"op\": \"add\", \"path\": \"/data/tls.pk8\", \"value\": \"$has_tls_key\"},
                {\"op\": \"remove\", \"path\": \"/data/tls.key\"}
            ]"

            if [[ $? -eq 0 ]]; then
                success "Successfully renamed 'tls.key' to 'tls.pk8' in Secret '$bts_secret_name'"
            else
                error "Failed to update Secret '$bts_secret_name'. Please check the secret permissions and try again."
                return 1
            fi
        else
            # Check if tls.pk8 already exists
            local has_tls_pk8=$(${CLI_CMD} get secret "$bts_secret_name" -n "$namespace" -o jsonpath='{.data.tls\.pk8}' 2>/dev/null)
            if [[ -n "$has_tls_pk8" ]]; then
                info "Secret '$bts_secret_name' already has 'tls.pk8' field. No changes needed."
            fi
        fi
    fi

    # Process ConfigMap if it exists
    if [[ "$cm_exists" == "true" ]]; then
        info "Processing ConfigMap '$bts_configmap_name' to check for 'tls.key' file path references..."

        # Get all keys from ConfigMap data section
        local all_keys=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o jsonpath='{.data}' 2>/dev/null)

        if [[ -z "$all_keys" || "$all_keys" == "{}" ]]; then
            warning "No data found in ConfigMap '$bts_configmap_name'. ConfigMap appears to be empty."
        else
            # Find all customPropertyName keys and check for sslKey value
            local ssl_key_num=""
            local custom_prop_names=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o json | grep -o '"customPropertyName[0-9]*"' | tr -d '"')

            if [[ -z "$custom_prop_names" ]]; then
                info "No 'customPropertyName' keys found in ConfigMap '$bts_configmap_name'. No SSL key configuration to update."
            else
                # Check each customPropertyName to find sslKey
                while IFS= read -r key; do
                    if [[ -n "$key" ]]; then
                        local value=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o jsonpath="{.data.$key}" 2>/dev/null)

                        if [[ "$value" == "sslKey" ]]; then
                            # Extract the number from customPropertyNameX
                            ssl_key_num=$(echo "$key" | grep -o '[0-9]*$')
                            info "Found 'sslKey' property at '$key'"
                            break
                        fi
                    fi
                done <<< "$custom_prop_names"

                if [[ -n "$ssl_key_num" ]]; then
                    # Check the corresponding customPropertyValue
                    local custom_prop_value_key="customPropertyValue$ssl_key_num"
                    local current_value=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o jsonpath="{.data.$custom_prop_value_key}" 2>/dev/null)

                    if [[ -n "$current_value" ]]; then

                        # Check if the path ends with tls.key
                        if [[ "$current_value" == *"tls.key" ]]; then
                            local new_value="${current_value%tls.key}tls.pk8"
                            warning "File path ends with 'tls.key' which needs to be updated to 'tls.pk8' for compatibility with the latest BTS version."
                            info "Applying patch to update '$custom_prop_value_key' from '$current_value' to '$new_value'..."

                            # Patch the ConfigMap
                            ${CLI_CMD} patch configmap "$bts_configmap_name" -n "$namespace" --type=json -p="[
                                {\"op\": \"replace\", \"path\": \"/data/$custom_prop_value_key\", \"value\": \"$new_value\"}
                            ]"

                            if [[ $? -eq 0 ]]; then
                                success "Successfully updated the '$custom_prop_value_key' key in ConfigMap '$bts_configmap_name'"
                            else
                                error "Failed to update ConfigMap '$bts_configmap_name'. Please check the configmap '$bts_configmap_name' permissions and try again."
                                return 1
                            fi
                        elif [[ "$current_value" == *"tls.pk8" ]]; then
                            info "File path already ends with 'tls.pk8'. No changes needed."
                        else
                            echo
                        fi
                    else
                        warning "Property '$custom_prop_value_key' not found or is empty in ConfigMap '$bts_configmap_name'."
                        warning "Expected to find the SSL key file path at this property."
                    fi
                else
                    info "No 'sslKey' property found in ConfigMap '$bts_configmap_name'."
                    info "Please verify the '$bts_configmap_name' configmap before proceeding with next steps."
                fi
            fi
        fi
    fi

    success "BTS Datasource resources are compatible with the latest BTS version."
    return 0
}
