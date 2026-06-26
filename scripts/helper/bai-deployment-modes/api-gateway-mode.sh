#!/bin/bash
# set -x
###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2026. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################

###############################################################################
# Function: generate_gke_gateway_api_templates
# Description: Main entry point for generating Gateway API templates for GKE.
#              This function handles user confirmation, prerequisite checks,
#              and orchestrates the Gateway API resource generation process.
# Parameters: None (uses global variables)
# Returns: Exits script after completion or user cancellation
###############################################################################
function generate_gke_gateway_api_templates(){
    # Display initial information and prerequisites
    info "Generating Gateway API files required for a BAI Standalone deployment on GKE..."
    printf "\n"
    
    # Show important prerequisites that must be verified before proceeding
    echo "${RED_TEXT}[IMPORTANT]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the Gateway API generation, please verify the following prerequisites:${RESET_TEXT}"
    echo
    echo "  ${BOLD_TEXT}1. ZenService Readiness${RESET_TEXT}"
    echo "     Ensure that the ZenService is in a ready state before generating Gateway API templates."
    echo
    msgB "     To check ZenService status and progress manually:"
    echo "       ${CLI_CMD} get zenService \$(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME | awk '{print \$1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.zenStatus}'"
    echo "       ${CLI_CMD} get zenService \$(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME | awk '{print \$1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.progress}'"
    echo
    echo "  ${BOLD_TEXT}2. Gateway API Enablement${RESET_TEXT}"
    echo "     Verify that Gateway API is enabled on your GKE cluster."
    echo
    
    # Initialize attempt counter for user confirmation loop
    attempt=0

    # Prompt user for confirmation with retry logic (max 3 attempts)
   while (( attempt < 3 )); do
        read -rp "Do you want to proceed with generating Gateway API templates required for a Business Automation Insights Standalone deployment on GKE? (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase for case-insensitive comparison

        # Use case statement for cleaner pattern matching
        case "$answer" in
            ""|"no"|"n")
                # User declined or pressed Enter (default is No)
                echo "Gateway API templates for a Business Automation Insights Standalone deployment will not be created."
                exit
                ;;
            "yes"|"y")
                # User confirmed, proceed with generation
                info "Proceeding with the generation of Gateway API templates for a Business Automation Insights Standalone deployment on GKE."
                break
                ;;
            *)
                # Invalid input, increment attempt counter
                echo "Invalid input. Please enter 'yes' or 'no'."
                ;;
        esac

        ((attempt++))
    done

    # Check if maximum attempts exceeded
    if [[ "$attempt" == 3 ]]; then
        error "Maximum number of incorrect answers exceeded. Exiting..."
        exit
    fi

    # Source required utility scripts for Gateway API generation
    source $BAI_CNCF_FOLDER/bai-utils.sh
    source $BAI_CNCF_FOLDER/bai-generate-api-gateway-resources-gke.sh
    
    # Clean up and prepare output directory
    rm -rf $GENERATED_API_GATEWAY_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_API_GATEWAY_FOLDER >/dev/null 2>&1
    
    # Call the main Gateway API generation function
    # This function handles all the heavy lifting including:
    # - Checking prerequisites (ZenService, GatewayClass, etc.)
    # - Patching services for HTTPS backend protocol
    # - Generating Gateway API manifests
    # - Creating service patch scripts
    # - Displaying comprehensive next steps
    bai_gke_generate_gateway_api "$TARGET_PROJECT_NAME" "$GENERATED_API_GATEWAY_FOLDER/gke-api-gateway-configurations.yaml"
    
    # Exit successfully after generation completes
    exit 0
}




###############################################################################
# Function: generate_gateway_api_templates
# Description: Controller function that routes to platform-specific Gateway API
#              generation functions. Currently only supports GKE, but designed
#              to be extensible for other cloud platforms in the future.
# Parameters: None
# Returns: Delegates to platform-specific function
###############################################################################
function generate_gateway_api_templates(){
    # Currently only GKE is supported, but this structure allows for easy
    # addition of other platforms (e.g., AWS, Azure) in the future
    generate_gke_gateway_api_templates
}