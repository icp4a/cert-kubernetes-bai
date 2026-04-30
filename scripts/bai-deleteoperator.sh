#!/bin/bash
#set -x
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
# CUR_DIR set to full path to scripts folder
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TEMP_FOLDER=${CUR_DIR}/.tmp
# Define the path to the OLM subscription YAML file
OLM_SUBSCRIPTION=${PARENT_DIR}/descriptors/op-olm/subscription.yaml
OLM_SUBSCRIPTION_TMP=${TEMP_FOLDER}/.subscription.yaml

# Function to determine the uninstall type based on the presence of an OLM subscription
function select_uninstall_type(){
    local returnValue
    # Check whether the subscription exists in the specified namespace.
    ${CLI_CMD} get subscription.operators.coreos.com -n $NAMESPACE | grep ibm-bai-operator-catalog-subscription >&3 2>&3
    returnValue=$?
    if [ "$returnValue" == 0 ] ; then
        # If the subscription exists, call the OLM-based uninstall function
        uninstall_olm_bai
    elif [ "$returnValue" == 1 ] ; then
        # If no subscription is found, call uninstall_bai
        uninstall_bai
    fi
}

# Function to uninstall Non-OLM-based BAI operator
function uninstall_bai(){
    printf "\n"
    printf "\x1B[1mUninstall BAI Operator...\n\x1B[0m"
    ${CLI_CMD} delete -f ${CUR_DIR}/../descriptors/operator.yaml -n $NAMESPACE >&3 2>&3
    ${CLI_CMD} delete -f ${CUR_DIR}/../descriptors/role_binding.yaml -n $NAMESPACE >&3 2>&3
    ${CLI_CMD} delete -f ${CUR_DIR}/../descriptors/role.yaml -n $NAMESPACE >&3 2>&3
    ${CLI_CMD} delete -f ${CUR_DIR}/../descriptors/service_account.yaml -n $NAMESPACE >&3 2>&3
    echo "All descriptors have been successfully deleted."
}

# Function to uninstall an OLM-based BAI operator
function uninstall_olm_bai(){
    printf "\n\x1B[1mUninstall BAI Operator Subscription...\n\x1B[0m"

    # Function to delete a subscription and its associated CSV
    function delete_subscription_and_csv() {
        local subName=$1
        local csvName
        # Get the CSV name from the subscription
        csvName=$(${CLI_CMD} get subscription.operators.coreos.com "$subName" -n $NAMESPACE -o=jsonpath='{.status.installedCSV}')
        
        # Remove the subscription
        echo "Removing the subscription for $subName"
        ${CLI_CMD} delete subscription "$subName" -n $NAMESPACE
        if [[ $? -eq 0 ]]; then
            echo "Subscription deletion successful."
        else
            echo "Subscription deletion failed."
        fi

        # Remove the CSV 
        echo "Removing the CSV for $csvName"
        ${CLI_CMD} delete clusterserviceversion "$csvName" -n $NAMESPACE
        if [[ $? -eq 0 ]]; then
            echo "CSV deletion successful."
        else
            echo "CSV deletion failed."
        fi
    }

    ${CLI_CMD} get subscription.operators.coreos.com -n $NAMESPACE -o=jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.source}{"\n"}{end}' | while read -r line; do
        subName=$(echo "$line" | awk '{print $1}')
        source=$(echo "$line" | awk '{print $2}')
        echo "***********************************"
        echo "[DEBUG] Checking subscription: $subName with source: $source"
        if [[ "$source" == "ibm-bai-operator-catalog" ]]; then
            delete_subscription_and_csv "$subName"
        fi
    done
}

# Function to display help information
function show_help {
    printf '%b\n' "\nPrerequisite:"
    printf '%b\n' "1. Login to your cluster;"
    printf '%b\n' "2. The CR was applied in your project."
    printf '%b\n' "Usage: deleteOperator.sh -n <namespace>\n"
    echo "Options:"
    echo "  -h  Display help"
    echo "  -n  The namespace where the BAI Operator is installed"
}

# Check if any arguments were passed; if not, display help and exit
if [[ -z "$1" ]]; then
    show_help
    exit 1
else
    while getopts "h?n:" opt; do
        case "$opt" in
        h|\?)
            show_help
            exit 0
            ;;
        n) NAMESPACE=$OPTARG
            ;;
        :)  echo "Invalid option: -$OPTARG requires an argument"
            show_help
            exit 1
            ;;
        esac
    done
fi

mkdir -p $TEMP_FOLDER >&3 2>&3
source ${CUR_DIR}/helper/common.sh
select_uninstall_type
rm -rf ${TEMP_FOLDER} >&3 2>&3
