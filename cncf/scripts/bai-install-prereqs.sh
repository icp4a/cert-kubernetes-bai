#!/usr/bin/env bash

#set -o nounset

is_openshift=false
accept_license=false
existing_cert_manager=false
existing_licensing_service=false
licensing_namespace=ibm-licensing

# function that creates the operator groups for cert manager and ibm licensing
function create_operator_groups() {
  info "Creating the operator groups if needed ..."

  if ! ${existing_cert_manager}; then
    create_namespace ibm-cert-manager
    kubectl apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-cert-manager
  namespace: ibm-cert-manager
spec:
  upgradeStrategy: Default
EOF
    if [[ $? -ne 0 ]]; then
        error "Error creating ibm-cert-manager operator group."
    fi
  fi

  if ! ${existing_licensing_service}; then
    create_namespace ${licensing_namespace}

    existing_og_name=$(kubectl get operatorgroup -n ${licensing_namespace} -o name | awk -F "/" '{print $NF}')
    if [[ ! -z ${existing_og_name} ]]; then
      info "Operator Group '${existing_og_name}' detected in namespace '${licensing_namespace}'."
      
      add_target_namespace_to_operator_group ${licensing_namespace} ${existing_og_name} ${licensing_namespace}

    else
      # use namespace name as operatorgroup name
      kubectl apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${licensing_namespace}
  namespace: ${licensing_namespace}
spec:
  targetNamespaces:
  - ${licensing_namespace}
  upgradeStrategy: Default
EOF

      if [[ $? -ne 0 ]]; then
        error "Error creating ibm-licensing operator group."
      fi
    fi
  fi

}

# Function that creates the subscriptions for cert manager and licensing manager
function create_subscriptions() {
    printf "\n"
    info "Creating ibm-cert-manager or ibm-licensing subscription if needed ..."

    if ! ${existing_licensing_service}; then
        create_licensing_service_subscription ${licensing_namespace} "ibm-licensing" ${LICENSING_SERVICE_CHANNEL}
    fi

    if ! ${existing_cert_manager}; then
        create_ibm_certificate_manager_subscription "ibm-cert-manager" ${CERT_MANAGER_CHANNEL} 
    fi

}

# Function that checks for prereqs needed 
# This includes installing olm if it is not present already
# Function gets called as soon as rancher platform is selected in bai-clusteradmin-setup.sh
function check_cncf_rancher_prereqs() {
    printf "\n"
    info "Checking the prerequisites to install BAI Standalone Operators for platform type -> Other - Cloud Native Computing Foundation ( CNCF )..."
    #check_command kubectl

    is_openshift=false

    oc_version=$($CLI_CMD get clusterversion version -o=jsonpath={.status.desired.version} 2>/dev/null)
    if [[ ! -z ${oc_version} ]]; then
        info "Openshift version ${oc_version} detected."
        is_openshift=true
    fi
    
    
    ## Check OLM
    if [[ "$is_openshift" == true ]]; then
        olm_namespace="openshift-marketplace"
        info "OLM is installed by default on openshift clusters."
    else
        olm_namespace=$($CLI_CMD get deployment -A | grep olm-operator | awk '{print $1}')
        if [[ -z "$olm_namespace" ]]; then
            
            # Instead of installing OLM on our own, we should ask the customer first if they want the script to that or not.
            # https://jsw.ibm.com/browse/DBACLD-183358
            
            info "Cannot find Operator Lifecycle Manager (OLM) installed on this Cluster. OLM is a prerequisite to installing IBM Business Automation Insights Standalone and the script can install OLM ${OLM_VERSION} for you."
            echo
            printf "\x1B[1m\nDo you want the script to install the prerequisite OLM ${OLM_VERSION} (Yes/No, default: No) \x1B[0m"
            read -rp "" ans
            # If the user provides no input, set the default to 'No'
            if [ -z "$ans" ]; then
                ans="No"
            fi

            ans=$(echo "${ans}" | tr '[:upper:]' '[:lower:]')

            if [[ "$ans" == "yes" ]]; then

                # Saving the OLM install script locally so that it can be run even during an airgap based deployment.
                # IF we are bumping up the OLM_VERSION we need to run a few commands to get the necessary files
                # Install Script -> curl -L "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/install.sh" -o install.sh 
                # olm.yaml -> https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/olm.yaml
                # crds.yaml -> https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/crds.yaml
                # the olm-install.sh script must be tweaked to retrieve the files from $BAI_CNCF_FOLDER/olm instead of the Git URLS that it will point to when it is downloaded
                # https://jsw.ibm.com/browse/DBACLD-183358
                ${BAI_CNCF_FOLDER}/olm/olm-install.sh "${OLM_VERSION}" "$BAI_CNCF_FOLDER/olm"
                olm_install_success=$?
                
                
                #curl -L "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/install.sh" -o install.sh 
                #chmod +x install.sh
                #./install.sh "${OLM_VERSION}"
                #olm_install_success=$?
                #rm -f install.sh
                
                olm_namespace="olm"
                if [[ $olm_install_success -ne 0 ]]; then
                    error "Error installing OLM."
                    exit 1
                fi
            
            # If customer does not want the script to install OLM they can do so on their own.
            # https://jsw.ibm.com/browse/DBACLD-183358
            else
                info "OLM is a required prerequisite for installing IBM Business Automation Insights Standalone. The script will not proceed with the installation of OLM version: ${OLM_VERSION} and will now exit."
                echo
                echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
                step_num=1
                # You can run ${GREEN_TEXT}\" .${BAI_CNCF_FOLDER}/olm/olm-install.sh "${OLM_VERSION}" \"${RESET_TEXT} to install OLM version ${OLM_VERSION}.
                echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}:  Refer to https://www.ibm.com/docs/en/bai/$BAI_RELEASE_BASE?topic=ibaicoiiolc-option-1-installing-business-automation-insights-catalog-operator-instances-by-using-cluster-admin-script-recommended for more information about the prerequisites required to install IBM Business Automation Insights Standalone."
                printf "\n"
                step_num=$((step_num + 1))
                echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-clusteradmin-setup.sh \"${RESET_TEXT} to install the IBM Business Automation Insights operators."
                printf "\n"
                step_num=$((step_num + 1))
                exit 1
            fi
        else
            # Check if it is a supported version
            OLM_VERSION=$($CLI_CMD get csv packageserver -n $olm_namespace -o yaml -o jsonpath='{.spec.version}')
            if (( $(bc <<< "${OLM_VERSION:2} < ${OLM_MINIMAL_VERSION:3}") )); then
                error "Detected olm version v${OLM_VERSION} is less than supported minimal version ${OLM_MINIMAL_VERSION}. You can not install without upgrading OLM version in your cluster."
                exit 1
            fi
        fi
        success "OLM available under namespace ${olm_namespace}."
    fi
}

# Function to check if cert manager already exists and if not install it
function check_cert_manager() {
    printf "\n"
    info "Checking if ibm-cert-manager is already installed in the cluster ..."
    local CERT_MANAGER_NAMESPACE="ibm-cert-manager"

    # Check for CertManagerConfig instances
    CERT_MANAGER_CONFIGS=$(${CLI_CMD} get certmanagerconfig -n "$CERT_MANAGER_NAMESPACE" --no-headers -o custom-columns=":metadata.name")

    # Check for Subscription
    SUBSCRIPTION_EXISTS=$(${CLI_CMD} get subscription.operators.coreos.com ibm-cert-manager-operator -n "$CERT_MANAGER_NAMESPACE" --ignore-not-found)

    # Check for CSV
    CSV_NAME=$(${CLI_CMD} get csv -n "$CERT_MANAGER_NAMESPACE" | grep ibm-cert-manager | awk '{print $1}')

    # If any of these exist, proceed with installation
    if [[ -n "$CERT_MANAGER_CONFIGS" || -n "$SUBSCRIPTION_EXISTS" || -n "$CSV_NAME" ]]; then
        info "Cert Manager components detected. The BAI deployment will use the existing Cert Manager available.Proceeding with installation..."
        existing_cert_manager=true
        
    else
        info "No Cert Manager detected, the script will now install it."
        existing_cert_manager=false
    fi
    
    #kubectl get crd | grep cert-manager
    #if [[ $? -ne 0 ]] ; then
    #   info "No certificate manager detected, will install one."
    #   existing_cert_manager=false
    #else
    #   info "A certificate manager is already installed in this cluster, BAI will use it."
    #   existing_cert_manager=true
    #fi
}

# Function to check if the licensing manager is not present
function check_licensing_service() {
    printf "\n"
    info "Checking if the licensing service is already installed in the cluster ..."

    is_sub_exist "ibm-licensing-operator-app" # this will catch the packagenames of all ibm-licensing-operator-app
    if [ $? -eq 0 ]; then
        warning "There is an ibm-licensing-operator-app Subscription already. Skipping the ibm-licensing installation."
        existing_licensing_service=true
    else
        info "There is no ibm-licensing-operator-app Subscription installed, the script will proceed to install ibm-licensing service."
        existing_licensing_service=false
    fi
}

# The main function that is called by bai-clusteradmin-setup.sh script that will install cert manager, licensing manager and create all catalog sources
# Takes in 3 parameters
# licensing_namespace which is the licensing manager namespace, defaulted to ibm-licensing
# bai_namespace which is the namespace where BAI Standalone is to be deployed
# Dev mode flag which is only true when we want to deploy BAI Standalone with the staging ER images.
function bai_cncf_rancher_prereq_install() {
    licensing_namespace=$1
    bai_namespace=$2
    dev_mode=$3
    #check_prereqs
    check_cert_manager
    check_licensing_service
    create_all_catalog_sources ${bai_namespace} ${dev_mode} ${CATALOG_SOURCE_FILENAME} "freshinstall" # this function is in bai-utils and is used to create all catalog sources.
    create_operator_groups
    create_subscriptions
}