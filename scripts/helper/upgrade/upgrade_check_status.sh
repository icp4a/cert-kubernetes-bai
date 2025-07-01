#!/BIN/BASH
# set -x
###############################################################################
#
# LICENSED MATERIALS - PROPERTY OF IBM
#
# (C) COPYRIGHT IBM CORP. 2023. ALL RIGHTS RESERVED.
#
# US GOVERNMENT USERS RESTRICTED RIGHTS - USE, DUPLICATION OR
# DISCLOSURE RESTRICTED BY GSA ADP SCHEDULE CONTRACT WITH IBM CORP.
#
###############################################################################


#Determine if it's an Ifix to ifix upgrade or a n-1 upgrade using CSV
# Format of CSV x.y.z where x is major version, y is minor version and z is ifix version
# For example: 
# - 24.0.1 version will have 24.1.0 in the CSV
# - 24.0.1-IF001 version will 24.1.1 in the CSV
# - 25.0.0-GA version will have 25.0.0 in the CSV 
# The rules are:
# 1. n-1 upgrade: Use the desired major version such as 24 from the CP4BA_CSV_VERSION in the common.sh  to compare with the current install version
#   - If x version of the current CSV is equal to the desired major version, then it's a n-1 upgrade.  For example, if the current version is 24.0.0-IF003 (24.0.3) and the desired version is 24.0.1 (24.1.0), then it's a n-1 upgrade
#   - If x version of the current CSV is equal to the desired major version (x+1), then it's the n-1 upgrade. For example, if the current version is 24.x and the desired version is 25.x, then it's a n-1 upgrade
# 2. Ifix to Ifix upgrade: Use the desired major version such as 24 from the CP4BA_CSV_VERSION in the common.sh  to compare with the current install version
#   - If x.y version of the current CSV is equal to x.y of the desired major version, then it's an Ifix to Ifix upgrade. For example, if the current version is 24.0.0-IF003 (24.0.3) and the desired version is 24.0.0-IF004 (24.0.4), then it's an Ifix to Ifix upgrade
# The function will set the is_ifix_to_ifix_upgrade flag to 1 if it's an Ifix to Ifix upgrade and 0 if it's a n-1 upgrade
function determine_type_of_upgrade() {
    info "Determining the type of upgrade"
    local current_version=$1
    local current_version_major=$(echo $current_version | cut -d'.' -f1)
    local current_version_minor=$(echo $current_version | cut -d'.' -f2)
    local desired_version="${BAI_CSV_VERSION//v/}"
    local desired_version_major=$(echo $desired_version | cut -d'.' -f1)
    local desired_version_minor=$(echo $desired_version | cut -d'.' -f2)
    if [[ $current_version_major"."$current_version_minor == $desired_version_major"."$desired_version_minor ]]; then
        export is_ifix_to_ifix_upgrade="true"
        info "This is an upgrade from $current_version to $desired_version which is an Ifix to Ifix upgrade"
    else
        export is_ifix_to_ifix_upgrade="false"
        info "This is an upgrade from $current_version to $desired_version which is an n-1 to n upgrade"
    fi

}

# This function is used in check_bai_operator_version where it will check the version of the operator and compare it with the array of minimum supported upgrade versions
# It will fail if the operator version is not less than the minimum supported upgrade version.
# This function takes 3 arguments:
# 1. current_csv_version: The csv of the version that needs to be checked such as "24.0.0", "24.0.4", "240.1"
# 2. failed_upgrade_message: The message that will be displayed if the version is not supported
function check_bai_minimum_version(){

    local current_version=$1
    local failed_upgrade_message=$2

    for version in "${MINIMUM_SUPPORTED_UPGRADE_VERSIONS[@]}"; do
        if [[ "$current_version" == "${BAI_CSV_VERSION//v/}" ]]; then
            info "The current IBM Business Automation Insights Operator is already ${BAI_CSV_VERSION//v/}"
            valid_version=true
            break
        fi
        if [[ (! "$(printf '%s\n' "$version" "$current_version" | sort -V | head -n1)" = "$version") ]]; then
            info "Found IBM Business Automation Insights Operator is \"$current_version\" version."
            fail "$failed_upgrade_message"
            valid_version=false
            exit 1
        else
            info "Found IBM Business Automation Insights Operator is \"$current_version\" version."
            valid_version=true
            break
        fi

    done 
}

# function for checking bai standalone operator version
function check_bai_operator_version(){
    local project_name=$1
    local maxRetry=5
    info "Checking the version of IBM Business Automation Insights Operator"
    bai_operator_csv_name=$(${CLI_CMD} get csv -n $project_name --no-headers --ignore-not-found | grep "IBM Business Automation Insights" | awk '{print $1}')
    
    if [[ -z $bai_operator_csv_name ]]; then
        fail "No IBM Business Automation Insights Operator found in \"$project_name\" project."
        warning "Input correct project name for BAI Standalone."
        exit 1
    fi
    for ((retry=0;retry<=${maxRetry};retry++)); do
        valid_version=false  #this is flag to check if the BAI S operator is a valid version
        if [[ (! -z $bai_operator_csv_name) ]]; then
            success "Found IBM Business Automation Insights Operator deployed in the project \"$project_name\"."
            ALL_NAMESPACE_FLAG="No"
            TEMP_OPERATOR_PROJECT_NAME=$project_name
            bai_operator_csv_version=$(${CLI_CMD} get csv $bai_operator_csv_name -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')
        fi
        

        if [[ ! -z $BAI_ORIGINAL_CSV_VERSION ]]; then
            BAI_ORIGINAL_CSV_VERSION=$(sed -e 's/^"//' -e 's/"$//' <<<"$BAI_ORIGINAL_CSV_VERSION")
            bai_operator_csv_version=$BAI_ORIGINAL_CSV_VERSION
        fi
        # DBACLD-165816: Calling check_bai_minimum_version function to check the minimum supported version
        check_bai_minimum_version "$bai_operator_csv_version" "Upgrade to BAI Standalone v24.0.0 or a later iFix first before upgrading to BAI Standalone $BAI_CSV_VERSION"

        determine_type_of_upgrade "$bai_operator_csv_version"
        if [[ "$valid_version" == true ]]; then
            break
        fi
        if [[ "$bai_operator_csv_version" != "${BAI_CSV_VERSION//v/}" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                info "Timeout Checking for the version of IBM Business Automation Insights in the project \"$project_name\""
                exit 1
            else
                sleep 2
                echo -n "..."
                continue
            fi
        fi
    done
}

function check_operator_status(){
    local maxRetry=30
    local project_name=$1
    local check_mode=$2 # full or partial
    local check_channel=$3
    CHECK_BAI_OPERATOR_RESULT=()
    if [[ "$check_mode" == "full" ]]; then
        echo "****************************************************************************"
        info "Checking the IBM Cert-manager Operator ready or not"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReadyWebhook=$(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-webhook -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')
            isReadyCertmanager=$(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-controller -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')
            isReadyCainjector=$(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-cainjector -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')
            isReadyCertmanagerOperator=$(kubectl get pod -l=app.kubernetes.io/name=cert-manager,app.kubernetes.io/instance=ibm-cert-manager-operator -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')

            if [[ -z $isReadyWebhook || -z $isReadyCertmanager || -z $isReadyCainjector || -z $isReadyCertmanagerOperator ]]; then
            # if [[ -z $isReadyCertmanagerOperator ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    printf "\n"
                    warning "Timeout Waiting for IBM Cert-manager Operator to start"
                    echo -e "\x1B[1mCheck the status of Pod by issuing the following command: \x1B[0m"
                    if [[ -z $isReadyWebhook ]]; then
                        echo "kubectl describe pod $(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-webhook --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
                    fi
                    if [[ -z $isReadyCertmanager ]]; then
                        echo "kubectl describe pod $(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-controller --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
                    fi
                    if [[ -z $isReadyCainjector ]]; then
                        echo "kubectl describe pod $(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-cainjector --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
                    fi
                    if [[ -z $isReadyCertmanagerOperator ]]; then
                        echo "kubectl describe pod $(kubectl get pod -l=app.kubernetes.io/name=cert-manager,app.kubernetes.io/instance=ibm-cert-manager-operator --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
                    fi
                    CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "FAIL" )
                    exit 1
                else
                    sleep 10
                    echo -n "..."
                    continue
                fi
            else
                success "IBM Cert-manager Operator is running: "
                # info "Pod: $isReadyCertmanagerOperator"
                info "Pod: $isReadyCertmanager"
                echo "            $isReadyWebhook"
                echo "            $isReadyCainjector"
                echo "            $isReadyCertmanagerOperator"
                CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        done
        echo "****************************************************************************"
        # success "IBM Cert-manager is running"
    fi

    # Check Common Service Operator
    if [[ "$check_mode" == "full" ]]; then
        local maxRetry=10
        echo "****************************************************************************"
        info "Checking for IBM Cloud Pak foundational operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            # isReady=$(kubectl exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
            if [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout Waiting for IBM Cloud Pak foundational operator to start"
                echo -e "\x1B[1mCheck the status of Pod by issuing the following command:\x1B[0m"
                echo "oc describe pod $(oc get pod -n $project_name|grep ibm-common-service-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mCheck the status of ReplicaSet by issuing the following command:\x1B[0m"
                echo "oc describe rs $(oc get rs -n $project_name|grep ibm-common-service-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                pod_name=$(kubectl get pod -l=name=ibm-common-service-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM Cloud Pak foundational Operator pod is NOT running"
                    CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM Cloud Pak foundational Operator is running"
                    info "Pod: $pod_name"
                    CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"
    fi


    # Check CP4BA operator upgrade status
    if [[ "$check_mode" == "full" ]]; then
        local maxRetry=20
        echo "****************************************************************************"
        info "Checking for IBM Business Automation Insights stand-alone (BAI S) operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(kubectl get csv ibm-bai-insights-engine-operator.$BAI_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            # isReady=$(kubectl exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
            if [[ -z $isReady ]]; then
                fail "Failed to upgrade the IBM Business Automation Insights stand-alone (BAI S) operator to ibm-bai-insights-engine-operator.$BAI_CSV_VERSION under project \"$project_name\"" 
                msg "Check the Subscription and ClusterServiceVersions and then fix the issues before proceeding."
                exit 1
            elif [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout Waiting for IBM Business Automation Insights stand-alone (BAI S) operator to start"
                echo -e "\x1B[1mCheck the status of Pod by executing the below command:\x1B[0m"
                echo "oc describe pod $(oc get pod -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mCheck the status of ReplicaSet by executing the below command:\x1B[0m"
                echo "oc describe rs $(oc get rs -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                if [[ "$check_channel" == "channel" ]]; then
                    success "IBM Business Automation Insights stand-alone (BAI S) Operator is in the phase of \"$isReady\"!"
                    CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"
    fi

    # Check CP4BA Foundation operator upgrade status
    echo "****************************************************************************"
    info "Checking for BAI Foundation operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(kubectl get csv ibm-bai-foundation-operator.$BAI_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        # isReady=$(kubectl exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(kubectl get csv $(kubectl get csv --no-headers --ignore-not-found -n $project_name | grep ibm-bai-foundation-operator.v |awk '{print $1}') --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
            if [[ "v$csv_version" != $BAI_CSV_VERSION ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    fail "Failed to upgrade the IBM BAI Foundation operator to ibm-bai-foundation-operator.$BAI_CSV_VERSION under project \"$project_name\"" 
                    msg "Check the Subscription and ClusterServiceVersions and then fix the issues before proceeding."
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        elif [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
            printf "\n"
            warning "Timeout Waiting for IBM BAI Foundation operator to start"
            echo -e "\x1B[1mCheck the status of Pod by issuing the following command:\x1B[0m"
            echo "oc describe pod $(oc get pod -n $project_name|grep ibm-bai-foundation-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mCheck the status of ReplicaSet by issuing the following command:\x1B[0m"
            echo "oc describe rs $(oc get rs -n $project_name|grep ibm-bai-foundation-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(kubectl get pod -l=name=ibm-bai-foundation-operator,release=$BAI_RELEASE_BASE --no-headers --ignore-not-found -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM Business Automation Insights Foundation operator pod is NOT running"
                    CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM Business Automation Insights Foundation operator is running"
                    info "Pod: $pod_name"
                    CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            elif [[ "$check_channel" == "channel" ]]; then
                success "IBM Business Automation Insights Foundation operator is in the phase of \"$isReady\"!"
                CHECK_BAI_OPERATOR_RESULT=( "${CHECK_BAI_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        fi
    done
    echo "****************************************************************************"
}

function check_bai_deployment_status(){
    local project_name=$1
    # local meta_name=$2


    UPGRADE_STATUS_BAI_FOLDER=${TEMP_FOLDER}/${project_name}
    mkdir -p ${UPGRADE_STATUS_BAI_FOLDER}
    UPGRADE_STATUS_BAI_FILE=${UPGRADE_STATUS_BAI_FOLDER}/.insightsengine_status.yaml

    UPGRADE_DEPLOYMENT_insightsengine_CR_BAK=${CUR_DIR}/bai-upgrade/project/$project_name/custom_resource/backup/insightsengine_cr_backup.yaml

    bai_cr_name=$(kubectl get insightsengine -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z "$bai_cr_name" ]; then
        cp4ba_cr_metaname=$(kubectl get insightsengine $bai_cr_name -n $project_name --no-headers --ignore-not-found -o yaml | ${YQ_CMD} r - metadata.name)
        kubectl get insightsengine $bai_cr_name -n ${project_name} --no-headers --ignore-not-found -o yaml > ${UPGRADE_STATUS_BAI_FILE}
    fi

    if [[ -z "${bai_cr_name}" ]]; then
        fail "Not found any insightsengine custom resource files in the project \"$project_name\", exiting ..."
        exit 1
    fi

    if [ -z "${bai_cr_name}" ]; then
        UPGRADE_STATUS_FILE=${UPGRADE_STATUS_CONTENT_FILE}
    elif [ ! -z "${bai_cr_name}" ]; then
        UPGRADE_STATUS_FILE=${UPGRADE_STATUS_BAI_FILE}
    fi
    
    if [[ ( ! -z "${bai_cr_name}" ) ]]; then
        convert_olm_cr "${UPGRADE_STATUS_FILE}"
        if [[ $olm_cr_flag == "No" ]]; then
            #this variable is being used to check what the version of CP4BA was used before upgrade and is used later in a check if some alert message is to be printed
            # initial_app_version=`cat $UPGRADE_DEPLOYMENT_insightsengine_CR_BAK | ${YQ_CMD} r - spec.appVersion`
            existing_pattern_list=""
            existing_opt_component_list=""
            EXISTING_PATTERN_ARR=()
            EXISTING_OPT_COMPONENT_ARR=()
            existing_pattern_list=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
            existing_opt_component_list=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`

            OIFS=$IFS
            IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
            IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
            IFS=$OIFS
        fi

        #################### BAA AE Multiple instance #######################
        AE_ENGINE_DEPLOYMENT=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.application_engine_configuration`
        cr_metaname=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - metadata.name`
        if [[ ! -z "$AE_ENGINE_DEPLOYMENT" ]]; then
            item=0
            while true; do
                ae_config_name=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.application_engine_configuration.[${item}].name`
                if [[ -z "$ae_config_name" ]]; then
                    break
                else
                    source ${CUR_DIR}/helper/upgrade/deployment_check/baa_status.sh
                    ((item++))
                fi
            done
        fi
        #################### BAStudio #######################
        BASTUDIO_DEPLOYMENT=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.bastudio_configuration.admin_user`
        if [[ ! -z "$BASTUDIO_DEPLOYMENT" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/bastudio_status.sh
        fi
        ## currently this script wont execute as the CR for BAI Standalone does not have individual status variables for each component deployed
        #################### BAI #######################
        if [[ " ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "bai" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/bai_status.sh
        fi

        #################### BAML #######################
        BAML_DEPLOYMENT=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.baml_configuration`
        if [[ ! -z "$BAML_DEPLOYMENT" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/baml_status.sh
        fi

        #################### BAW runtime Multiple instance #######################
        BAW_DEPLOYMENT=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.baw_configuration`
        cr_metaname=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - metadata.name`
        if [[ ! -z "$BAW_DEPLOYMENT" ]]; then
            item=0
            while true; do
                baw_instance_name=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.baw_configuration.[${item}].name`
                if [[ -z "$baw_instance_name" ]]; then
                    break
                else
                    source ${CUR_DIR}/helper/upgrade/deployment_check/baw_runtime_status.sh
                    ((item++))
                fi
            done
        fi
    fi

}

function show_bai_upgrade_status() {
    printf '%s %s\n' "$(date)" "[refresh interval: 30s]"
    echo -en "[Press Ctrl+C to exit] \t\t"
    check_bai_deployment_status "${BAI_SERVICES_NS}"

    printf "\n"
    step_num=1
    echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}:"
    # https://jsw.ibm.com/browse/DBACLD-158711 updating the upgrade status
    echo "${YELLOW_TEXT}  * After the status of upgrade for Zen Service components showing as ${RESET_TEXT}${GREEN_TEXT}\"Completed\"${RESET_TEXT}${YELLOW_TEXT}, the BAI deployment upgrade can be monitored by monitoring the logs of the ibm-insights-engine-operator.${RESET_TEXT}"
    echo "  - ${YELLOW_TEXT} Retrieve the the logs of of the Insights Engine operator pod by exiting the script and running \"kubectl logs $(kubectl get pod -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') \"${RESET_TEXT}"
    echo "  - ${YELLOW_TEXT} AFTER UPGRADING the IBM Business Automations Insights (BAI) DEPLOYMENT SUCCESSFULLY, YOU NEED TO REMOVE${RESET_TEXT} ${RED_TEXT}\"recovery_path\"${RESET_TEXT} ${YELLOW_TEXT}FROM THE CUSTOM RESOURCE FILE UNDER${RESET_TEXT} ${RED_TEXT}\"the bai_configuration section\"${RESET_TEXT} ${YELLOW_TEXT}MANUALLY IF IT EXISTS.${RESET_TEXT}"
    echo "  - ${YELLOW_TEXT}[ATTENTION]: ${RESET_TEXT}${YELLOW_TEXT}DON'T SET ${RESET_TEXT}${RED_TEXT}\"shared_configuration.sc_egress_configuration.sc_restricted_internet_access\"${RESET_TEXT}${YELLOW_TEXT} TO ${RESET_TEXT}${RED_TEXT}\"true\"${RESET_TEXT}${YELLOW_TEXT} UNTIL AFTER YOU'VE COMPLETED THE BAI UPGRADE TO $BAI_RELEASE_BASE.${RESET_TEXT} ${GREEN_TEXT}(UNLESS YOU ALREADY HAD THIS SET TO \"true\" IN THE pre upgrade BAI VERSION)${RESET_TEXT}"
    
}
