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

# Define the required Java version based on CP4BA release
REQUIRED_JAVA_MAJOR_VERSION=17  # Semeru 17 is required for BAI S 

# Directory for common service script
COMMON_SERVICES_SCRIPT_FOLDER=${CUR_DIR}/cpfs/installer_scripts/cp3pt0-deployment

COMMON_SERVICES_SCRIPT_YQ_FOLDER=${CUR_DIR}/cpfs/yq

PREREQUISITES_FOLDER=${CUR_DIR}/bai-prerequisites/project/$1
PREREQUISITES_FOLDER_BAK=${CUR_DIR}/bai-prerequisites-backup/project/$1
PROPERTY_FILE_FOLDER=${PREREQUISITES_FOLDER}/propertyfile
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
ZEN_SECRET_FILE=${ZEN_SECRET_FOLDER}/ibm-zen-metastore-edb-secret.sh
ZEN_CONFIGMAP_FILE=${ZEN_SECRET_FOLDER}/ibm-zen-metastore-edb-cm.yaml

IM_SECRET_FOLDER=${SECRET_FILE_FOLDER}/im_external_db
IM_SECRET_FILE=${IM_SECRET_FOLDER}/ibm-im-datastore-edb-secret.sh
IM_CONFIGMAP_FILE=${IM_SECRET_FOLDER}/ibm-im-datastore-edb-cm.yaml

BTS_SECRET_FOLDER=${SECRET_FILE_FOLDER}/bts_external_db
BTS_SSL_SECRET_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-ssl-secret.sh
BTS_SECRET_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-user-secret.yaml
BTS_CONFIGMAP_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-cm.yaml

CP4A_LDAP_SSL_SECRET_FILE=${LDAP_SSL_SECRET_FOLDER}/ibm-bai-ldap-ssl-cert-secret.sh


LDAP_SECRET_FILE=${SECRET_FILE_FOLDER}/ldap-bind-secret.yaml

# Release/Patch version for CP4BA
# BAI_RELEASE_BASE is for fetch content/foundation operator pod, only need to change for major release.
BAI_RELEASE_BASE="24.0.1"
BAI_PATCH_VERSION="IF007"
# BAI_CSV_VERSION is for checking CP4BA operator upgrade status, need to update for each IFIX
BAI_CSV_VERSION="v24.1.7"
# BAI_CHANNEL_VERSION is for switch CP4BA operator upgrade status, need to update for major release
BAI_CHANNEL_VERSION="v24.1"
# CS_OPERATOR_VERSION is for checking CPFS operator upgrade status, need to update for each IFIX
CS_OPERATOR_VERSION="v4.17.0"
# CS_CHANNEL_VERSION is for for CPFS script -c option, need to update for each IFIX
CS_CHANNEL_VERSION="v4.17"
# CS CHANNEL VERSION that is used in the KC
CS_CHANNEL_KC="4.x_cd"
# CERT_LICENSE_OPERATOR_VERSION is for checking IBM cert-manager/licensing operator upgrade status, need to update for each IFIX
CERT_LICENSE_OPERATOR_VERSION="v4.2.20"
# CERT_LICENSE_CHANNEL_VERSION is for for IBM cert-manager/licensing script -c option, need to update for each IFIX
CERT_LICENSE_CHANNEL_VERSION="v4.2"
# CS_CATALOG_VERSION is for CPFS script -s option, need to update for each IFIX
CS_CATALOG_VERSION="ibm-cs-install-catalog-v4-17-0"
# ZEN_OPERATOR_VERSION is for checking ZenService operator upgrade status, need to update for each IFIX
ZEN_OPERATOR_VERSION="v6.4.0"
# BTS_CHANNEL_VERSION is for for BTS, need to update for each IFIX
BTS_CHANNEL_VERSION="v3.35"
# BTS_CATALOG_VERSION is for BTS 3.35.8.
BTS_CATALOG_VERSION="ibm-bts-operator-catalog-v3-35"
# REQUIREDVER_BTS is for checking bts operator upgrade status before run removal_iaf.sh, need to update for each IFIX
REQUIREDVER_BTS="3.35.8"
# REQUIREDVER_POSTGRESQL is for checking postgresql operator upgrade status before run removal_iaf.sh, need to update for each IFIX
REQUIREDVER_POSTGRESQL="1.25.5"
# EVENTS_OPERATOR_VERSION is for checking IBM Events operator upgrade status, need to update for each IFIX
EVENTS_OPERATOR_VERSION="v5.2.1"
# List of BAI versions that are supported for upgrade to $BAI_CSV_VERSION
MINIMUM_SUPPORTED_UPGRADE_VERSIONS=("24.0." "24.1." )

# Zen metastore EDB configmap name
ZEN_EDB_CFG="ibm-zen-metastore-edb-cm"
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

function prop_ext_ldap_property_file() {
    grep "^${1}=" ${EXTERNAL_LDAP_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_user_profile_property_file() {
    grep "^${1}=" ${USER_PROFILE_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_db_name_user_property_file() {
    grep "^.*${1}=" ${DB_NAME_USER_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_db_name_user_property_file_for_server_name() {
    grep "^.*${1}=" ${DB_NAME_USER_PROPERTY_FILE}|cut -d'.' -f1
}

function prop_osdb_property_file() {
    grep "^.*${1}=" ${DB_NAME_USER_PROPERTY_FILE}|cut -d'=' -f2
}

function prop_db_server_property_file() {
    grep "^${1}=" ${DB_SERVER_INFO_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_db_oracle_server_property_file() {
    grep "^${1}=" ${DB_SERVER_INFO_PROPERTY_FILE}|cut -d'"' -f2
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
        Linux*)     machine="Linux";;
        Darwin*)    machine="Mac";;
        *)          machine="UNKNOWN:${unameOut}"
    esac

    if [[ "$machine" == "Mac" ]]; then
        SED_COMMAND='sed -i ""'
        SED_COMMAND_FORMAT='sed -i "" s/^M//g'
        YQ_CMD=${CUR_DIR}/helper/yq/yq_darwin_amd64
        CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/macos/yq
        COPY_CMD=/bin/cp
    else
        SED_COMMAND='sed -i'
        SED_COMMAND_FORMAT='sed -i s/\r//g'
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

# This function checks if its a valid version during the course of upgrade
# It looks at the current csv version and compares it to the minimum support upgraded versions stored in MINIMUM_SUPPORTED_UPGRADE_VERSIONS.
# The version the operator should be in that channel and not equal to the CSV version of BAI Operator that the scripts are for.
function check_valid_bai_operator_version() {
    local current_operator_version=$1
    valid_bai_operator_version=false
    for version in "${MINIMUM_SUPPORTED_UPGRADE_VERSIONS[@]}"; do
        if [[ "$current_operator_version" == "$version"* && "$current_operator_version" != "${BAI_CSV_VERSION#v}" ]]; then
            valid_bai_operator_version=true
            break
        fi
    done
}

# This function is to generate a truststore password for DB and LDAP verification
# DBACLD-167057
function generate_truststore_password() {
    local pwd_length="${1:-8}"
    local pwd_charset="${2:-A-Za-z0-9}"
    local machine_lower=$(echo "${machine}" | tr '[:upper:]' '[:lower:]')
    if [[ "$machine_lower" == "linux" ]]; then
        < /dev/urandom tr -dc "$pwd_charset" | head -c "$pwd_length"
    else
        < /dev/urandom tr -dc "$pwd_charset" | cut -c1-"$pwd_length"
    fi
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
    cleaned_params=$(echo "$cleaned_params" | sed 's/,EXT_LDAP_SSL_SECRET_NAME//g' | sed 's/EXT_LDAP_SSL_SECRET_NAME,//g' | sed 's/EXT_LDAP_SSL_SECRET_NAME//g')
    cleaned_params=$(echo "$cleaned_params" | sed 's/,EXT_LDAP_SSL_CERT_FILE_FOLDER//g' | sed 's/EXT_LDAP_SSL_CERT_FILE_FOLDER,//g' | sed 's/EXT_LDAP_SSL_CERT_FILE_FOLDER//g')
    
    # Remove the old line
    sed -i '/^OPTIONAL_PARAMETERS:/d' "$TEMPORARY_PROPERTY_FILE"
    
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

# Empty values or {xor} are considered invalid.
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

        # Fail early if value is <Required>, {xor}
        if [[ "$value" == "<Required>" || "$value" == "{xor}" ]]; then
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

# This function is to patch the kafka strimzi podset for an upgrade to a version having Events Operator 5.2 or higher
# The function checks if events operator subscription is on channel 5.2 and if so gets the kafka strimzi podset and replaces an annotation which will allow the zen upgrade to complete
# The subscription for events operator is updated after the new CR is applied and the foundation-operator applies the new operand request, so this function is called during upgradeDeploymentStatus
# For https://jsw.ibm.com/browse/DBACLD-199163 https://jsw.ibm.com/browse/DBACLD-199093
function patch_strimzi_podset(){
    local operator_namespace=$1
    local services_namespace=$2

    echo "Checking ibm-events-operator subscription and channel..."
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
        kafka_podset_exists=$(${CLI_CMD} get strimzipodset iaf-system-kafka -n $services_namespace -o name --no-headers 2>/dev/null || echo "")

        if [[ -z "$kafka_podset_exists" ]]; then
            echo "StrimziPodSet 'iaf-system-kafka' not found"
            return
        fi

        echo "Found StrimziPodSet 'iaf-system-kafka'"

        # Get the current kafka version from the annotation - YQ 3.3 compatible syntax
        kafka_annotation_value=$(${CLI_CMD} get strimzipodset iaf-system-kafka -n $services_namespace -o yaml | ${YQ_CMD} read - "metadata.annotations[strimzi.io/kafka-version]" 2>/dev/null || echo "")

        if [[ -z "$kafka_annotation_value" || "$kafka_annotation_value" == "null" ]]; then
            strimzi_patched=true
            return
        fi

        echo "Current kafka version: $kafka_annotation_value"

        # Apply the patch directly
        echo "Applying patch to update annotations..."
        ${CLI_CMD} patch strimzipodset iaf-system-kafka -n $services_namespace --type=merge -p "{\"metadata\":{\"annotations\":{\"strimzi.io/kafka-version\":null,\"ibmevents.ibm.com/kafka-version\":\"$kafka_annotation_value\"}}}"

        echo "Successfully updated annotations:"
        echo "- Removed: strimzi.io/kafka-version"
        echo "- Added: ibmevents.ibm.com/kafka-version: $kafka_annotation_value"
        strimzi_patched=true
    else
        echo "Events operator is not at channel v5.2"
    fi
}
