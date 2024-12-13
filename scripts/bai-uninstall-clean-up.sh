#!/bin/bash
###############################################################################
#
# Licensed Materials - Property of IBM
# (C) Copyright IBM Corp. 2023. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################

# Import common utilities and environment variables
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
source ${CUR_DIR}/helper/common.sh

#Options
HELP="false"

while getopts 'n:s:h' OPTION; do
	case "$OPTION" in
	n)	BAI_NAMESPACE=$OPTARG
		;;
    s)  BAI_SERVICE_NAMESPACE=$OPTARG
        ;;
	h)
		HELP="true"
		;;
	?)
		HELP="true"
		;;
	esac
done
shift "$(($OPTIND - 1))"

if [[ $HELP == "true" ]]; then
	echo "This script cleans up resources that are stuck in terminating state or would cause failure in re-deployment."
	echo "Usage: $0 -h -n"
	echo "  -h  Display help"
	echo "  -n  Enter BAI namespace for clean up."
	exit 0
fi

# Check if OpenShift CLI is installed
if ! [ -x "$(command -v oc)" ]; then
  echo -e "\x1B[1;31mError: OpenShift CLI (oc) is not installed. Please install OpenShift CLI (oc) before running this script. \x1B[0m" >&2
  exit 1
fi

# Check if user is logged in to OCP cluster.
oc project > /dev/null 2>&1
if [ $? -gt 0 ]; then
  echo -e "\x1B[1;31mError: Not logged in to OCP cluster. Please login to an OCP cluster. \x1B[0m" && exit 1
fi

# BAI Namespace check
while [ -z "$BAI_NAMESPACE" ]; do
	printf "\x1B[1mEnter namespace of your BAI deployment: \x1B[0m"
	read -rp "" ans 
    BAI_NAMESPACE=$ans
    if [ -z "$(oc get project "${BAI_NAMESPACE}" 2>/dev/null)" ]; then
	    echo -e "\x1B[1;31mError: Namespace ${BAI_NAMESPACE} does not exist. Please re-enter the namespace.\x1B[0m"
        BAI_NAMESPACE=""
    fi
    echo
done

# Get Operand namespace from user
if [ -z "$BAI_SERVICE_NAMESPACE" ]; then
    # For https://jsw.ibm.com/browse/DBACLD-157622
    # Update the default answer for Seperation of Duties to No
    #fixes a potential scenario of no input passed to the next step
	max_retries=0
	while [ $max_retries -lt 4 ]; do
        printf "\x1B[1m\nDid you install BAI Standalone with Separation of Duties? (Yes/No, default: No) \x1B[0m"
        read -rp "" ans
        # If the user provides no input, set the default to 'No'
        if [ -z "$ans" ]; then
            ans="No"
        fi

        ans=$(echo "${ans}" | tr '[:upper:]' '[:lower:]')
        case "$ans" in
            "y"|"yes"|"")
                max_counter=0
				while [ $max_counter -lt 4 ]; do
                    printf "\x1B[1mEnter Operand namespace of your BAI deployment: \x1B[0m"
                    read -rp "" ans 
                    BAI_SERVICE_NAMESPACE=$ans
                    if [ -z "$(oc get project "${BAI_SERVICE_NAMESPACE}" 2>/dev/null)" ]; then
                        echo -e "\x1B[1;31mError: Namespace ${BAI_SERVICE_NAMESPACE} does not exist. Please re-enter the namespace.\x1B[0m"
                        BAI_SERVICE_NAMESPACE=""
                        max_counter=$(($max_counter + 1))
                    else
                        break
                    fi
                    echo
                done
                if [[ -z "$BAI_SERVICE_NAMESPACE" ]]; then
                    error "Maximum retries for incorrect inputs exceeded. The script will now exit.."
                    exit
                fi
                echo -e "\x1B[1mGetting Operator Namespace... \x1B[0m"
                BAI_NAMESPACE=$(oc get cm ibm-cp4ba-common-config -n $BAI_SERVICE_NAMESPACE --ignore-not-found -o jsonpath="{ .data.operators_namespace}")
                if [[ -z "$BAI_NAMESPACE" ]]; then
                    echo -e "\x1B[31;5mError: ibm-cp4ba-common-config ConfigMap not found in ${BAI_SERVICE_NAMESPACE} \x1B[0m\n"
                    exit 1
                fi
                break
            ;;
            "n"|"no")
                BAI_SERVICE_NAMESPACE=$BAI_NAMESPACE
                break
            ;;
            *)
            error "Answer must be 'Yes' or 'No'"
            max_retries=$(($max_retries + 1))
        esac
    done
    if [[ $max_retries == 4 ]]; then
		error "Maximum retries for incorrect inputs exceeded. The script will now exit.."
		exit
    fi
fi

# Validate BAI_NAMESPACE env var is for existing namespace
if [ -z "$(oc get project "${BAI_SERVICE_NAMESPACE}" 2>/dev/null)" ]; then
	echo -e "\x1B[1;31mError: Namespace ${BAI_SERVICE_NAMESPACE} does not exist. Specify an existing namespace where BAI is deployed.\x1B[0m" && exit 1
fi

# Check for namespace to prvent accidental deletion to other important namespaces.
if [[ "$BAI_SERVICE_NAMESPACE" == openshift* ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'openshift' or start with 'openshift'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == kube* ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'kube' or start with 'kube'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == "services" ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'services'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == "default" ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'default'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == "calico-system" ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'calico-system'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == "ibm-cert-store" ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'ibm-cert-store'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == "ibm-observe" ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'ibm-observe'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == "ibm-odf-validation-webhook" ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'default'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
elif [[ "$BAI_SERVICE_NAMESPACE" == "ibm-system" ]]; then
    echo -e "\x1B[1;31mThe current namespace should not be 'ibm-system'. It should be the namespace where BAI is installed. The script aborted. \x1B[0m"
    exit 1
fi

echo -e "The BAI namespace entered: ${BAI_SERVICE_NAMESPACE}"
if [[ "$BAI_SERVICE_NAMESPACE" != "$BAI_NAMESPACE" ]]; then
    echo -e "The BAI operator namespace is ${BAI_NAMESPACE}\n"
fi

# Check if user is logged in to OCP cluster.
oc project $BAI_SERVICE_NAMESPACE
if [ $? -gt 0 ]; then
  echo -e "\x1B[1;31mError: Not logged in to OCP cluster. Please login to an OCP cluster. \x1B[0m" && exit 1
fi
echo -e "\x1B[1mNote: Please make sure you are using the namespace you intent to clean up.\n\x1B[0m"
echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1;31mThis clean-up script is only intended to be run after you have deleted your InsightsEngine CR instance for your BAI deployment. This clean-up script will delete all Client CRs and zenExtensions, and some secrets that would cause failure in re-deployment. \x1B[0m\n"


# Confirm to clean up
echo -e "\x1B[1mPlease confirm if you would like to proceed with this clean up.\x1B[0m"
read -p "Enter Y or y to continue: " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\nYou did not confirm to proceed with this clean up. Exit clean-up script.\n"
    exit 0
  fi
  echo -e "You have confirmed to continue this clean up.\n"
  sleep 2

function delete_resource() {
	local RESOURCE_NAME=$1
	local NAMESPACE_NAME=$2
	oc get "${RESOURCE_NAME}" -n "${NAMESPACE_NAME}" --ignore-not-found=true &>/dev/null
	if [ $? -eq 0 ]; then
		for i in $(oc get "${RESOURCE_NAME}" --no-headers -n "${NAMESPACE_NAME}" --ignore-not-found=true | awk '{print $1}'); do
			oc patch "${RESOURCE_NAME}"/"$i" -n "${NAMESPACE_NAME}" -p '{"metadata":{"finalizers":[]}}' --type=merge
			oc delete "${RESOURCE_NAME}" "$i" -n "${NAMESPACE_NAME}" --ignore-not-found=true
		done
	fi
}

# Clean up clients
echo -e "\x1B[1mCleaning up Clients... \x1B[0m\n"
delete_resource client "${BAI_SERVICE_NAMESPACE}"
echo -e "\n\x1B[1mFinsished cleaning up all Clients. \x1B[0m\n"
# Clean up zenExtension
echo -e "\x1B[1mCleaning up zenExtensions... \x1B[0m\n"
delete_resource zenextension "${BAI_SERVICE_NAMESPACE}"
echo -e "\n\x1B[1mFinsihed cleaning up all zenExtensions. \x1B[0m\n"
# Clean up zen-metastore-edb secret
echo -e "\x1B[1mCleaning up zen-metastore-edb secrets... \x1B[0m\n"
for i in $(oc get secrets --no-headers|awk '{print $1}'| grep 'zen-metastore-edb'); do
    oc delete secret "$i" -n "$BAI_SERVICE_NAMESPACE"
done
echo -e "\n\x1B[1mFinsihed cleaning up all zen-metastore-edb related secrets. \x1B[0m\n"

# Clean up cs-ca-certificate secret
echo -e "\x1B[1mCleaning up cs-ca-certificate-secret secret... \x1B[0m\n"
oc delete secret cs-ca-certificate-secret -n "$BAI_SERVICE_NAMESPACE"
echo -e "\n\x1B[1mFinsihed cleaning up cs-ca-certificate-secret secret. \x1B[0m\n"

# delete FlinkDeployment CR
echo "Deleting FlinkDeployment CR"
delete_resource FlinkDeployment $BAI_SERVICE_NAMESPACE
# <https://jsw.ibm.com/browse/DBACLD-156830?> - Need to add a full name for flinkdeployments, as there could be another flinkdeployment CRD
delete_resource flinkdeployments.flink.ibm.com $BAI_SERVICE_NAMESPACE
delete_resource flinkdeployments.flink.apache.org $BAI_SERVICE_NAMESPACE

# delete FlinkSessionJobs
echo "Deleting FlinkSessionJobs"
delete_resource FlinkSessionJobs $BAI_SERVICE_NAMESPACE

# delete Flink operator certificate
oc patch secret/flink-operator-cert -p '{"metadata":{"finalizers":[]}}' --type=merge -n $BAI_SERVICE_NAMESPACE
echo "Deleting secret "
oc delete secret flink-operator-cert -n $BAI_SERVICE_NAMESPACE --ignore-not-found=true --wait=true 
if [[ "$BAI_SERVICE_NAMESPACE" != "$BAI_NAMESPACE" ]]; then
    oc patch secret/flink-operator-cert -p '{"metadata":{"finalizers":[]}}' --type=merge -n $BAI_NAMESPACE
    oc delete secret flink-operator-cert -n $BAI_NAMESPACE --ignore-not-found=true --wait=true 
fi

# delete common service
delete_resource CommonService ${BAI_SERVICE_NAMESPACE}
delete_resource CommonService ${BAI_NAMESPACE}

echo -e "\x1B[1m \nBAI clean up has completed.\x1B[0m\n"