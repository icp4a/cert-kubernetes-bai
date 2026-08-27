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


current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

###############################################################################
# GKE-specific Gateway API generation script for Business Automation Insights
# Standalone deployment. This script generates Gateway API resources using the
# GKE Gateway controller (gke-l7-global-external-managed).
###############################################################################

###############################################################################
# Function: check_prereqs_for_gke_gateway
# Description: Validates all prerequisites required for Gateway API generation
#              including cluster configuration, InsightsEngine CR settings,
#              GatewayClass availability, and TLS issuer presence.
# Parameters:
#   $1 - namespace: The BAI deployment namespace
# Global Variables Set:
#   - licensing_namespace: Namespace where IBM licensing is deployed
#   - cp_console_hostname: Hostname for the CP console
#   - domain_name: Domain name for the deployment
#   - GATEWAY_CLASS_NAME: Name of the GatewayClass to use
# Returns: Exits with error if prerequisites are not met
###############################################################################
function check_prereqs_for_gke_gateway() {
    local namespace=$1
    info "Checking prerequisites for GKE Gateway API generation..."

    # Detect licensing namespace from subscription
    licensing_namespace=$(${CLI_CMD} get sub -A 2>/dev/null | grep ibm-licensing-operator-app | cut -d ' ' -f1)
    # Use default if licensing namespace not found
    if [[ -z ${licensing_namespace} ]]; then
        licensing_namespace="ibm-licensing"
        warning "Could not detect licensing namespace, using default: ibm-licensing"
    fi

    # Retrieve cluster hostname from ConfigMap
    cp_console_hostname=$(${CLI_CMD} get cm ibmcloud-cluster-info -n ${namespace} -o jsonpath='{.data.cluster_address}' 2>/dev/null)
    if [[ -z ${cp_console_hostname} ]]; then
        error "Cannot find cluster_address value in ibmcloud-cluster-info config map in namespace ${namespace}. Check that Business Automation Insights is installed under ${namespace}."
        exit 1
    fi

    # Retrieve domain name from ConfigMap
    domain_name=$(${CLI_CMD} get cm ibm-cpp-config -n ${namespace} -o jsonpath='{.data.domain_name}' 2>/dev/null)
    if [[ -z ${domain_name} ]]; then
        error "Cannot find domain_name value in ibm-cpp-config config map in namespace ${namespace}. Check that Business Automation Insights is installed under ${namespace}."
        exit 1
    fi

    # Validate InsightsEngine CR sc_ingress_type setting
    # This setting determines how services are exposed (loadbalancer is recommended for Gateway API)
    echo ""
    info "Checking InsightsEngine CR configuration..."
    sc_ingress_type=$(${CLI_CMD} get insightsengine -n ${namespace} -o jsonpath='{.items[0].spec.shared_configuration.sc_ingress_type}' 2>/dev/null)
    if [[ -n "$sc_ingress_type" ]]; then
        if [[ "$sc_ingress_type" == "loadbalancer" ]]; then
            success "InsightsEngine CR has sc_ingress_type set to: ${sc_ingress_type}"
        else
            warning "InsightsEngine CR sc_ingress_type is set to: ${sc_ingress_type}"
            echo ""
            echo "Recommended setting for Gateway API:"
            echo "  sc_ingress_type: loadbalancer"
            echo ""
        fi
    else
        warning "InsightsEngine CR does not have sc_ingress_type set"
        echo ""
        echo "${YELLOW_TEXT}IMPORTANT:${RESET_TEXT} Update your InsightsEngine CR with:"
        echo ""
        echo "  spec:"
        echo "    shared_configuration:"
        echo "      sc_ingress_type: loadbalancer"
        echo ""
        echo "${YELLOW_TEXT}NOTE:${RESET_TEXT} If you are planning to use NGINX for Kafka, you can remove sc_ingress_type: loadbalancer"
        echo ""
        read -rp "Do you want to continue anyway? (yes/no, default: no): " continue_anyway
        continue_anyway=$(echo "$continue_anyway" | tr '[:upper:]' '[:lower:]')

        case "$continue_anyway" in
            "yes"|"y")
                # Continue with the script
                ;;
            *)
                error "Exiting. Please configure sc_ingress_type in your ICP4ACluster CR first."
                exit 1
                ;;
        esac
    fi

    # Prompt for GatewayClass name
    echo ""
    info "Configuring Gateway API GatewayClass..."
    echo ""
    echo "Available GatewayClasses in your cluster:"
    ${CLI_CMD} get gatewayclass -o custom-columns=NAME:.metadata.name,CONTROLLER:.spec.controllerName --no-headers 2>/dev/null || echo "  (none found)"
    echo ""
    read -rp "Enter the GatewayClass name to use: " gateway_class_input
    if [[ -z "$gateway_class_input" ]]; then
        error "GatewayClass name is required"
        exit 1
    fi
    GATEWAY_CLASS_NAME="${gateway_class_input}"

    # Verify the GatewayClass exists
    if ! ${CLI_CMD} get gatewayclass "${GATEWAY_CLASS_NAME}" >/dev/null 2>&1; then
        warning "GatewayClass '${GATEWAY_CLASS_NAME}' not found in the cluster."
        echo ""
        echo "To enable Gateway API on GKE with gke-l7-global-external-managed, run:"
        echo ""
        echo "  gcloud container clusters update <CLUSTER_NAME> --region <REGION> --gateway-api=standard"
        echo ""
        read -rp "Do you want to continue anyway? (yes/no, default: no): " continue_anyway
        continue_anyway=$(echo "$continue_anyway" | tr '[:upper:]' '[:lower:]')
        case "$continue_anyway" in
            "yes"|"y")
                # Continue with the script
                ;;
            *)
                error "Exiting. Please configure sc_ingress_type in your ICP4ACluster CR first."
                exit 1
                ;;
        esac
    else
        success "GatewayClass '${GATEWAY_CLASS_NAME}' found and will be used."
    fi

    

    # Check for zen-tls-issuer
    if ! ${CLI_CMD} get issuer zen-tls-issuer -n ${namespace} >/dev/null 2>&1; then
        warning "zen-tls-issuer not found in namespace ${namespace}."
        echo "This issuer is typically created by the Business Automation Insights Standalone deployment."
        echo ""
    fi
}

function get_client_id_gke_gateway() {
    local namespace=$1
    client_id=$(${CLI_CMD} get secret ibm-iam-bindinfo-platform-oidc-credentials -n ${namespace} -o jsonpath='{.data.WLP_CLIENT_ID}' 2>/dev/null | base64 --decode)
    if [[ -z ${client_id} ]]; then
        error "Cannot retrieve client_ID from ibm-iam-bindinfo-platform-oidc-credential secret. Check if the Business Automation Insights Standalone Custom Resource file has the status marked as ready."
        exit 1
    fi
}

function patch_services_for_https() {
    local namespace=$1
    info "Patching services to add appProtocol: HTTPS..."
    echo ""

    # Patch auth services
    ${CLI_CMD} patch svc platform-auth-service -n ${namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true

    ${CLI_CMD} patch svc platform-identity-provider -n ${namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true

    ${CLI_CMD} patch svc platform-identity-management -n ${namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true

    ${CLI_CMD} patch svc ibm-nginx-svc -n ${namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true

    # Patch licensing service
    ${CLI_CMD} patch svc ibm-licensing-service-instance -n ${licensing_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true

    # Add NEG annotations to all services
    ${CLI_CMD} annotate service platform-auth-service -n ${namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true

    ${CLI_CMD} annotate service platform-identity-provider -n ${namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true

    ${CLI_CMD} annotate service platform-identity-management -n ${namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true

    ${CLI_CMD} annotate service ibm-nginx-svc -n ${namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true

    ${CLI_CMD} annotate service ibm-licensing-service-instance -n ${licensing_namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true

    # Handle OpenSearch if included
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        info "Adding NEG annotation to OpenSearch service..."
        ${CLI_CMD} annotate service opensearch -n ${namespace} \
          cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || tru

        # Verify if appProtocol is set
        opensearch_app_protocol=$(${CLI_CMD} get svc opensearch -n ${namespace} -o jsonpath='{.spec.ports[1].appProtocol}' 2>/dev/null)
        if [[ "$opensearch_app_protocol" == "HTTPS" ]]; then
            success "OpenSearch service already has appProtocol: HTTPS on port 9200"
        else
            warning "OpenSearch service does NOT have appProtocol: HTTPS on port 9200"
            echo "Please verify that the flag sc_ingress_type has been set correctly in the InsightsEngine Custom Resource File."
            echo "If your OpenSearch operator doesn't support spec.patches, you may need a sidecar service."
            echo ""
        fi
    fi

    success "Services patched with appProtocol: HTTPS and NEG annotations"
}

function replace_gke_gateway() {
    local namespace=$1
    if [[ -z ${output_file} ]]; then
        output_file=$(mktemp)
    fi

    info "Writing the GKE Gateway API manifests to ${output_file}"

    # Select the appropriate template based on optional components
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        template_file="bai-api-gateway-template-for-gke.yaml"
    else
        template_file="gateway_api_template_gke_base.yaml"
    fi

    cp "${current_dir}/${template_file}" ${output_file}

    # Basic replacements using | as delimiter to avoid issues with / in values
    ${SED_COMMAND} "s|NAMESPACE|${namespace}|g" ${output_file}
    ${SED_COMMAND} "s|HOST|${cp_console_hostname}|g" ${output_file}
    ${SED_COMMAND} "s|DOMAIN|${domain_name}|g" ${output_file}
    ${SED_COMMAND} "s|CLIENT_ID|${client_id}|g" ${output_file}
    ${SED_COMMAND} "s|LICENSING_NS|${licensing_namespace}|g" ${output_file}
    ${SED_COMMAND} "s|GATEWAY_CLASS|${GATEWAY_CLASS_NAME}|g" ${output_file}

    # Note: GATEWAY_IP_NAME placeholder will be replaced by user or left as-is for manual update

    # Workaround for Mac sed creating extra files
    if [[ -f "$output_file\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
}

function bai_gke_generate_gateway_api() {
    local bai_namespace=$1
    local output_file=$2

    # GKE-specific variables
    INCLUDE_OPENSEARCH="true"
    INCLUDE_KAFKA="true"
    GATEWAY_CLASS_NAME=""

    # Set output directory
    output_dir=$(dirname "${output_file}")

    # Check prerequisites
    check_prereqs_for_gke_gateway $bai_namespace

    # Get client ID
    get_client_id_gke_gateway $bai_namespace

    # Patch services
    echo ""
    info "Patching services for HTTPS backend protocol..."
    patch_services_for_https $bai_namespace

    # Generate Gateway API manifest
    echo ""
    info "Generating GKE Gateway API manifest..."
    replace_gke_gateway $bai_namespace


    # Summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "GKE Gateway API resources generated successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Generated files:"
    echo "  1. ${output_file}"
    echo ""


    echo "Next steps:"
    echo ""
    echo "1. Reserve a static IP in GCP:"
    echo "   ${GREEN_TEXT}gcloud compute addresses create <IP_NAME> --global --ip-version IPV4${RESET_TEXT}"
    echo ""
    echo "2. Update the Gateway manifest:"
    echo "   - Replace ${YELLOW_TEXT}GATEWAY_IP_NAME${RESET_TEXT} with your static IP name"
    echo "   - File: ${output_file}"
    echo ""
    echo ""
    echo "3. Apply the Gateway API manifest:"
    echo "   ${GREEN_TEXT}kubectl apply -f ${output_file}${RESET_TEXT}"
    echo ""
    echo "4. Wait for Gateway provisioning (2-5 minutes):"
    echo "   ${GREEN_TEXT}kubectl get gateway bai-gateway -n ${bai_namespace} -w${RESET_TEXT}"
    echo ""
    echo "5. Get the Gateway IP:"
    echo "   ${GREEN_TEXT}gcloud compute addresses describe <IP_NAME> --global --format=\"value(address)\"${RESET_TEXT}"
    echo ""
    echo "6. Configure DNS to point to the Gateway IP:"
    echo "   - ${cp_console_hostname} → <GATEWAY_IP>"
    echo "   - licensing.${domain_name} → <GATEWAY_IP>"
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        echo "   - opensearch-${bai_namespace}.${domain_name} → <GATEWAY_IP>"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}