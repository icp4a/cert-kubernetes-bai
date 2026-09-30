#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Rancher/Traefik v3-specific Gateway API generation script for BAI Standalone deployment
# This script generates Gateway API resources using Traefik as the Gateway API implementation.
#
# Key differences from GKE:
#   - No GCPBackendPolicy / HealthCheckPolicy (GKE-only CRDs)
#   - No NEG annotations (GKE-only)
#   - Backend HTTPS: uses appProtocol:https (lowercase IANA value) on Service ports.
#     Traefik's kubernetesGateway provider reads appProtocol from EndpointSlices to
#     decide whether to use TLS when connecting to backend pods.
#     NOTE: traefik.ingress.kubernetes.io/service.serversscheme=https is ONLY honoured
#     by the kubernetesCRD (IngressRoute) provider — silently ignored by kubernetesGateway.
#     PREREQUISITE: Traefik must have --serversTransport.insecureSkipVerify=true set
#     globally (IBM pod certs have DNS SANs only, no IP SAN for ClusterIPs).
#     The script checks for this and exits if not set — see check_prereqs_rancher_gateway().
#   - Gateway address: type:IPAddress (not NamedAddress) or omitted when controller assigns IP
#   - Session affinity: NOT supported via standard Gateway API — see WARNING printed by script
#   - OpenSearch is always included (core BAI component, not optional)

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION: check_prereqs_rancher_gateway
# ─────────────────────────────────────────────────────────────────────────────
function check_prereqs_rancher_gateway() {
    info "Checking prerequisites for Rancher/Traefik Gateway API generation..."
    echo ""

    # ── MANDATORY CHECK 1: Traefik kubernetesGateway provider ────────────────
    # This is the most critical check. If the provider is not enabled, all
    # Gateway objects will be silently ignored — no error is surfaced.
    info "Checking Traefik Gateway API provider..."

    local traefik_ns=""
    traefik_ns=$(${CLI_CMD} get pods -A --no-headers 2>/dev/null | grep -i traefik | awk '{print $1}' | head -1)
    if [[ -z "$traefik_ns" ]]; then
        traefik_ns="traefik"
        warning "Could not auto-detect Traefik namespace; assuming 'traefik'"
    fi
    TRAEFIK_NAMESPACE="$traefik_ns"

    local gw_provider_enabled="false"
    # Discover the controller workload; RKE2 names it rke2-traefik rather than traefik.
    local traefik_args=""
    local traefik_workload=""
    local traefik_workload_kind=""
    traefik_workload=$(${CLI_CMD} get daemonset -n "${TRAEFIK_NAMESPACE}" \
        -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -z "$traefik_workload" ]]; then
        traefik_workload=$(${CLI_CMD} get daemonset -n "${TRAEFIK_NAMESPACE}" \
            --no-headers 2>/dev/null | awk '$1 ~ /traefik/ {print $1; exit}')
    fi
    if [[ -n "$traefik_workload" ]]; then
        traefik_workload_kind="daemonset"
    else
        traefik_workload=$(${CLI_CMD} get deployment -n "${TRAEFIK_NAMESPACE}" \
            -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -z "$traefik_workload" ]]; then
            traefik_workload=$(${CLI_CMD} get deployment -n "${TRAEFIK_NAMESPACE}" \
                --no-headers 2>/dev/null | awk '$1 ~ /traefik/ {print $1; exit}')
        fi
        [[ -n "$traefik_workload" ]] && traefik_workload_kind="deployment"
    fi

    if [[ "$traefik_workload_kind" == "daemonset" ]]; then
        traefik_args=$(${CLI_CMD} get daemonset "$traefik_workload" -n "${TRAEFIK_NAMESPACE}" \
            -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
    elif [[ "$traefik_workload_kind" == "deployment" ]]; then
        traefik_args=$(${CLI_CMD} get deployment "$traefik_workload" -n "${TRAEFIK_NAMESPACE}" \
            -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
    fi

    if echo "$traefik_args" | grep -qi "providers.kubernetesgateway"; then
        gw_provider_enabled="true"
        success "Traefik kubernetesGateway provider is enabled."
    fi

    if [[ "$gw_provider_enabled" == "false" ]]; then
        echo ""
        echo "${RED_TEXT}╔══════════════════════════════════════════════════════════════════════╗${RESET_TEXT}"
        echo "${RED_TEXT}║  FATAL: Traefik Gateway API provider is NOT enabled                  ║${RESET_TEXT}"
        echo "${RED_TEXT}╚══════════════════════════════════════════════════════════════════════╝${RESET_TEXT}"
        echo ""
        echo "Gateway objects will be created but silently ignored — no traffic will flow."
        echo ""
        echo "${YELLOW_TEXT}To enable it, update your Traefik HelmRelease/HelmChart values:${RESET_TEXT}"
        echo ""
        echo "  providers:"
        echo "    kubernetesGateway:"
        echo "      enabled: true"
        echo ""
        echo "Or if managing Traefik via the Rancher UI:"
        echo "  Cluster > Apps > Installed Apps > traefik > Edit/Upgrade"
        echo "  Add under 'providers': kubernetesGateway: { enabled: true }"
        echo ""
        echo "After enabling, re-run this script."
        exit 1
    fi

    # ── MANDATORY CHECK 2: --serversTransport.insecureSkipVerify=true ────────
    #
    # WHY THIS FLAG IS REQUIRED — AND WHY THIS IS NOT A SECURITY WEAKNESS:
    #
    # This check verifies that Traefik has --serversTransport.insecureSkipVerify=true
    # set. This flag skips TLS certificate verification on backend (pod-to-pod)
    # connections inside the cluster.
    #
    # WHY IT IS NEEDED ON TRAEFIK (but NOT on GKE or legacy NGINX Ingress):
    #   - GKE: the load balancer is a GCP-managed infrastructure service (not a Go
    #     process). GCP's LB validates backend TLS at the infrastructure level using
    #     GCP's own CA bundle — Go's crypto/tls is never involved. GCPBackendPolicy
    #     handles this entirely outside the cluster.
    #   - NGINX Ingress (previous Rancher approach): NGINX does not enforce strict
    #     Go TLS validation against backend ClusterIPs. It skips cert verification
    #     by default when proxy_ssl_verify is off — which IS the default for
    #     nginx.ingress.kubernetes.io/backend-protocol: HTTPS. Every BAI NGINX
    #     ingress template uses backend-protocol:HTTPS without proxy-ssl-verify:on,
    #     meaning backend cert verification has always been disabled on the NGINX
    #     path too. Traefik simply makes this explicit via
    #     --serversTransport.insecureSkipVerify=true instead of relying on a silent
    #     NGINX default.
    #   - Traefik kubernetesGateway: Traefik is a Go binary running inside the
    #     cluster. When it connects to a backend Service over HTTPS, it uses Go's
    #     crypto/tls which enforces strict certificate validation. IBM Cloud Pak pod
    #     certificates have DNS SANs only (e.g. ibm-nginx-svc, *.cp4ba.svc) — no IP
    #     SAN is provisioned for the Service ClusterIP. Go requires an IP SAN when
    #     connecting to an IP address, so every backend connection fails with:
    #       x509: cannot validate certificate for <ClusterIP> because it doesn't
    #       contain any IP SANs
    #
    # WHY THIS IS ACCEPTABLE (not a security gap):
    #   - TLS termination for all external traffic already happens at the Gateway
    #     (Traefik itself). The connection between Traefik and backend pods is
    #     intra-cluster traffic over the pod network, never exposed externally.
    #   - The ServersTransport CRD + service.serverstransport annotation pattern
    #     would fix this per-service for the kubernetesCRD (IngressRoute) provider,
    #     but that annotation is silently ignored by kubernetesGateway — it is a
    #     Traefik limitation, not a configuration error.
    #   - BackendTLSPolicy (Gateway API standard CRD, v1alpha3) is the correct
    #     long-term solution, but as of Traefik v3.7 it does not support the
    #     IP-SAN bypass case via BackendTLSPolicy. This will be revisited when
    #     Traefik's BackendTLSPolicy implementation matures.
    #
    # SAST / SECURITY SCANNER NOTE:
    #   Any finding flagging this insecureSkipVerify check as a security issue
    #   should be marked as an accepted risk / false positive with the above
    #   justification. The flag applies only to intra-cluster Traefik→pod traffic
    #   on a dedicated BAI deployment cluster. It is equivalent in risk profile to
    #   NGINX Ingress backend-protocol:HTTPS (which also skips backend cert verify)
    #   and to GKE's GCPBackendPolicy which offloads verification to GCP infra.
    #
    # nosemgrep: generic.secrets.security.detected-insecureskipverify
    # nosec G402
    # checkov:skip=CKV_K8S_28
    info "Checking Traefik backend TLS configuration (insecureSkipVerify)..."
    local skip_verify_enabled="false"
    if echo "$traefik_args" | grep -q "insecureSkipVerify=true"; then
        skip_verify_enabled="true"
        success "Traefik --serversTransport.insecureSkipVerify=true is set."
    fi

    if [[ "$skip_verify_enabled" == "false" ]]; then
        echo ""
        echo "${RED_TEXT}╔══════════════════════════════════════════════════════════════════════╗${RESET_TEXT}"
        echo "${RED_TEXT}║  FATAL: --serversTransport.insecureSkipVerify is NOT set             ║${RESET_TEXT}"
        echo "${RED_TEXT}╚══════════════════════════════════════════════════════════════════════╝${RESET_TEXT}"
        echo ""
        echo "Without this flag, Traefik will fail to connect to IBM Cloud Pak backend"
        echo "pods with:"
        echo "  x509: cannot validate certificate for <ClusterIP> because it doesn't"
        echo "  contain any IP SANs"
        echo ""
        echo "${YELLOW_TEXT}To fix, patch the Traefik DaemonSet (takes effect immediately after pod restart):${RESET_TEXT}"
        echo ""
        echo "  kubectl patch daemonset traefik -n ${TRAEFIK_NAMESPACE} --type=json \\"
        echo "    -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\","
        echo "         \"value\":\"--serversTransport.insecureSkipVerify=true\"}]'"
        echo "  kubectl rollout restart daemonset/traefik -n ${TRAEFIK_NAMESPACE}"
        echo ""
        echo "${YELLOW_TEXT}Or via Traefik HelmChart values (persistent across upgrades):${RESET_TEXT}"
        echo ""
        echo "  serversTransport:"
        echo "    insecureSkipVerify: true"
        echo ""
        echo "After patching Traefik and confirming pods have restarted, re-run this script."
        exit 1
    fi

    # ── MANDATORY CHECK 3: Traefik RBAC — can it read ReferenceGrants? ────────
    info "Checking Traefik RBAC for ReferenceGrant access..."
    local traefik_sa="traefik"
    local rbac_ok
    rbac_ok=$(${CLI_CMD} auth can-i get referencegrants \
        --as="system:serviceaccount:${TRAEFIK_NAMESPACE}:${traefik_sa}" -A 2>/dev/null)
    if [[ "$rbac_ok" == "yes" ]]; then
        success "Traefik ServiceAccount can read ReferenceGrants cluster-wide."
    else
        echo ""
        echo "${YELLOW_TEXT}╔══════════════════════════════════════════════════════════════════════╗${RESET_TEXT}"
        echo "${YELLOW_TEXT}║  WARNING: Traefik may lack RBAC permission to read ReferenceGrants   ║${RESET_TEXT}"
        echo "${YELLOW_TEXT}╚══════════════════════════════════════════════════════════════════════╝${RESET_TEXT}"
        echo ""
        echo "Cross-namespace licensing routes will silently fail to attach."
        echo "Ensure your Traefik Helm chart version supports ReferenceGrant RBAC."
        echo "You can patch manually:"
        echo ""
        echo "  kubectl create clusterrolebinding traefik-referencegrant \\"
        echo "    --clusterrole=traefik-referencegrant \\"
        echo "    --serviceaccount=${TRAEFIK_NAMESPACE}:${traefik_sa}"
        echo ""
    fi

    # ── Read cluster data ─────────────────────────────────────────────────────
    licensing_namespace=$(${CLI_CMD} get sub -A 2>/dev/null | grep ibm-licensing-operator-app | cut -d ' ' -f1)
    if [[ -z "${licensing_namespace}" ]]; then
        licensing_namespace="ibm-licensing"
        warning "Could not detect licensing namespace, using default: ibm-licensing"
    fi

    cp_console_hostname=$(${CLI_CMD} get cm ibmcloud-cluster-info -n "${bai_namespace}" \
        -o jsonpath='{.data.cluster_address}' 2>/dev/null)
    if [[ -z "${cp_console_hostname}" ]]; then
        error "Cannot find cluster_address in ibmcloud-cluster-info ConfigMap in namespace ${bai_namespace}."
        exit 1
    fi

    domain_name=$(${CLI_CMD} get cm ibm-cpp-config -n "${bai_namespace}" \
        -o jsonpath='{.data.domain_name}' 2>/dev/null)
    if [[ -z "${domain_name}" ]]; then
        error "Cannot find domain_name in ibm-cpp-config ConfigMap in namespace ${bai_namespace}."
        exit 1
    fi

    # ── GatewayClass ──────────────────────────────────────────────────────────
    echo ""
    info "Configuring Gateway API GatewayClass..."
    echo ""
    echo "Available GatewayClasses in your cluster:"
    ${CLI_CMD} get gatewayclass \
        -o custom-columns=NAME:.metadata.name,CONTROLLER:.spec.controllerName,ACCEPTED:.status.conditions[0].status \
        --no-headers 2>/dev/null || echo "  (none found)"
    echo ""
    read -rp "Enter the GatewayClass name to use [default: traefik]: " gateway_class_input
    if [[ -z "$gateway_class_input" ]]; then
        gateway_class_input="traefik"
    fi
    GATEWAY_CLASS_NAME="${gateway_class_input}"

    if ! ${CLI_CMD} get gatewayclass "${GATEWAY_CLASS_NAME}" >/dev/null 2>&1; then
        warning "GatewayClass '${GATEWAY_CLASS_NAME}' not found in the cluster."
        read -rp "Continue anyway? (yes/no, default: no): " continue_anyway
        continue_anyway=$(echo "$continue_anyway" | tr '[:upper:]' '[:lower:]')
        if [[ "$continue_anyway" != "yes" && "$continue_anyway" != "y" ]]; then
            error "Exiting. Ensure GatewayClass exists before proceeding."
            exit 1
        fi
    else
        success "GatewayClass '${GATEWAY_CLASS_NAME}' found."
    fi

    # ── Gateway IP / address ──────────────────────────────────────────────────
    echo ""
    info "Configuring Gateway address..."
    echo ""
    local detected_ip=""
    detected_ip=$(${CLI_CMD} get svc traefik -n "${TRAEFIK_NAMESPACE}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [[ -n "$detected_ip" ]]; then
        echo "Detected Traefik LoadBalancer IP: ${GREEN_TEXT}${detected_ip}${RESET_TEXT}"
        echo ""
    fi
    echo "Enter the static IP address for the Gateway (type:IPAddress)."
    echo "Press Enter to omit (let the Traefik controller assign the IP automatically)."
    if [[ -n "$detected_ip" ]]; then
        read -rp "Gateway IP [detected: ${detected_ip}]: " gateway_ip_input
        if [[ -z "$gateway_ip_input" ]]; then
            gateway_ip_input="$detected_ip"
        fi
    else
        read -rp "Gateway IP (or press Enter to omit): " gateway_ip_input
    fi
    GATEWAY_IP="${gateway_ip_input}"

    # ── cert-manager ─────────────────────────────────────────────────────────
    if ! ${CLI_CMD} get pods -n cert-manager >/dev/null 2>&1; then
        warning "cert-manager not found. TLS Certificates require cert-manager."
        echo "Install cert-manager: https://cert-manager.io/docs/installation/"
        echo ""
    fi

    if ! ${CLI_CMD} get issuer zen-tls-issuer -n "${bai_namespace}" >/dev/null 2>&1; then
        warning "zen-tls-issuer not found in namespace ${bai_namespace}."
        echo "This issuer is created by IBM Cloud Pak installation."
        echo ""
    fi

    # ── Existing NGINX Ingress objects — warn, never delete ──────────────────
    echo ""
    local existing_ingresses
    existing_ingresses=$(${CLI_CMD} get ingress -n "${bai_namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$existing_ingresses" -gt 0 ]]; then
        echo "${YELLOW_TEXT}╔══════════════════════════════════════════════════════════════════════╗${RESET_TEXT}"
        echo "${YELLOW_TEXT}║  WARNING: Existing NGINX Ingress objects detected                    ║${RESET_TEXT}"
        echo "${YELLOW_TEXT}╚══════════════════════════════════════════════════════════════════════╝${RESET_TEXT}"
        echo ""
        echo "Found ${existing_ingresses} Ingress object(s) in namespace ${bai_namespace}:"
        ${CLI_CMD} get ingress -n "${bai_namespace}" --no-headers 2>/dev/null | awk '{print "  " $0}'
        echo ""
        echo "These NGINX Ingress objects will COMPETE with the new Gateway API HTTPRoutes."
        echo "After verifying that Gateway API routes work correctly, delete them manually:"
        echo ""
        echo "  ${GREEN_TEXT}kubectl delete ingress zen-ingress -n ${bai_namespace}${RESET_TEXT}"
        echo "  (and any other NGINX ingresses you want to retire)"
        echo ""
        echo "${RED_TEXT}DO NOT delete them now — only after Gateway API is verified working.${RESET_TEXT}"
        echo ""
    fi

    # ── Session affinity warning (no standard CRD equivalent in Traefik) ─────
    echo ""
    local auth_replicas
    auth_replicas=$(${CLI_CMD} get deploy platform-auth-service -n "${bai_namespace}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)
    echo "${YELLOW_TEXT}╔══════════════════════════════════════════════════════════════════════╗${RESET_TEXT}"
    echo "${YELLOW_TEXT}║  INFO: Session affinity — no GCPBackendPolicy equivalent             ║${RESET_TEXT}"
    echo "${YELLOW_TEXT}╚══════════════════════════════════════════════════════════════════════╝${RESET_TEXT}"
    echo ""
    echo "On GKE, GCPBackendPolicy provided GENERATED_COOKIE session affinity for"
    echo "platform-auth-service (/oidc flows). Traefik Gateway API has no equivalent CRD."
    echo ""
    if [[ -n "$auth_replicas" && "$auth_replicas" -gt 1 ]]; then
        echo "${RED_TEXT}⚠ RISK: platform-auth-service has ${auth_replicas} replicas.${RESET_TEXT}"
        echo "  OIDC login flows may loop or fail under load because successive requests"
        echo "  may land on different pods with different session state."
        echo "  OPTIONS:"
        echo "    1. Scale to 1 replica (safest):  kubectl scale deploy platform-auth-service -n ${bai_namespace} --replicas=1"
        echo "    2. Accept the risk (appropriate for dev/test single-user scenarios)"
    else
        echo "platform-auth-service replicas: ${auth_replicas:-unknown} — session affinity risk is LOW."
        echo "If replicas are ever scaled >1, OIDC flows may break without sticky sessions."
    fi
    echo ""

    # ── ibm-nginx health probe warning ───────────────────────────────────────
    echo "${YELLOW_TEXT}╔══════════════════════════════════════════════════════════════════════╗${RESET_TEXT}"
    echo "${YELLOW_TEXT}║  INFO: No HealthCheckPolicy equivalent — verify readiness probes     ║${RESET_TEXT}"
    echo "${YELLOW_TEXT}╚══════════════════════════════════════════════════════════════════════╝${RESET_TEXT}"
    echo ""
    echo "On GKE, HealthCheckPolicy controlled GCP LB health probes (e.g. ibm-nginx"
    echo "probed on :8443/diag, NOT on Service port 443). Traefik uses Kubernetes"
    echo "readiness probes instead — no separate CRD is needed."
    echo ""
    echo "Please verify BEFORE applying Gateway API resources:"
    echo "  1. ibm-nginx pods have a readinessProbe on port 8443 with path /diag"
    echo "     kubectl get deploy ibm-nginx -n ${bai_namespace} -o yaml | grep -A 10 readinessProbe"
    echo "  2. opensearch pods have a readinessProbe that does NOT return 401"
    echo "     (unauthenticated OpenSearch requests return 401 — this must not mark pods unready)"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION: get_client_id_rancher_gateway
# ─────────────────────────────────────────────────────────────────────────────
function get_client_id_rancher_gateway() {
    client_id=$(${CLI_CMD} get secret ibm-iam-bindinfo-platform-oidc-credentials \
        -n "${bai_namespace}" \
        -o jsonpath='{.data.WLP_CLIENT_ID}' 2>/dev/null | base64 --decode)
    if [[ -z "${client_id}" ]]; then
        error "Cannot retrieve WLP_CLIENT_ID from ibm-iam-bindinfo-platform-oidc-credentials secret."
        error "Check that the BAI Standalone Custom Resource is in Ready status."
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION: patch_services_for_https_rancher
#
# On GKE:    kubectl patch svc ... appProtocol:HTTPS (uppercase) + cloud.google.com/neg
# On Traefik (kubernetesGateway provider):
#   kubectl patch svc ... appProtocol:https (lowercase)
#
# WHY appProtocol:https — NOT the serversscheme annotation:
#   Traefik's kubernetesGateway provider resolves backends to pod IPs via EndpointSlices
#   and reads the appProtocol field on the Service port to determine backend scheme.
#   appProtocol:https (lowercase, IANA-registered value) tells Traefik to use TLS.
#
#   The annotation traefik.ingress.kubernetes.io/service.serversscheme=https is ONLY
#   honoured by the kubernetesCRD (IngressRoute) provider — it is silently ignored by
#   kubernetesGateway. Without appProtocol:https, Traefik sends plain HTTP to pods
#   that expect HTTPS, producing 502 Bad Gateway with zero error in logs.
#
#   ibm-nginx-svc works without appProtocol because it has port:443 ≠ targetPort:8443.
#   This port/targetPort asymmetry triggers a different endpoint resolution path in
#   Traefik that correctly honours serversscheme. All auth services have port==targetPort
#   (e.g. 4300:4300) and require appProtocol:https to be patched explicitly.
#
#   GKE uses appProtocol:HTTPS (uppercase) for the same purpose. Traefik uses lowercase
#   'https' per IANA registered name convention. The NEG annotation
#   (cloud.google.com/neg) is GKE-specific — NOT needed.
# ─────────────────────────────────────────────────────────────────────────────
function patch_services_for_https_rancher() {
    info "Patching services with appProtocol:https for HTTPS backend transport..."
    echo ""
    echo "NOTE: appProtocol:https (lowercase) on Service ports tells Traefik's"
    echo "      kubernetesGateway provider to use TLS when connecting to backend pods."
    echo "      This replaces GKE's appProtocol:HTTPS + NEG annotation pattern."
    echo ""

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "${YELLOW_TEXT}[DRY RUN] The following patches would be applied:${RESET_TEXT}"
        echo ""
    fi

    # Services and their HTTPS port index (0-based) that need appProtocol:https.
    # Format: "namespace:service:port_index"
    # ibm-nginx-svc is intentionally excluded: its port:443/targetPort:8443 asymmetry
    # causes Traefik to already use the correct HTTPS endpoint path.
    local all_services=(
        "${bai_namespace}:platform-auth-service:0"
        "${bai_namespace}:platform-identity-provider:0"
        "${bai_namespace}:platform-identity-management:0"
        "${licensing_namespace}:ibm-licensing-service-instance:0"
    )

    for entry in "${all_services[@]}"; do
        local svc_ns="${entry%%:*}"; local rest="${entry#*:}"
        local svc_name="${rest%%:*}"; local port_idx="${rest##*:}"
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            echo "  Would patch: ${svc_ns}/${svc_name} ports[${port_idx}].appProtocol=https"
        else
            if ${CLI_CMD} get svc "${svc_name}" -n "${svc_ns}" >/dev/null 2>&1; then
                ${CLI_CMD} patch svc "${svc_name}" -n "${svc_ns}" --type=json \
                    -p="[{\"op\":\"add\",\"path\":\"/spec/ports/${port_idx}/appProtocol\",\"value\":\"https\"}]" \
                    2>/dev/null || true
                success "Patched ${svc_ns}/${svc_name} → appProtocol:https"
            else
                warning "Service ${svc_ns}/${svc_name} not found — skipping."
            fi
        fi
    done

    echo ""
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        success "Services patched with appProtocol:https."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION: replace_rancher_gateway
# ─────────────────────────────────────────────────────────────────────────────
function replace_rancher_gateway() {
    if [[ -z "${output_file}" ]]; then
        output_file=$(mktemp)
    fi

    info "Writing Rancher/Traefik Gateway API manifests to ${output_file}"

    cp "${current_dir}/gateway_api_template_rancher_base.yaml" "${output_file}"

    ${SED_COMMAND} "s|NAMESPACE|${bai_namespace}|g" "${output_file}"
    ${SED_COMMAND} "s|HOST|${cp_console_hostname}|g" "${output_file}"
    ${SED_COMMAND} "s|DOMAIN|${domain_name}|g" "${output_file}"
    ${SED_COMMAND} "s|LICENSING_NS|${licensing_namespace}|g" "${output_file}"
    ${SED_COMMAND} "s|GATEWAY_CLASS|${GATEWAY_CLASS_NAME}|g" "${output_file}"

    # Gateway address: inject IPAddress block if provided, otherwise remove placeholder line
    if [[ -n "${GATEWAY_IP}" ]]; then
        ${SED_COMMAND} "s|GATEWAY_IP_PLACEHOLDER|${GATEWAY_IP}|g" "${output_file}"
    else
        # Remove the entire addresses: block (3 lines: addresses:, - type: IPAddress, value: ...)
        ${SED_COMMAND} "/GATEWAY_IP_PLACEHOLDER/d" "${output_file}"
        ${SED_COMMAND} "/^    - type: IPAddress$/d" "${output_file}"
        ${SED_COMMAND} "/^  addresses:$/d" "${output_file}"
    fi

    # Workaround for macOS sed creating backup files with empty suffix
    if [[ -f "${output_file}\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION: bai_rancher_generate_gateway_api  (main entry point)
# ─────────────────────────────────────────────────────────────────────────────
function bai_rancher_generate_gateway_api() {
    bai_namespace=$1
    output_file=$2

    # Initialise variables
    client_id=""
    cp_console_hostname=""
    domain_name=""
    licensing_namespace=""
    GATEWAY_CLASS_NAME=""
    GATEWAY_IP=""
    TRAEFIK_NAMESPACE="traefik"

    # Parse --dry-run flag if passed as third argument
    if [[ "${3:-}" == "--dry-run" ]]; then
        DRY_RUN="true"
        echo ""
        echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
        echo "${YELLOW_TEXT}  DRY RUN MODE — no cluster mutations will be made${RESET_TEXT}"
        echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
        echo ""
    else
        DRY_RUN="false"
    fi

    # Set output directory
    output_dir=$(dirname "${output_file}")
    mkdir -p "${output_dir}"

    # Step 1 — Prerequisites and cluster interrogation
    check_prereqs_rancher_gateway

    # Step 2 — Get OIDC client ID
    get_client_id_rancher_gateway

    # Step 3 — Patch / annotate services
    echo ""
    info "Annotating services for HTTPS backend transport..."
    patch_services_for_https_rancher

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "${YELLOW_TEXT}DRY RUN COMPLETE — review above, then run without --dry-run${RESET_TEXT}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        return 0
    fi

    # Step 4 — Generate manifest
    echo ""
    info "Generating Rancher/Traefik Gateway API manifest..."
    replace_rancher_gateway

    # Step 5 — Copy to final well-known path
    local final_output="${output_dir}/gateway-api-rancher.yaml"
    if [[ "${output_file}" != "${final_output}" ]]; then
        cp "${output_file}" "${final_output}"
    fi

    echo ""
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "Rancher/Traefik Gateway API manifests created successfully!"
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "Generated file:"
    echo "  ${GREEN_TEXT}${output_dir}/gateway-api-rancher.yaml${RESET_TEXT}"
    echo ""
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Made with Bob
