#!/bin/bash
# set -x
###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2025. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################


# This file is a helper script used to store all functions that are used by the bai-deployment.sh when the ingress flag is passed
# Example : bai-deployment.sh --ingress -n <bai-namespace>

#### Start - Functions being called by the generate_ingress_templates function ####

# function used to generate the ingress templates for rancher
function generate_cncf_ingress_templates(){
    local tls_enable="$1"
    info "Generating Ingress files required for a BAI Standalone deployment..."
    printf "\n"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the ingress generation, make sure the BAI Standalone components have been installed by looking at the status section of the InsightsEngine Custom Resource file and monitoring the Insights Engine Operator logs ${RESET_TEXT}"
    attempt=0

    while (( attempt < 3 )); do
        read -rp "Confirm if you want to proceed with generating ingress templates required for a BAI Standalone deployment (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

        if [[ -z "$answer" || "$answer" == "no" || "$answer" = "n" ]]; then
            echo "Ingress templates for a BAI Standalone deployment will not be created. Exiting the script.."
            exit
        elif [[ "$answer" == "yes" ||  "$answer" == "y" ]]; then
            info "Proceeding with the generation of Ingress templates for a BAI Standalone deployment"
            break
        else
            echo "Invalid input. Please enter 'yes' or 'no'."
        fi

        ((attempt++))
    done
    if [[ "$attempt" == 3 ]]; then
        error "maximum number of incorrect answers exceeded, exiting..."
        exit
    fi
    source $BAI_CNCF_FOLDER/bai-utils.sh
    source $BAI_CNCF_FOLDER/bai-generate-ingress.sh
    rm -rf $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    bai_cncf_generate_ingress "$TARGET_PROJECT_NAME" "$GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml" "$tls_enable"
    success "The ingress file has been created successfully. After reviewing the file, apply the yaml file using the command ${GREEN_TEXT}\"${CLI_CMD} apply -f $GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml\"${RESET_TEXT}"
    exit
}

#### END - Functions being called by the generate_ingress_templates function ####

# The main function that calls the platform specific ingress generation function
function generate_ingress_templates(){
    tls_enable=$1
    generate_cncf_ingress_templates "$tls_enable"
}