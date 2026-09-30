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
        printf "Do you want to proceed with generating Gateway API templates required for a Business Automation Insights Standalone deployment on GKE? (Yes/No, default: No): \n"
        read -erp "" answer
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
# Function: generate_rancher_gateway_api_templates
# Description: Main entry point for generating Gateway API templates for
#              Rancher/Traefik. Handles user confirmation, prerequisite checks,
#              and orchestrates the Gateway API resource generation process.
# Parameters: None (uses global variables)
# Returns: Exits script after completion or user cancellation
###############################################################################
function generate_rancher_gateway_api_templates(){
    info "Generating Gateway API files required for a BAI Standalone deployment on Rancher/Traefik..."
    printf "\n"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding, make sure the ZenService CR is ready: kubectl get ZenService ${RESET_TEXT}"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Ensure Traefik v3 is installed and the kubernetesGateway provider is enabled${RESET_TEXT}"
    attempt=0

    while (( attempt < 3 )); do
        read -rp "Confirm if you want to proceed with generating Gateway API templates required for a BAI Standalone deployment on Rancher (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

        if [[ -z "$answer" || "$answer" == "no" || "$answer" = "n" ]]; then
            echo "Gateway API templates for a BAI Standalone deployment will not be created. Exiting the script.."
            exit
        elif [[ "$answer" == "yes" ||  "$answer" == "y" ]]; then
            info "Proceeding with the generation of Gateway API templates for a BAI Standalone deployment on Rancher"
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
    source $BAI_CNCF_FOLDER/bai-generate-gateway-api-rancher.sh
    rm -rf $GENERATED_API_GATEWAY_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_API_GATEWAY_FOLDER >/dev/null 2>&1
    bai_rancher_generate_gateway_api "$TARGET_PROJECT_NAME" "$GENERATED_API_GATEWAY_FOLDER/gateway-api-rancher.yaml"

    printf "\n"
    success "The Gateway API files have been created successfully at: ${GREEN_TEXT}$GENERATED_API_GATEWAY_FOLDER/${RESET_TEXT}"
    printf "\n"
    info "${YELLOW_TEXT}Next Steps:${RESET_TEXT}"
    echo "  1. Review the Gateway API manifest:"
    echo "     ${GREEN_TEXT}cat $GENERATED_API_GATEWAY_FOLDER/gateway-api-rancher.yaml${RESET_TEXT}"
    printf "\n"
    echo "  2. Apply the Gateway API resources:"
    echo "     ${GREEN_TEXT}kubectl apply -f $GENERATED_API_GATEWAY_FOLDER/gateway-api-rancher.yaml${RESET_TEXT}"
    printf "\n"
    echo "  3. Monitor Gateway provisioning:"
    echo "     ${GREEN_TEXT}kubectl get gateway bai-gateway -n $TARGET_PROJECT_NAME -w${RESET_TEXT}"
    printf "\n"
    echo "  4. Verify HTTPRoutes are attached (all should show Accepted=True, Resolved=True):"
    echo "     ${GREEN_TEXT}kubectl get httproute -n $TARGET_PROJECT_NAME${RESET_TEXT}"
    printf "\n"
    echo "  5. Configure DNS with the Gateway address"
    printf "\n"
    echo "  6. Verify Traefik is routing traffic:"
    echo "     ${GREEN_TEXT}kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=50${RESET_TEXT}"
    printf "\n"
    echo "  7. Delete the default zen-ingress to ensure everything works smoothly:"
    echo "     ${GREEN_TEXT}kubectl delete ingress zen-ingress -n $TARGET_PROJECT_NAME${RESET_TEXT}"
    printf "\n"
    exit
}


###############################################################################
# Function: generate_gateway_api_templates
# Description: Controller function that routes to platform-specific Gateway API
#              generation functions.
# Parameters: None
# Returns: Delegates to platform-specific function
###############################################################################
function generate_gateway_api_templates(){
    # If --platform was not supplied, prompt the user to choose
    if [[ -z "${GATEWAY_API_PLATFORM:-}" ]]; then
        local attempt=0
        while (( attempt < 3 )); do
            read -rp "Select the target platform for Gateway API generation [gke/rancher] (default: rancher): " GATEWAY_API_PLATFORM
            GATEWAY_API_PLATFORM=$(echo "${GATEWAY_API_PLATFORM:-rancher}" | tr '[:upper:]' '[:lower:]')
            if [[ "$GATEWAY_API_PLATFORM" == "gke" || "$GATEWAY_API_PLATFORM" == "rancher" ]]; then
                break
            else
                echo "Invalid input. Please enter 'gke' or 'rancher'."
                ((attempt++))
            fi
        done
        if (( attempt >= 3 )); then
            error "Maximum number of incorrect answers exceeded. Exiting..."
            exit 1
        fi
    fi

    if [[ "${GATEWAY_API_PLATFORM}" == "rancher" ]]; then
        generate_rancher_gateway_api_templates
    else
        generate_gke_gateway_api_templates
    fi
}