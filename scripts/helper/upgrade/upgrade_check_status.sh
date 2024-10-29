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

# function for checking bai standalone operator version
function check_bai_operator_version(){
    local project_name=$1
    local maxRetry=5
    info "Checking the version of IBM Business Automation Insights Operator"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        bai_operator_csv_name=$(kubectl get csv -n $project_name --no-headers --ignore-not-found | grep "IBM Business Automation Insights" | awk '{print $1}')
        bai_operator_csv_version=$(kubectl get csv $bai_operator_csv_name -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')

        if [[ "$bai_operator_csv_version" == "${BAI_CSV_VERSION//v/}" ]]; then
            success "The current IBM Business Automation Insights Operator is already ${BAI_CSV_VERSION//v/}"
            break
            # exit 1
        elif [[ "$bai_operator_csv_version" == "22.2."* || "$bai_operator_csv_version" == "23.1."* || "$bai_operator_csv_version" == "23.2."* ]]; then
            fail "Please upgrade to BAI Standalone 24.0.0 or a later iFix before you can upgrade to latest BAI interim fix ${BAI_CSV_VERSION//v/}"
            exit 1
        elif [[ "$bai_operator_csv_version" == "24.0."* ]]; then
            bai_operator_csv=$(kubectl get csv $bai_operator_csv_name -n $project_name -o 'jsonpath={.spec.version}')
            # cp4a_operator_csv="22.2.2"
            requiredver="24.0.0"
            if [ ! "$(printf '%s\n' "$requiredver" "$bai_operator_csv" | sort -V | head -n1)" = "$requiredver" ]; then
                fail "Please upgrade to BAI Standalone 24.0.0 or later iFix before you can upgrade to the latest BAI interim fix ${BAI_CSV_VERSION//v/}"
                exit 1
            else
                info "Found IBM Business Automation Insights Operator is \"$bai_operator_csv_version\" version."
                break
            fi
        elif [[ "$bai_operator_csv_version" != "${BAI_CSV_VERSION//v/}" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                info "Timeout Checking for the version of IBM Cloud Pak® for Business Automation under project \"$project_name\""
                exit 1
            else
                sleep 2
                echo -n "..."
                continue
            fi
        fi
    done
}

#function to check if the deployment has seperate operators and operands
function check_bai_separate_operand(){
    local project=$1
    # Check whether the BAI is separation of operators and operands.
    # operators_namespace: openshift-operators
    # services_namespace: ibm-common-services

    # operators_namespace: ibm-common-services
    # services_namespace: ibm-common-services

    # operators_namespace: cp4a-ns
    # services_namespace: cp4a-ns

    if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $project >/dev/null 2>&1; then
        success "Found \"ibm-cp4ba-common-config\" configMap in the project \"$project\"."
    else
        status=$?
        echo $status
        warning "Not found \"ibm-cp4ba-common-config\" configMap in the project \"$project\"."
        while [[ $BAI_SERVICES_NS == "" ]];
        do
            printf "\n"
            echo -e "\x1B[1mWhere (namespace) did you deploy BAI Standalone operands (i.e., runtime pods)? \x1B[0m"
            read -p "Enter the name for an existing project (namespace): " BAI_SERVICES_NS
            if [ -z "$BAI_SERVICES_NS" ]; then
                echo -e "\x1B[1;31mEnter a valid project name, project name can not be blank\x1B[0m"
            elif [[ "$BAI_SERVICES_NS" == openshift* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
                BAI_SERVICES_NS=""
            elif [[ "$BAI_SERVICES_NS" == kube* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
                BAI_SERVICES_NS=""
            else
                isProjExists=`${CLI_CMD} get project $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1

                if [ "$isProjExists" -ne 2 ] ; then
                    echo -e "\x1B[1;31mInvalid project name, please enter a existing project name ...\x1B[0m"
                    BAI_SERVICES_NS=""
                else
                    echo -e "\x1B[1mUsing project ${BAI_SERVICES_NS}...\x1B[0m"
                    if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $BAI_SERVICES_NS >/dev/null 2>&1; then
                        success "Found \"ibm-cp4ba-common-config\" configMap in the project \"$BAI_SERVICES_NS\"."
                    else
                        warning "Not found \"ibm-cp4ba-common-config\" configMap in the project \"$BAI_SERVICES_NS\"."
                        BAI_SERVICES_NS=""
                        if [[ ($SCRIPT_MODE == "" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "dev" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "review" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "baw-dev" && $RUNTIME_MODE == "") ]]; then
                            fail "You NEED to create \"ibm-cp4ba-common-config\" configMap first in the project (namespace) where you want to deploy CP4BA operands (i.e., runtime pods)."
                            exit 1
                        fi
                    fi
                fi
            fi
        done
    fi
    tmp_namespace_val=""
    if [[ $BAI_SERVICES_NS != "" ]]; then
        tmp_namespace_val=$BAI_SERVICES_NS
    else
        tmp_namespace_val=$project
    fi
    bai_services_namespace=$(${CLI_CMD} get configMap ibm-cp4ba-common-config -n $tmp_namespace_val --no-headers --ignore-not-found -o jsonpath='{.data.services_namespace}')
    bai_operators_namespace=$(${CLI_CMD} get configMap ibm-cp4ba-common-config -n $tmp_namespace_val --no-headers --ignore-not-found -o jsonpath='{.data.operators_namespace}')
    if [[ (! -z $BAI_SERVICES_NS) ]]; then
        if [[ $bai_services_namespace != $BAI_SERVICES_NS ]]; then
            fail "Your input value for BAI Standalone operands (i.e., runtime pods) is NOT equal to the value of \"services_namespace\" in \"ibm-cp4ba-common-config\" configMap under the project \"$BAI_SERVICES_NS\"."
            exit 1
        fi
    fi
    if [[ (! -z $bai_services_namespace) && (! -z $bai_operators_namespace) ]]; then
        # The IF condition below checks for separation of duties scenario (note: all-ns and shared CPfs are not considered separation of duties):
        #  - ($bai_services_namespace != $bai_operators_namespace) -> confirms that operator and services ns are different
        #  - ($bai_operators_namespace != "openshift-operators") -> confirms that scenario is NOT all-ns
        #  - ($bai_operators_namespace != "ibm-common-services") -> confirms that scenario is NOT shared/cluster-scoped CPfs scenario
        if [[ ($bai_services_namespace != $bai_operators_namespace) && ($bai_operators_namespace != "openshift-operators" && $bai_operators_namespace != "ibm-common-services") ]]; then
            info "This BAI Standalone deployment has separate operators and operands"
            SEPARATE_OPERAND_FLAG="Yes"
            BAI_SERVICES_NS=$bai_services_namespace
        else
            SEPARATE_OPERAND_FLAG="No"
            BAI_SERVICES_NS=$TARGET_PROJECT_NAME
        fi
    else
        warning "Not found \"operator_namespace\\services_namespace\" in \"ibm-cp4ba-common-config\" configMap under the project \"$tmp_namespace_val\""
        fail "You need to set correct value(s) in \"ibm-cp4ba-common-config\" configMap for BAI Standalone seperation of operators and operand under the project \"$tmp_namespace_val\""
        exit 1
    fi
}

# function for checking operator version
function check_content_operator_version(){
    local project_name=$1
    local maxRetry=5
    info "Checking the version of IBM CP4BA FileNet Content Manager Operator"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        cp4a_content_operator_csv_name=$(kubectl get csv -n $project_name --no-headers --ignore-not-found | grep "IBM CP4BA FileNet Content Manager" | awk '{print $1}')
        cp4a_content_operator_csv_version=$(kubectl get csv $cp4a_content_operator_csv_name -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')

        if [[ "$cp4a_content_operator_csv_version" == "${BAI_CSV_VERSION//v/}" ]]; then
            success "The current IBM CP4BA FileNet Content Manager Operator is already ${BAI_CSV_VERSION//v/}"
            break
        elif [[ "$cp4a_content_operator_csv_version" == "22.2."* || "$cp4a_content_operator_csv_version" == "23.1."* || "$cp4a_content_operator_csv_version" == "23.2."* ]]; then
            cp4a_content_operator_csv=$(kubectl get csv $cp4a_content_operator_csv_name -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')
            # cp4a_operator_csv="22.2.2"
            requiredver="22.2.2"
            if [ ! "$(printf '%s\n' "$requiredver" "$cp4a_content_operator_csv" | sort -V | head -n1)" = "$requiredver" ]; then
                fail "Please upgrade to CP4BA 22.0.2-IF002 or later iFix before you can upgrade to CP4BA 23.0.1 GA"
                exit 1
            else
                info "Found IBM CP4BA FileNet Content Manager Operator is \"$cp4a_content_operator_csv_version\" version."
                break
            fi
        elif [[ "$cp4a_content_operator_csv_version" != "${BAI_CSV_VERSION//v/}" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                info "Timeout Checking for the version of IBM CP4BA FileNet Content Manager Operator under project \"$project_name\""
                exit 1
            else
                sleep 2
                echo -n "..."
                continue
            fi
        fi
    done
    # success "Found the IBM CP4BA FileNet Content Manager Operator $cp4a_content_operator_csv_version \n"
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
                    echo -e "\x1B[1mPlease check the status of Pod by issue cmd: \x1B[0m"
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
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "oc describe pod $(oc get pod -n $project_name|grep ibm-common-service-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
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
        info "Checking for IBM Business Automation Insights stand-alone (CP4BA) multi-pattern operator pod initialization"
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
                echo -e "\x1B[1mPlease check the status of Pod by executing the below command:\x1B[0m"
                echo "oc describe pod $(oc get pod -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by executing the below command:\x1B[0m"
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
            echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
            echo "oc describe pod $(oc get pod -n $project_name|grep ibm-bai-foundation-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
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

    if [[ "$bai_original_csv_ver_for_upgrade_script" == "24.0."* ]]; then
        printf "\n"
        step_num=1
        echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}:"
        echo "${YELLOW_TEXT}  * After the status of upgrade for Zen Service components showing as ${RESET_TEXT}${GREEN_TEXT}\"Done\"${RESET_TEXT}${YELLOW_TEXT}, the BAI deployment upgrade can be monitored by monitoring the logs of the ibm-insights-engine-operator.${RESET_TEXT}"
        echo "  - ${YELLOW_TEXT} Retrieve the the logs of of the insights engine operator pod by exiting the script and running \"kubectl logs $(kubectl get pod -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') \"${RESET_TEXT}"
    fi
}
