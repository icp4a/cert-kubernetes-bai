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
        printf "Confirm if you want to proceed with generating Gateway API templates required for a BAI Standalone deployment on Rancher (Yes/No, default: No): \n"
        read -erp "" answer
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
    generate_rancher_gateway_api_templates
}