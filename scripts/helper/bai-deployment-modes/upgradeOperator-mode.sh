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


# This file is a helper script used to store all functions that are used by the bai-deployment.sh for the upgradeOperator mode
# Example : bai-deployment.sh -m upgradeOperator -n <bai-namespace>

# function that checks if ibm-bai-shared-info exists and if not creates it
function check_and_created_sharedinfo_configmap(){
    info "Checking if ibm-bai-shared-info configMap exists in the project \"$BAI_SERVICES_NS\""
    ibm_bai_shared_info_cm=$(${CLI_CMD} get configmap ibm-bai-shared-info --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.data.bai_operator_of_last_reconcile}') 
    # Create ibm-bai-shared-info configMap if it doesn't exist
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
    if [[ ! -z $insightsengine_cr_name ]]; then
        cr_version=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - spec.appVersion)
        cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
        cr_uid=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.uid)
        if [[ -z $ibm_bai_shared_info_cm ]]; then
            info "ibm-bai-shared-info configMap was not found, the script will now create it."
            create_ibm_bai_shared_info_cm_yaml
            ${SED_COMMAND} "s|<bai_namespace>|$BAI_SERVICES_NS|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
            ${SED_COMMAND} "s|<cr_metaname>|$cr_metaname|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
            ${SED_COMMAND} "s|<cr_uid>|$cr_uid|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
            ${SED_COMMAND} "s|<csv_version>|$bai_operator_csv_version|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
            ${SED_COMMAND} "s|<cr_version>|$cr_version|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}

            ${CLI_CMD} apply -f $UPGRADE_BAI_SHARED_INFO_CM_FILE  >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                success "Created ibm-bai-shared-info configMap in the project \"$BAI_SERVICES_NS\"!"
                ${CLI_CMD} patch configmap ibm-bai-shared-info -n $BAI_SERVICES_NS --type=json -p="[{'op': 'add', 'path': '/data/bai_original_csv_ver_for_upgrade_script', 'value': '$(echo $bai_operator_csv_version)'}]" >/dev/null 2>&1
                ${CLI_CMD} patch configmap ibm-bai-shared-info -n $BAI_SERVICES_NS --type=json -p="[{'op': 'add', 'path': '/data/cpfs_original_csv_ver_for_upgrade_script', 'value': '$(echo $cpfs_operator_csv_version)'}]" >/dev/null 2>&1
                bai_original_csv_ver_for_upgrade_script=$bai_operator_csv_version
            else
                fail "Failed to create ibm-bai-shared-info configMap in the project \"$BAI_SERVICES_NS\"!"
            fi
        else
            success "Found ibm-bai-shared-info configMap under \"$BAI_SERVICES_NS\"!"
            ${CLI_CMD} patch configmap ibm-bai-shared-info -n $BAI_SERVICES_NS --type=json -p="[{'op': 'add', 'path': '/data/bai_original_csv_ver_for_upgrade_script', 'value': '$(echo $bai_operator_csv_version)'}]" >/dev/null 2>&1
            ${CLI_CMD} patch configmap ibm-bai-shared-info -n $BAI_SERVICES_NS --type=json -p="[{'op': 'add', 'path': '/data/cpfs_original_csv_ver_for_upgrade_script', 'value': '$(echo $cpfs_operator_csv_version)'}]" >/dev/null 2>&1
            bai_original_csv_ver_for_upgrade_script=$bai_operator_csv_version
        fi
    fi
}

function select_private_catalog_bai(){
    printf "\n"
    echo "${YELLOW_TEXT}[NOTES] You can switch the BAI Standalone deployment to a private catalog (namespace scope) or keep it in the global catalog namespace (GCN). The private catalog (recommended) uses the same target namespace as the BAI Standalone deployment, while the GCN uses the openshift-marketplace namespace.${RESET_TEXT}"

    while true; do
        printf "\x1B[1mDo you want to switch BAI Standalone deployment to use private catalog? (Yes/No, default: Yes): \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES"|"")
            ENABLE_PRIVATE_CATALOG=1
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")          
            ENABLE_PRIVATE_CATALOG=0
            break
            ;;
        *)
            PRIVATE_CATALOG=""
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

# Function that detects the catalog type
# 99.99% this will be private as from 24.0.0 we recommend private catalog type
function get_catalog_type(){
    # Check if --enable-private-catalog is set or not
    # shared to shared code can be removed
    # Call select_private_catalog_bai if --enable-private-catalog option is not set
    if ${CLI_CMD} get catalogsource -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
        PRIVATE_CATALOG_FOUND="Yes"
        ENABLE_PRIVATE_CATALOG=1
        info "This BAI Standalone deployment is installed using private catalog in the project \"$TARGET_PROJECT_NAME\""
    elif ${CLI_CMD} get catalogsource -n openshift-marketplace --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
        PRIVATE_CATALOG_FOUND="No"
        info "This BAI deployment is installed using global catalog in the project \"openshift-marketplace\""
        if [[ $ENABLE_PRIVATE_CATALOG -eq 1 && $UPGRADE_MODE == "shared2shared" ]]; then
            ENABLE_PRIVATE_CATALOG=0
            warning "Can NOT switch catalog source from global catalog namespace (GCN) to private catalog (namespace-scoped) when migration IBM Cloud Pak foundational services from \"Cluster-scoped to Namespace-scoped\"."
            prompt_press_any_key_to_continue
        elif [[ $ENABLE_PRIVATE_CATALOG -eq 1 && ($UPGRADE_MODE == "shared2dedicated" || $UPGRADE_MODE == "dedicated2dedicated") ]]; then
            info "You have set the option \"--enable-private-catalog\" for this BAI Standalone deployment to use private catalog"
        elif [[ $ENABLE_PRIVATE_CATALOG -eq 0 || -z $ENABLE_PRIVATE_CATALOG ]]; then
            if [[ $UPGRADE_MODE == "shared2dedicated" || $UPGRADE_MODE == "dedicated2dedicated" ]]; then
                select_private_catalog_bai
            elif [[ $UPGRADE_MODE == "shared2shared" ]]; then
                fail "This upgrade mode path \"$UPGRADE_MODE\" is not supported for BAI Standalone upgrade"
                exit 1
                #info "Keep to use global catalog namespace (GCN) for this BAI deployment when migration IBM Cloud Pak foundational services from \"Cluster-scoped\" to \"Cluster-scoped\"."
                #sleep 2
            fi
        fi
    fi

    
    if [[ $ENABLE_PRIVATE_CATALOG -eq 1 && $PRIVATE_CATALOG_FOUND == "No" && ($UPGRADE_MODE == "shared2dedicated" || $UPGRADE_MODE == "dedicated2dedicated") ]]; then
        info "The global catalog namespace (GCN) will be switched to private catalog (namespace-scoped)."
        sleep 2
    elif [[ $PRIVATE_CATALOG_FOUND == "Yes" ]]; then
        ENABLE_PRIVATE_CATALOG=1
        info "The BAI Standalone deployment will continue to use private catalog (namespace-scoped)."
        sleep 2
    fi

    # For shared->dedicated upgrade, we should allow user option to keep "global catalog"
    if [[ $ENABLE_PRIVATE_CATALOG -eq 0 && $UPGRADE_MODE == "shared2dedicated" ]]; then
        echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the upgrade: if you have multiple BAI Standalone deployments on this cluster and you don't want them to be updated, update installPlan approval for BTS and EDB PostgreSQL on the other BAI deployments from \"Automatic\" to \"Manual\".${RESET_TEXT}"
        prompt_press_any_key_to_continue
    fi
}

# Function that checks for the BAI Standalone operator and BAI Foundation Operator subscription and accordingly decides the value of RUN_BAI_SAVEPOINT
# RUN_BAI_SAVEPOINT gets set to yes only for a major release upgrade
# This Function also provides a way to check if subscriptions are present before proceeding
function check_subscription(){
    sub_inst_list=$(${CLI_CMD} get subscription.operators.coreos.com -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
    if [[ -z $sub_inst_list ]]; then
        info "No existing BAI Standalone subscriptions have been found, continuing ..."
        exit 1
    fi
    sub_array=($sub_inst_list)
    target_csv_version=${BAI_CSV_VERSION//v/}
    for i in ${!sub_array[@]}; do
        if [[ ! -z "${sub_array[i]}" ]]; then
            if [[ ${sub_array[i]} = ibm-bai-operator-catalog* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
                current_version=$(${CLI_CMD} get subscription.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                installed_version=$(${CLI_CMD} get subscription.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                if [[ -z $current_version || -z $installed_version ]]; then
                    error "Failed to retrieve installed or current CSV. Aborting the upgrade procedure. Check the subscription status of ${sub_array[i]}."
                    exit 1
                fi
                case "${sub_array[i]}" in
                "ibm-bai-insights-engine-operator"*)
                    prefix_sub="ibm-bai-insights-engine-operator.v"
                    ;;
                "ibm-bai-foundation-operator"*)
                    prefix_sub="ibm-bai-foundation-operator.v"
                    ;;
                esac
                current_version=${current_version#"$prefix_sub"}
                installed_version=${installed_version#"$prefix_sub"}
                if [[ $current_version != $installed_version || $current_version != $target_csv_version || $installed_version != $target_csv_version ]]; then      
                    RUN_BAI_SAVEPOINT="Yes"
                fi
            fi
        else
            fail "No subscription found for '${sub_array[i]}'! exiting now..."
            exit 1
        fi
    done
}

# Function that creates bai savepoints for a major release upgrade scenario
function create_bai_savepoints(){
    # Retrieve existing InsightsEngine CR for Create BAI save points
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $insightsengine_cr_name ]; then
        info "Retrieving the existing BAI InsightsEngine CR (Kind: insightsengines.bai.ibm.com) Custom Resource"
        cr_type="insightsengine"
        cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
        ${CLI_CMD} get $cr_type $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

        # Backup existing icp4acluster CR
        mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
        ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_CR_BAK}

        #convert_olm_cr "${UPGRADE_DEPLOYMENT_BAI_CR_TMP}"
        #if [[ $olm_cr_flag == "No" ]]; then
        #    # Get EXISTING_PATTERN_ARR/EXISTING_OPT_COMPONENT_ARR
        #    existing_pattern_list=""
        #    existing_opt_component_list=""
        #
        #    EXISTING_PATTERN_ARR=()
        #    EXISTING_OPT_COMPONENT_ARR=()
        #    existing_pattern_list=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
        #    existing_opt_component_list=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`
        #
        #    OIFS=$IFS
        #    IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
        #    IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
        #    IFS=$OIFS
        #fi

        # Create BAI save points
        info "Checking for any BAI save points"
        mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
        # Check the jq install on MacOS
        if [[ "$machine" == "Mac" ]]; then
            which jq &>/dev/null
            [[ $? -ne 0 ]] && \
            echo -e  "\x1B[1;31mUnable to locate the jq CLI. You must install it to run this script on MacOS.\x1B[0m" && \
            exit 1
        fi
        info "Creating the BAI savepoints for recovery path used for updating the custom resource file"
        ${CLI_CMD} get crd |grep insightsengines.bai.ibm.com >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            INSIGHTS_ENGINE_CR=$(${CLI_CMD} get insightsengines.bai.ibm.com --no-headers --ignore-not-found -n ${BAI_SERVICES_NS} -o name)
        fi
        if [[ -z $INSIGHTS_ENGINE_CR ]]; then
            error "Insightsengine custom resource instance not found in the project \"${BAI_SERVICES_NS}\"."
        fi
        if [[ ! -z $INSIGHTS_ENGINE_CR ]]; then
            MANAGEMENT_URL=$(${CLI_CMD} get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${BAI_SERVICES_NS} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].uri}')
            MANAGEMENT_AUTH_SECRET=$(${CLI_CMD} get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${BAI_SERVICES_NS} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].authentication.secret.secretName}')
            MANAGEMENT_USERNAME=$(${CLI_CMD} get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${BAI_SERVICES_NS} -o jsonpath='{.data.username}' | base64 -d)
            MANAGEMENT_PASSWORD=$(${CLI_CMD} get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${BAI_SERVICES_NS} -o jsonpath='{.data.password}' | base64 -d)
            if [[ -z "$MANAGEMENT_URL" || -z "$MANAGEMENT_AUTH_SECRET" || -z "$MANAGEMENT_USERNAME" || -z "$MANAGEMENT_PASSWORD" ]]; then
                error "Can not create the BAI savepoints for recovery path."
                # exit 1
            else
                # rm -rf ${UPGRADE_DEPLOYMENT_CR}/bai.json >/dev/null 2>&1
                touch ${UPGRADE_DEPLOYMENT_BAI_TMP} >/dev/null 2>&1
                if [[ -e ${UPGRADE_DEPLOYMENT_CR}/bai.json ]]; then
                    [ "$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json)" != "[]" ] && mkdir -p ${UPGRADE_DEPLOYMENT_CR}/bai-json-backup && cp ${UPGRADE_DEPLOYMENT_CR}/bai.json ${UPGRADE_DEPLOYMENT_CR}/bai-json-backup/bai_$(date +'%Y%m%d%H%M%S').json
                fi
                curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} "${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints" -o ${UPGRADE_DEPLOYMENT_CR}/bai.json >/dev/null 2>&1

                json_file_content="[]"
                if [ "$json_file_content" == "$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json)" ] ;then
                    fail "None return in \"${UPGRADE_DEPLOYMENT_CR}/bai.json\" when request BAI savepoint through REST API: curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} \"${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints\" "
                    warning "Fetch Flink job savepoints for the recovery path using above REST API manually, then place the JSON file (bai.json) under the directory \"${TEMP_FOLDER}/\""
                    prompt_press_any_key_to_continue
                fi
                ##########################################################################################################################
                ## In 24.0.1 and later, we'll only support n-1 upgrade therefore we're back to the old way of saving content event-forwarder savepoint and bai-content savepoint UNLESS the ALLOW_DIRECT_UPGRADE == 1 .
                ##########################################################################################################################
                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-event-forwarder)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-event-forwarder |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.event-forwarder.recovery_path ${tmp_recovery_path}
                    success "Savepoint for Event-forwarder has been created: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.event-forwarder.recovery_path."
                fi
                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-content)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-content |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.content.recovery_path ${tmp_recovery_path}
                    success "Flink savepoint for Content has been merged: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.content.recovery_path."
                fi

                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-icm)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-icm |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.icm.recovery_path ${tmp_recovery_path}
                    success "Flink savepoint for ICM has been merged: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.icm.recovery_path."
                fi

                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-odm)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-odm |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.odm.recovery_path ${tmp_recovery_path}
                    success "Flink savepoint for ODM has been merged: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.odm.recovery_path."
                fi

                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-bawadv)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-bawadv |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bawadv.recovery_path ${tmp_recovery_path}
                    success "Flink savepoint for BAW ADV has been merged: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.bawadv.recovery_path."
                fi

                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-bpmn)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-bpmn |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bpmn.recovery_path ${tmp_recovery_path}
                    success "Flink savepoint for BPMN has been merged: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.bpmn.recovery_path."
                fi
                # Adding Navigator's recovery path
                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-navigator)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-navigator |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.navigator.recovery_path ${tmp_recovery_path}
                    success "Flink savepoint for Navigator has been merged: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.navigator.recovery_path."
                fi
                # Adding ADS's recovery path
                if [[ "$machine" == "Mac" ]]; then
                    tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-ads)
                else
                    tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-ads |cut -d':' -f2)
                fi
                tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                if [ ! -z "$tmp_recovery_path" ]; then
                    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.ads.recovery_path ${tmp_recovery_path}
                    success "Flink savepoint for ADS has been merged: \"$tmp_recovery_path\""
                    info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.ads.recovery_path."
                fi
            fi
        fi
    fi
}

# Function to switch to a private catalog
function switch_to_private_catalog(){
    sub_inst_list=$(${CLI_CMD} get subscription.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
    if [[ -z $sub_inst_list ]]; then
        info "No existing BAI Standalone subscriptions found, continuing ..."
        # exit 1
    fi

    sub_array=($sub_inst_list)
    for i in ${!sub_array[@]}; do
        if [[ ! -z "${sub_array[i]}" ]]; then
            if [[ ${sub_array[i]} = ibm-bai-operator-catalog* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
                ${CLI_CMD} patch subscription.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -p '{"spec":{"sourceNamespace":"'"$TARGET_PROJECT_NAME"'"}}' --type=merge >/dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    sleep 1
                    success "Switched the CatalogSource of subscription '${sub_array[i]}' to project \"$TARGET_PROJECT_NAME\"!"
                    printf "\n"
                else
                    fail "Failed to switch the CatalogSource of subscription '${sub_array[i]}' to project \"$TARGET_PROJECT_NAME\"!"
                fi
            fi
        else
            fail "Subscription '${sub_array[i]}' not found in the project \"$TARGET_PROJECT_NAME\"! exiting now..."
            exit 1
        fi
    done
}

# Function that patches the channel version of the BAI Standalone operator to the latest channel
function patch_channel_version(){
    sub_inst_list=$(${CLI_CMD} get subscription.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
    if [[ -z $sub_inst_list ]]; then
        info "No existing BAI Standalone subscriptions found, continuing ..."
        # exit 1
    fi

    sub_array=($sub_inst_list)
    for i in ${!sub_array[@]}; do
        if [[ ! -z "${sub_array[i]}" ]]; then
            if [[ ${sub_array[i]} = ibm-bai-operator-catalog* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
                ${CLI_CMD} patch subscription.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -p "{\"spec\":{\"channel\":\"$BAI_CHANNEL_VERSION\"}}" --type=merge >/dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    success "Updated the channel of subscription '${sub_array[i]}' to $BAI_CHANNEL_VERSION"
                    printf "\n"
                else
                    fail "Failed to update the channel of subscription '${sub_array[i]}' to $BAI_CHANNEL_VERSION! exiting now..."
                    exit 1
                fi
            fi
        else
            fail "No subscription found for '${sub_array[i]}'! exiting now..."
            exit 1
        fi
    done
}

# function to create new project namespaces for cert manager and licensing
function create_project() {
    local project_name=$1
    project_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$project_name")

    isProjExists=`${CLI_CMD} get namespace $project_name --ignore-not-found | wc -l`  >/dev/null 2>&1

    if [ $isProjExists -ne 2 ] ; then
        ${CLI_CMD} create namespace ${project_name} >/dev/null 2>&1
        returnValue=$?
        if [ "$returnValue" == 1 ]; then
            if [ -z "$BAI_AUTO_NAMESPACE" ]; then
                echo -e "\x1B[1;31mInvalid project name, enter a valid name...\x1B[0m"
                project_name=""
                return 1
            else
                echo -e "\x1B[1;31mInvalid project name \"$BAI_AUTO_NAMESPACE\", set a valid name...\x1B[0m"
                project_name=""
                exit 1
            fi
        else
            echo -e "\x1B[1mUsing project ${project_name}...\x1B[0m"
            return 0
        fi
    else
        echo -e "\x1B[1mProject \"${project_name}\" already exists! Continuing...\x1B[0m"
        return 0
    fi
}

# Function that applies the new catalog sources based on the private/global catalog selection
# In the process it creates the cert manager and licensing manager namespaces if required
function apply_new_catalog_sources(){
    # switch catalog from "global" to "namespace" catalog or keep private catalog source
    if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
        TEMP_CATALOG_PROJECT_NAME=${TARGET_PROJECT_NAME}
        OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
        OLM_CATALOG_TMP=${TEMP_FOLDER}/.catalog_source.yaml

        info "Creating project \"$CERT_MANAGER_PROJECT\" for IBM Cert Manager operator catalog."
        create_project "$CERT_MANAGER_PROJECT"
        if [[ $? -eq 0 ]]; then
            success "Created project \"$CERT_MANAGER_PROJECT\" for IBM Cert Manager operator catalog."
        fi

        info "Creating project \"$LICENSE_MANAGER_PROJECT\" for IBM Licensing operator catalog."
        create_project "$LICENSE_MANAGER_PROJECT"
        if [[ $? -eq 0 ]]; then
            success "Created project \"$LICENSE_MANAGER_PROJECT\" for IBM Licensing operator catalog."
            printf "\n"
        fi

        # Additionally, we would check if cs-control namespace exists.
        isProjExists=`${CLI_CMD} get project $DEDICATED_CS_PROJECT --no-headers --ignore-not-found | wc -l`  >/dev/null 2>&1
        if [ $isProjExists -eq 1 ] ; then
            # If it exists, we will deploy the same ibm-licensing-catalog into cs-control namespace.
            if [[ $machine == "Linux" ]]; then
                TMP_LICENSING_OLM_CATALOG=$(mktemp --suffix=.yaml)
            elif [[ $machine == "Mac" ]]; then
                TMP_LICENSING_OLM_CATALOG=$(mktemp -t licensing_olm_catalog).yaml
            fi
            start_num="# IBM License Manager"
            end_num="interval: 45m"

            reading_section=false

            while IFS= read -r line; do
                if [[ "$line" == *"$start_num"* ]]; then
                    reading_section=true
                fi

                if $reading_section; then
                    echo "$line" >> "$TMP_LICENSING_OLM_CATALOG"
                fi

                if [[ "$line" == *"$end_num"* ]]; then
                    reading_section=false
                fi
            done < "${OLM_CATALOG}"

            # replace openshift-marketplace for ibm-licensing-catalog with cs-control
            ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: \"$DEDICATED_CS_PROJECT\"/;}" ${TMP_LICENSING_OLM_CATALOG}

            ${CLI_CMD} apply -f $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "Create IBM License Manager Catalog source in project \"$DEDICATED_CS_PROJECT\"!"
            else
                echo "Generic Operator catalog source update failed"
                exit 1
            fi
            rm -rf $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
        fi

        sed "s/REPLACE_CATALOG_SOURCE_NAMESPACE/$CATALOG_NAMESPACE/g" ${OLM_CATALOG} > ${OLM_CATALOG_TMP}
        # replace all other catalogs with <BAI NS> namespaces
        ${SED_COMMAND} "s|namespace: .*|namespace: \"$TARGET_PROJECT_NAME\"|g" ${OLM_CATALOG_TMP}
        # replace openshift-marketplace for ibm-cert-manager-catalog with ibm-cert-manager
        ${SED_COMMAND} "/name: ibm-cert-manager-catalog/{n;s/namespace: .*/namespace: $CERT_MANAGER_PROJECT/;}" ${OLM_CATALOG_TMP}
        # replace openshift-marketplace for ibm-licensing-catalog with ibm-licensing
        ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: $LICENSE_MANAGER_PROJECT/;}" ${OLM_CATALOG_TMP}

        # CPFS suggestion to delete the old BTS Catalogs after the new catalog source for BTS is applied. 
        # Saving the name of the current BTS Catalog sources so that it can be deleted once the new catalog sources are applied
        # Any existing bts catalogs in the stream v3-35 must be deleted and only what was applied must be kept
        # To be dynamic this loop will check for any v3-35-1 or v3-35-2 catalog source names and then accordingly remove them.
        # It will not delete any older BTS catalogs like v3-33 or v3-34 
        # Moving forward from the latest refresh of the public 24.0.1 IF002 this BTS catalog will be v3-35 for any catalog source in that stream
        # https://jsw.ibm.com/browse/DBACLD-176790
        pre_upgrade_bts_catalog_names=$(${CLI_CMD} get catalogsource -n "$TARGET_PROJECT_NAME" --no-headers 2>/dev/null | awk '$1 ~ /^ibm-bts-operator-catalog/ { print $1 }')
        pre_upgrade_bts_catalog_names_to_delete=()
        for pre_upgrade_bts_catalog_name in $pre_upgrade_bts_catalog_names; do
            #echo "here catalog ->$pre_upgrade_bts_catalog_name"
            if [[ "$pre_upgrade_bts_catalog_name" == *"ibm-bts-operator-catalog-v3-35"* && "$pre_upgrade_bts_catalog_name" != "ibm-bts-operator-catalog-v3-35" ]]; then
                #echo "addng this to Deleting catalog source: $pre_upgrade_bts_catalog_name"
                pre_upgrade_bts_catalog_names_to_delete+=("$pre_upgrade_bts_catalog_name")
                #${CLI_CMD} delete catalogsource "$pre_upgrade_bts_catalog_name" -n "$TARGET_PROJECT_NAME"
            fi
        done
        if [[ "$PLATFORM_SELECTED" == "other" && "$SCRIPT_MODE" == "dev" ]]; then
            source $BAI_CNCF_FOLDER/bai-utils.sh
            create_all_catalog_sources "$TARGET_PROJECT_NAME" true "$OLM_CATALOG_TMP" "upgrade"
        else
            ${CLI_CMD} apply -f $OLM_CATALOG_TMP
            if [ $? -eq 0 ]; then
                echo "IBM Business Automation Insights Catalog source updated!"
            else
                echo "IBM Business Automation Insights Catalog source update failed"
                exit 1
            fi
        fi

        # Delete BTS catalog sources that are no longer required and would cause problems with upgrade
        # https://jsw.ibm.com/browse/DBACLD-176790
        for cs in "${pre_upgrade_bts_catalog_names_to_delete[@]}"; do
            ${CLI_CMD} delete catalogsource "$cs" -n "$TARGET_PROJECT_NAME"
        done

    else
        TEMP_CATALOG_PROJECT_NAME="openshift-marketplace"
        info "Applying latest BAI Standalone catalog source ..."

        # CPFS suggestion to delete the old BTS Catalogs after the new catalog source for BTS is applied. 
        # Saving the name of the current BTS Catalog sources so that it can be deleted once the new catalog sources are applied
        # Any existing bts catalogs in the stream v3-35 must be deleted and only what was applied must be kept
        # To be dynamic this loop will check for any v3-35-1 or v3-35-2 catalog source names and then accordingly remove them.
        # It will not delete any older BTS catalogs like v3-33 or v3-34 
        # Moving forward from the latest refresh of the public 24.0.1 IF002 this BTS catalog will be v3-35 for any catalog source in that stream
        # https://jsw.ibm.com/browse/DBACLD-176790
        pre_upgrade_bts_catalog_names=$(${CLI_CMD} get catalogsource -n "$TEMP_CATALOG_PROJECT_NAME" --no-headers 2>/dev/null | awk '$1 ~ /^ibm-bts-operator-catalog/ { print $1 }')
        pre_upgrade_bts_catalog_names_to_delete=()
        for pre_upgrade_bts_catalog_name in $pre_upgrade_bts_catalog_names; do
            #echo "here catalog ->$pre_upgrade_bts_catalog_name"
            if [[ "$pre_upgrade_bts_catalog_name" == *"ibm-bts-operator-catalog-v3-35"* && "$pre_upgrade_bts_catalog_name" != "ibm-bts-operator-catalog-v3-35" ]]; then
                #echo "addng this to Deleting catalog source: $pre_upgrade_bts_catalog_name"
                pre_upgrade_bts_catalog_names_to_delete+=("$pre_upgrade_bts_catalog_name")
                #${CLI_CMD} delete catalogsource "$pre_upgrade_bts_catalog_name" -n "$TARGET_PROJECT_NAME"
            fi
        done

        OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
        ${CLI_CMD} apply -f $OLM_CATALOG >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "IBM Business Automation Insights Catalog source updated!"
            exit 1
        fi
        echo "Done!"

        # Delete BTS catalog sources that are no longer required and would cause problems with upgrade
        # https://jsw.ibm.com/browse/DBACLD-176790
        for cs in "${pre_upgrade_bts_catalog_names_to_delete[@]}"; do
            #echo "Deleting catalog source: $cs"
            ${CLI_CMD} delete catalogsource "$cs" -n "$TEMP_CATALOG_PROJECT_NAME"
        done

    fi
}

# Function to check if the newly applied catalog sources are ready
function check_catalog_pod_status(){
    maxRetry=50
    for ((retry=0;retry<=${maxRetry};retry++)); do
        bai_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-bai-operator-catalog -n $TEMP_CATALOG_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        postgresql_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=cloud-native-postgresql-catalog -n $TEMP_CATALOG_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        cs_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=$CS_CATALOG_VERSION -n $TEMP_CATALOG_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
            cert_mgr_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-cert-manager-catalog -n $CERT_MANAGER_PROJECT -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
            license_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-licensing-catalog -n $LICENSE_MANAGER_PROJECT -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        else
            cert_mgr_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-cert-manager-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
            license_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-licensing-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        fi
        if [[ ( -z $cert_mgr_catalog_pod_name) || ( -z $license_catalog_pod_name) || ( -z $cs_catalog_pod_name) || (-z $postgresql_catalog_pod_name) ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                if [[ -z $bai_catalog_pod_name ]]; then
                    warning "Timeout waiting for ibm-bai-operator-catalog catalog pod to be ready in the project \"$TEMP_CATALOG_PROJECT_NAME\""
                elif [[ -z $postgresql_catalog_pod_name ]]; then
                    warning "Timeout waiting for cloud-native-postgresql-catalog catalog pod to be ready in the project \"$TEMP_CATALOG_PROJECT_NAME\""
                elif [[ -z $cs_catalog_pod_name ]]; then
                    warning "Timeout waiting for $CS_CATALOG_VERSION catalog pod to be ready in the project \"$TEMP_CATALOG_PROJECT_NAME\""
                elif [[ -z $cert_mgr_catalog_pod_name ]]; then
                    warning "Timeout waiting for ibm-cert-manager-catalog catalog pod to be ready in the project \"openshift-marketplace\""
                elif [[ -z $license_catalog_pod_name ]]; then
                    warning "Timeout waiting for ibm-licensing-catalog catalog pod to be ready in the project \"openshift-marketplace\""
                fi
                exit 1
            else
                sleep 30
                echo -n "..."
                continue
            fi
        else
            success "Business Automation Insights operator catalog pod is ready in the project \"$TEMP_CATALOG_PROJECT_NAME\"!"
            break
        fi
    done
}

# Function that upgrades the CPFS operator using the setup-singleton script provided by CPFS
# Based on the upgrade mode different parameters
function upgrade_cpfs_operator(){
    if [[ $UPGRADE_MODE == "dedicated2dedicated" && $ENABLE_PRIVATE_CATALOG -eq 1 ]]; then
        # Additionally, we would check if cs-control namespace exists.
        isProjExists=`${CLI_CMD} get project $DEDICATED_CS_PROJECT --no-headers --ignore-not-found | wc -l`  >/dev/null 2>&1
        if [ $isProjExists -eq 1 ] ; then
            # If it exists, we will deploy the same ibm-licensing-catalog into cs-control namespace.
            if [[ $machine == "Linux" ]]; then
                TMP_LICENSING_OLM_CATALOG=$(mktemp --suffix=.yaml)
            elif [[ $machine == "Mac" ]]; then
                TMP_LICENSING_OLM_CATALOG=$(mktemp -t licensing_olm_catalog).yaml
            fi
            start_num="# IBM License Manager"
            end_num="interval: 45m"

            reading_section=false

            while IFS= read -r line; do
                if [[ "$line" == *"$start_num"* ]]; then
                    reading_section=true
                fi

                if $reading_section; then
                    echo "$line" >> "$TMP_LICENSING_OLM_CATALOG"
                fi

                if [[ "$line" == *"$end_num"* ]]; then
                    reading_section=false
                fi
            done < "${OLM_CATALOG}"

            # replace openshift-marketplace for ibm-licensing-catalog with cs-control
            ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: \"$DEDICATED_CS_PROJECT\"/;}" ${TMP_LICENSING_OLM_CATALOG}

            ${CLI_CMD} apply -f $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "Created IBM License Manager Catalog source in project \"$DEDICATED_CS_PROJECT\"!"
            else
                echo "Generic Operator catalog source update failed"
                exit 1
            fi
            rm -rf $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
        fi

        # Upgrading Cert-Manager and Licensing Service
        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --enable-private-catalog --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --enable-private-catalog --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION

        
        if [ $? -ne 0 ]; then
            TMP_MESSAGE="Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --enable-private-catalog --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
            displayUpgradeOperatorMessage "$TMP_MESSAGE" $TARGET_PROJECT_NAME $bai_operator_csv_version
            exit 1
        fi

        # set --service-namespace property to BAI_SERVICES_NS when it's seperation of duty
        if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
            TMP_SERVICES_NAMESPACE=$BAI_SERVICES_NS
        # set --service-namespace property to TARGET_PROJECT_NAME when it's not seperation of duty
        else
            TMP_SERVICES_NAMESPACE=$TARGET_PROJECT_NAME
        fi
        # switch catalog from GCN to private when it's seperation of duty.
        # Upgrading CPFS

        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TMP_SERVICES_NAMESPACE --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1"
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TMP_SERVICES_NAMESPACE --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1

        if [ $? -ne 0 ]; then
            TMP_MESSAGE="Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TMP_SERVICES_NAMESPACE --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1"
            displayUpgradeOperatorMessage "$TMP_MESSAGE" $TARGET_PROJECT_NAME  $bai_operator_csv_version
            exit 1
        fi

    elif [[ $UPGRADE_MODE == "dedicated2dedicated" && $ENABLE_PRIVATE_CATALOG -eq 0 ]]; then
        # Upgrading Cert-Manager and Licensing Service
        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
        if [ $? -ne 0 ]; then
            TMP_MESSAGE="Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
            displayUpgradeOperatorMessage "$TMP_MESSAGE" $TARGET_PROJECT_NAME $bai_operator_csv_version
            exit 1
        fi
        # set --service-namespace property to BAI_SERVICES_NS when it's seperation of duty
        if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
            TMP_SERVICES_NAMESPACE=$BAI_SERVICES_NS
        # set --service-namespace property to TARGET_PROJECT_NAME when it's not seperation of duty
        else
            TMP_SERVICES_NAMESPACE=$TARGET_PROJECT_NAME
        fi
        # keep GCN catalog
        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TMP_SERVICES_NAMESPACE --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TMP_SERVICES_NAMESPACE --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1
        if [ $? -ne 0 ]; then
            TMP_MESSAGE= "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TMP_SERVICES_NAMESPACE --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
            #source ${CUR_DIR}/helper/messages.sh
            displayUpgradeOperatorMessage "$TMP_MESSAGE" $TARGET_PROJECT_NAME $bai_operator_csv_version
            exit 1
        fi

    # Not a scenario currently supported, but code in it for now. 
    elif [[ $UPGRADE_MODE == "shared2shared" && $ALL_NAMESPACE_FLAG == "No" ]]; then
        # Upgrading Cert-Manager and Licensing Service
        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
        if [ $? -ne 0 ]; then
            warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
            echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run the following command to try upgrading again after fixing the migration issue of IBM Cloud Pak foundational services."
            echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
            echo "           Usage:"
            echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services; valid values are [shared2shared/shared2dedicated/dedicated2dedicated]."
            echo "           --original-bai-csv-ver  : The version of the CSV for the BAI operator before the upgrade. For example, use [24.0.1] for 24.0.1-IF001."
            echo "           Example command: "
            echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
            exit 1
        fi
        # keep GCN catalog
        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace ibm-common-services --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace ibm-common-services --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1
        if [ $? -ne 0 ]; then
            warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace ibm-common-services --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
            echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run the following command to try upgrading again after fixing the migration issue of IBM Cloud Pak foundational services."
            echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
            echo "           Usage:"
            echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services; valid values are [shared2shared/shared2dedicated/dedicated2dedicated]."
            echo "           --original-bai-csv-ver  : The version of the CSV for the BAI operator before the upgrade. For example, use [24.0.1] for 24.0.0-IF001."
            echo "           Example command: "
            echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
            exit 1
        fi
    fi
}

# Function that checks if a specific subscription exists
function is_sub_exist() {
    local package_name=$1
    if [ $# -eq 2 ]; then
        local namespace=$2
        local name=$(${CLI_CMD} get subscription.operators.coreos.com -n ${TARGET_PROJECT_NAME} -o yaml -o jsonpath='{.items[*].spec.name}')
    else
        local name=$(${CLI_CMD} get subscription.operators.coreos.com -A -o yaml -o jsonpath='{.items[*].spec.name}')
    fi
    is_exist=$(echo "$name" | grep -w "$package_name")
}

function cncf_wait_for_condition() {
    local condition=$1
    local retries=$2
    local sleep_time=$3
    local wait_message=$4
    local success_message=$5
    local error_message=$6
    local debug_condition=${7:-}

    info "${wait_message}"
    while true; do
        result=$(eval "${condition}")

        if [[ ( ${retries} -eq 0 ) && ( -z "${result}" ) ]]; then
            error "${error_message}"
        fi

        sleep ${sleep_time}
        result=$(eval "${condition}")

        if [[ -z "${result}" ]]; then
            if [[ ! -z "${debug_condition}" ]]; then
                info "${debug_condition} -> \n$(eval "${debug_condition}")\n"
            fi

            info "RETRYING: ${wait_message} (${retries} left)"
            retries=$(( retries - 1 ))
        else
            break
        fi
    done

    if [[ ! -z "${success_message}" ]]; then
        success "${success_message}\n"
    fi
}

function cncf_wait_for_cscr_status(){
    local namespace=$1
    local name=$2
    local condition="${CLI_CMD} -n ${namespace} get commonservice ${name} --no-headers --ignore-not-found -o jsonpath='{.status.phase}' | grep 'Succeeded'"
    local retries=150
    local sleep_time=6
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for CommonService CR ${name} in ${namespace} to be ready"
    local success_message="CommonService CR in ${namespace} is in Succeeded Phase"
    local error_message="Timeout after ${total_time_mins} minutes waiting for CommonService CR in ${namespace} to be ready"

    cncf_wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}"
}

function cncf_wait_for_operator_upgrade() {
    local namespace=$1
    local package_name=$2
    local channel=$3
    local key="${package_name}.${namespace}"
    # k8s label name length limit to 64 characters
    local length_limited_key=$(echo ${key:0:63})
    local condition="${CLI_CMD} get subscription.operators.coreos.com -l operators.coreos.com/${length_limited_key}='' -n ${namespace} -o yaml -o jsonpath='{.items[*].status.installedCSV}' | grep -w $channel"
    local debug_condition="${CLI_CMD} get subscription.operators.coreos.com -l operators.coreos.com/${length_limited_key}='' -n ${namespace} -o jsonpath='{.items[*].status.conditions}'"

    local retries=120
    local sleep_time=20
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for operator ${package_name} to be upgraded"
    local success_message="Operator ${package_name} is upgraded to latest version in channel ${channel}"
    local error_message="Timeout after ${total_time_mins} minutes waiting for operator ${package_name} to be upgraded"

    # if channel is not set, skip the wait
    if [[ "${channel}" == "null" ]]; then
        info "${wait_message}"
        sleep ${sleep_time}
        warning "Channel is not set for operator ${package_name}. Skipping wait for operator upgrade"
        return 0
    fi

    cncf_wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}" "${debug_condition}"
}

function cncf_wait_for_csv() {
    local namespace=$1
    local package_name=$2
    local key="${package_name}.${namespace}"
    local length_limited_key=$(echo ${key:0:63})
    local condition="${CLI_CMD} get subscription.operators.coreos.com -l operators.coreos.com/${length_limited_key}='' -n ${namespace} -o yaml -o jsonpath='{.items[*].status.installedCSV}'"
    local debug_condition="${CLI_CMD} get subscription.operators.coreos.com -l operators.coreos.com/${length_limited_key}='' -n ${namespace} -o jsonpath='{.items[*].status.conditions}'"
    
    local retries=180
    local sleep_time=10
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for operator ${package_name} CSV in namespace ${namespace} to be bound to Subscription"
    local success_message="Operator ${package_name} CSV in namespace ${namespace} is bound to Subscription"
    local error_message="Timeout after ${total_time_mins} minutes waiting for ${package_name} CSV in namespace ${namespace} to be bound to Subscription"

    cncf_wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}" "${debug_condition}"
}

function cncf_wait_for_operator() {
    local namespace=$1
    local operator_name=$2
    local condition="${CLI_CMD} -n ${namespace} get csv --no-headers --ignore-not-found | egrep 'Succeeded' | grep ^${operator_name}"
    local retries=50
    local sleep_time=10
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for operator ${operator_name} in namespace ${namespace} to become available"
    local success_message="Operator ${operator_name} in namespace ${namespace} is available"
    local error_message="Timeout after ${total_time_mins} minutes waiting for ${operator_name} in namespace ${namespace} to become available"

    cncf_wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}"
}

function upgrade_cpfs_operator_on_cncf(){
    local package_name="ibm-common-service-operator"
    is_sub_exist "ibm-common-service-operator" "$TARGET_PROJECT_NAME"
    if [ $? -eq 0 ]; then
        info "There is an ibm-common-service-operator Subscription already\n"
        local key="${package_name}.${TARGET_PROJECT_NAME}"
        # k8s label name length limit to 64 characters
        local length_limited_key=$(echo ${key:0:63})
        local sub_name=$(${CLI_CMD} get subscription.operators.coreos.com -n ${TARGET_PROJECT_NAME} -l operators.coreos.com/${length_limited_key}='' --no-headers | awk '{print $1}')
        ${CLI_CMD} patch subscription.operators.coreos.com $sub_name --type merge -p '{"spec": {"source": "'${CS_CATALOG_VERSION}'"}}' -n $TARGET_PROJECT_NAME
        ${CLI_CMD} patch subscription.operators.coreos.com $sub_name --type merge -p '{"spec": {"channel": "'${CS_CHANNEL_VERSION}'"}}' -n $TARGET_PROJECT_NAME
        cncf_wait_for_operator_upgrade $TARGET_PROJECT_NAME $package_name $CS_CHANNEL_VERSION
        cncf_wait_for_csv "$TARGET_PROJECT_NAME" "ibm-odlm"
        cncf_wait_for_operator "$TARGET_PROJECT_NAME" "operand-deployment-lifecycle-manager"
        cncf_wait_for_cscr_status "$TARGET_PROJECT_NAME" "common-service"
    else
        error " Could not find a ibm-common-service-operator subscription in $TARGET_PROJECT_NAME"
        exit
    fi
    
}

# Function that validates the BAI Standalone CSV version after the operators are upgraded
function validate_csv_version(){
    # Checking BAI operator CSV
    sub_inst_list=$(${CLI_CMD} get subscription.operators.coreos.com -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
    if [[ -z $sub_inst_list ]]; then
        fail "No existing BAI Standalone subscriptions found (version $BAI_CSV_VERSION), exiting ..."
        exit 1
    fi
    sub_array=($sub_inst_list)
    target_csv_version=${BAI_CSV_VERSION//v/}
    for i in ${!sub_array[@]}; do
        if [[ ! -z "${sub_array[i]}" ]]; then
            if [[ ${sub_array[i]} = ibm-bai-insights-engine-operator* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
            info "Checking the channel of subscription '${sub_array[i]}'!"
            currentChannel=$(${CLI_CMD} get subscription.operators.coreos.com ${sub_array[i]} -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.spec.channel}') >/dev/null 2>&1
                if [[ "$currentChannel" == "$BAI_CHANNEL_VERSION" ]];then
                    success "The channel of subscription '${sub_array[i]}' is $currentChannel!"
                    printf "\n"
                    maxRetry=40
                    info "Waiting for the \"${sub_array[i]}\" subscription be upgraded to the ClusterServiceVersions(CSV) \"v$target_csv_version\""
                    for ((retry=0;retry<=${maxRetry};retry++)); do
                        current_version=$(${CLI_CMD} get subscription.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                        installed_version=$(${CLI_CMD} get subscription.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                        if [[ -z $current_version || -z $installed_version ]]; then
                            error "Failed to retrieve installed or current CSV, abort the upgrade procedure. Check the subscription status of ${sub_array[i]}."
                            exit 1
                        fi
                        case "${sub_array[i]}" in
                        "ibm-bai-insights-engine-operator"*)
                            prefix_sub="ibm-bai-insights-engine-operator.v"
                            ;;
                        "ibm-bai-foundation-operator"*)
                            prefix_sub="ibm-bai-foundation-operator.v"
                            ;;
                        esac

                        current_version=${current_version#"$prefix_sub"}
                        installed_version=${installed_version#"$prefix_sub"}
                        if [[ $current_version != $installed_version || $current_version != $target_csv_version || $installed_version != $target_csv_version ]]; then
                            approval_mode=$(${CLI_CMD} get subscription.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o jsonpath={.spec.installPlanApproval})
                            if [[ $approval_mode == "Manual" ]]; then
                                error "${sub_array[i]} subscription is set to Manual Approval mode. Approve the installPlan to proceed with the upgrade."
                                exit 1
                            fi
                            if [[ $retry -eq ${maxRetry} ]]; then
                                warning "Timeout waiting for upgrading \"${sub_array[i]}\" subscription from ${installed_version} to ${target_csv_version} in the project \"$TEMP_OPERATOR_PROJECT_NAME\""
                                break
                            else
                                sleep 10
                                echo -n "..."
                                continue
                            fi
                        else
                            success "ClusterServiceVersions ${installed_version} is now the latest available version in ${currentChannel} channel."
                            break
                        fi
                    done

                else
                    fail "Failed to update the channel of subscription '${sub_array[i]}' to $BAI_CHANNEL_VERSION! exiting now..."
                    exit 1
                fi
            fi
        else
            fail "No subscription found for '${sub_array[i]}'! exiting now..."
            exit 1
        fi
    done
}

function patch_edb_configmap(){
    # DBACLD-166239 -> Update EDB configmap ibm-zen-metastore-edb-cm to add new parameters with CPFS 4.10 or later.
    # During upgrade, we check the existence of the configmap along with these 2 new parameters (DATABASE_ENABLE_SSL and DATABASE_SSL_MODE).
    # If those parameters exists then we will not patch the configmap as the configmap is same for embedded and external postgres.
    # Input:
    #   namespace: The namespace that the configmap is located

    local namespace=$1

    is_edb_missing_ssl_enable_param=$(${CLI_CMD} get configmap ${ZEN_EDB_CFG} -n $namespace -o jsonpath='{.data.DATABASE_ENABLE_SSL}' 2>&1 )
    is_edb_missing_ssl_mode_param=$(${CLI_CMD} get configmap ${ZEN_EDB_CFG} -n $namespace -o jsonpath='{.data.DATABASE_SSL_MODE}' 2>&1 )

    #Patch cm if DATABASE_ENABLE_SSL does not exist
    if [[  -z $is_edb_missing_ssl_enable_param ]]; then
        info "Patching ${ZEN_EDB_CFG} with DATABASE_ENABLE_SSL parameter"
        ${CLI_CMD} patch configmap ${ZEN_EDB_CFG} -n $namespace --type=merge -p '{"data": {"DATABASE_ENABLE_SSL":"'true'"}}'
    fi
    #Patch cm if DATABASE_SSL_MODE does not exist
    if [[  -z $is_edb_missing_ssl_mode_param ]]; then
        info "Patching ${ZEN_EDB_CFG} with DATABASE_SSL_MODE parameter"
        ${CLI_CMD} patch configmap ${ZEN_EDB_CFG} -n $namespace --type=merge -p '{"data": {"DATABASE_SSL_MODE":"require"}}'

    fi
}

# Function to patch the elastic search cluster CR with "quiesce":true which is required before upgrading to opensearch 2.19
# https://jsw.ibm.com/browse/DBACLD-166681
function patch_elasticsearch_cr(){
    local cr_namespace=$1
    elasticsearch_cr_name=$(${CLI_CMD} get ElasticsearchCluster -n $cr_namespace --no-headers --ignore-not-found | awk '{print $1}')
    if [[ -n $elasticsearch_cr_name ]]; then
        info "Patching ElasticsearchCluster $elasticsearch_cr_name in namespace $cr_namespace..."
        ${CLI_CMD} patch ElasticsearchCluster $elasticsearch_cr_name -n $cr_namespace --type=merge -p '{"spec": {"quiesce":true}}'
        printf "\n"
    else
        info " Manually patch the Elasticsearch Cluster by executing \" ${CLI_CMD} patch ElasticsearchCluster $elasticsearch_cr_name -n $cr_namespace --type=merge -p '{\"spec\": {\"quiesce\":true}}' \" "
        printf "\n"
    
    fi
}

function wait_for_csv() {
    MAX_RETRIES=10
    SLEEP_TIME=4
    local expected_csv_name="$1"
    local search_filter="$2"
    local namespace="$3"

    for ((i=1; i<=MAX_RETRIES; i++)); do
        csv_list=$(${CLI_CMD} get csv -n "$namespace" --no-headers --ignore-not-found | grep "$search_filter" | awk '{print $1}')

        if echo "$csv_list" | grep -q "$expected_csv_name"; then
            info "Found '$expected_csv_name' in CSV list."
            return 0
        else
            info "'$expected_csv_name' not found yet. Retrying in $SLEEP_TIME seconds..."
            sleep "$SLEEP_TIME"
        fi
    done

    error "'$expected_csv_name' not found in CSV list after $MAX_RETRIES attempts."
    return 1
}

# Main function used for the upgradeOperator mode
function upgradeoperator_mode(){
    info "Starting to upgrade BAI standalone operators and IBM foundation services"
    # check current bai operator version
    check_bai_operator_version $TARGET_PROJECT_NAME

    #### Seperaration of duties check ####
    # check if the deployment has seperate operators and operands
    check_bai_separate_operand $TARGET_PROJECT_NAME

    # If SEPARATE_OPERAND_FLAG gets set to Yes which happens in the check_bai_separate_operand function in upgrade_check_status.sh , then the variables being set below get set to the appropriate values.
    if [[ $SEPARATE_OPERAND_FLAG == "No" ]]; then

        BAI_SERVICES_NS=$TARGET_PROJECT_NAME
        bai_services_namespace=$TARGET_PROJECT_NAME
        bai_operators_namespace=$TARGET_PROJECT_NAME
        set_upgrade_file_paths $TARGET_PROJECT_NAME #function definition in helper/upgrade/upgrade_check_status.sh

    elif [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
        set_upgrade_file_paths $BAI_SERVICES_NS   #function definition in helper/upgrade/upgrade_check_status.sh
    fi
    #### End of Seperaration of duties check ####

    ##### Definition of ENV variables required for this mode ######
    TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME
    RUN_BAI_SAVEPOINT="No"
    # Sourcing the messages function
    source ${CUR_DIR}/helper/messages.sh

    mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
    mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1

    ##### End of Definition of ENV variables required for this mode ######


    #### Start the upgrade of BAI S Operators and CPFS ####
    info "Starting to upgrade BAI Standalone operators and IBM Cloud Pak foundational services"
    # bai_operator_csv_version is set from the check_bai_operator_version function
    if [[ "$bai_operator_csv_version" == "${BAI_CSV_VERSION//v/}" ]]; then
        warning "The ClusterServiceVersion (CSV) of BAI Standalone operator already is $BAI_CSV_VERSION."
        printf "\n"
        while true; do
            printf "\n"
            printf "\x1B[1mDo you want to continue to do upgrade? (Yes/No, default: No): \x1B[0m"
            read -rp "" ans
            if [[ -z "$ans" ]]; then
                ans="no"
            fi
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                displayUpgradeOperatorMessage '' $TARGET_PROJECT_NAME $cp4a_operator_csv_version
                exit 1
                ;;
            "n"|"N"|"no"|"No"|"NO"|"")
                echo "Exiting..."
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    fi
    PLATFORM_SELECTED=$(eval echo $(${CLI_CMD} get insightsengine $(${CLI_CMD} get insightsengine --no-headers --ignore-not-found -n $BAI_SERVICES_NS | grep NAME -v | awk '{print $1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o yaml | grep sc_deployment_platform | tail -1 | cut -d ':' -f 2))
    if [[ -z $PLATFORM_SELECTED ]]; then
        fail "No custom resource found for BAI Standalone under project \"$BAI_SERVICES_NS\", exiting"
        exit 1
    fi


    ############## Start - Create ibm-bai-shared-info configMap ##############
    check_and_created_sharedinfo_configmap
    ############## End - Create ibm-bai-shared-info configMap ##############


    ############## Start - Decide which CPfs migration mode should be used ##############
    ALL_NAMESPACE_FLAG="No" # no all namespaces support for BAI Standalone
    
    if [[ -z $UPGRADE_MODE ]]; then
        if [[ $ALL_NAMESPACE_FLAG == "Yes" ]]; then
            fail "All Namespaces deployment is not supported for BAI standalone under project \"$TARGET_PROJECT_NAME\", exiting"
            exit 1
        elif [[ $ALL_NAMESPACE_FLAG == "No" ]]; then
            info "IBM Cloud Pak foundational services is working in \"Namespace-scoped\"."
            UPGRADE_MODE="dedicated2dedicated"
        fi
    fi
    # checking existing catalog type
    if ${CLI_CMD} get catalogsource -n openshift-marketplace --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
        CATALOG_FOUND="Yes"
        PINNED="Yes"
    elif ${CLI_CMD} get catalogsource -n openshift-marketplace --no-headers --ignore-not-found | grep ibm-operator-catalog >/dev/null 2>&1; then
        CATALOG_FOUND="Yes"
        PINNED="No"
    else
        CATALOG_FOUND="No"
        PINNED="Yes" # Fresh install use pinned catalog source
    fi
    ############## End - Decide which CPfs migration mode should be used ##############

    ############## Start - Decide which catalog source (GNC/Private) should be used ##############
    get_catalog_type
    ############## End - Decide which catalog source (GNC/Private) should be used ##############

    # Retrieve existing InsightsEngine CR
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')

    if [[ ! -z $insightsengine_cr_name ]]; then
        cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
        ${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

        #convert_olm_cr "${UPGRADE_DEPLOYMENT_BAI_CR_TMP}"
        #if [[ $olm_cr_flag == "No" ]]; then
        #    existing_pattern_list=""
        #    existing_opt_component_list=""
        #    EXISTING_PATTERN_ARR=()
        #    EXISTING_OPT_COMPONENT_ARR=()
        #    existing_pattern_list=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
        #    existing_opt_component_list=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`
        #    OIFS=$IFS
        #    IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
        #    IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
        #    IFS=$OIFS
        #fi
    fi
    
    # Make changes to the elasticsearch CR to support the opensearch version 2.19.0 shipped with BAI Standalone 25.0.0
    patch_elasticsearch_cr "$BAI_SERVICES_NS"
    
    ############## Start - Decide whether to create savepoint for Flink job ##############
    # NOTES: No need to create save point for upgrade IFIX by IFIX
    # Checking CSV for bai-operator to decide whether to do BAI save point during IFIX to IFIX upgrade
    check_subscription

    # No need to create Flink job savepoint for upgrading from IFIX to IFIX
    # For IFIX to IFIX upgrade Save points are created manually and the instructions are documented in each IFIX readme https://jsw.ibm.com/browse/DBACLD-165326
    if [[ "$is_ifix_to_ifix_upgrade" == "false" ]]; then
        # In 24.0.0, follow the flow of migration from  Elasticsearch to Opensearch, the bai savepoint creation already done before upgrade BAI
        # So do not rerun savepoint. But need to covert bai json into UPGRADE_DEPLOYMENT_BAI_TMP for next upgradeDeployment mode.
        # Keep below logic for future IFIX to IFX upgrade.  Setting the RUN_BAI_SAVEPOINT="No" which will skip the savepoint creation in IFIX to IFIX upgrade
        # This section is for normal increment, n-1, upgrade like 24.0.0 to 24.0.1 for BAI.
        if [[ $RUN_BAI_SAVEPOINT == "Yes" ]]; then
            create_bai_savepoints
        fi
    fi
    ############## End - Decide whether to create savepoint for Flink job ##############
    
    ############## Start - Migration CPfs mode and upgrade BAI Standalone Operators ##############
    
    #  Switch BAI Operator to private catalog source
    if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
        switch_to_private_catalog
    fi

    # For CNCF we want to use the functions from the CNCF folder so that we can patch the catalog source for dev mode
    if [[ "$PLATFORM_SELECTED" == "other" ]]; then
        source $BAI_CNCF_FOLDER/bai-utils.sh
        source $BAI_CNCF_FOLDER/bai-install-prereqs.sh
        #apply_new_catalog_sources
        if [[ "$SCRIPT_MODE" == "dev" ]]; then
            create_all_catalog_sources ${BAI_SERVICES_NS} true ${CATALOG_SOURCE_FILENAME} "freshinstall"
        else
            create_all_catalog_sources ${BAI_SERVICES_NS} false ${CATALOG_SOURCE_FILENAME} "freshinstall"
        fi
        # Checking if BAI Standalone catalog source pods are ready
        TEMP_CATALOG_PROJECT_NAME=${BAI_SERVICES_NS}
        info "Checking if the Business Automation Insights operator catalog pod is ready in the namespace \"$TEMP_CATALOG_PROJECT_NAME\""
        check_catalog_pod_status
    fi

    
    #  Patch BAI channel to latest version, wait for all the operators are upgraded before applying operandRequest.
    patch_channel_version

    # For CNCF we want to use the functions from the CNCF folder so that we can patch the catalog source for dev mode
    if [[ "$SCRIPT_MODE" == "dev" ]]; then
        new_insights_csv_name="ibm-bai-insights-engine-operator.$BAI_CSV_VERSION"
        if wait_for_csv "$new_insights_csv_name" "IBM Business Automation Insights" "$TARGET_PROJECT_NAME"; then
            patch_csv "ibm-bai-insights-engine-operator" "$TARGET_PROJECT_NAME"
            sleep 5
        else
            info "Unable to patch $new_insights_csv_name,you must patch it manually"
        fi

        new_foundation_csv_name="ibm-bai-foundation-operator.$BAI_CSV_VERSION"
        if wait_for_csv "$new_foundation_csv_name" "IBM BAI Foundation" "$TARGET_PROJECT_NAME"; then
            patch_csv "ibm-bai-foundation-operator" "$TARGET_PROJECT_NAME"
        else
           info "Unable to patch $new_foundation_csv_name,you must patch it manually"
        fi
    fi

    success "Completed the switch of channels for all subscriptions of BAI Standalone operators"

    if [[ "$PLATFORM_SELECTED" != "other" ]]; then
        ############## BEGIN - Apply new catalog sources for the BAI Standalone Operators ##############
        # Apply the new catalog source and creating new namespaces for cert manager and license manager
        if [[ ($CATALOG_FOUND == "Yes" && $PINNED == "Yes") || $PRIVATE_CATALOG_FOUND == "Yes" ]]; then
        
            apply_new_catalog_sources

            # Checking if BAI Standalone catalog source pods are ready
            info "Checking if the Business Automation Insights operator catalog pod is ready in the namespace \"$TEMP_CATALOG_PROJECT_NAME\""
            check_catalog_pod_status
        else
            fail "IBM Business Automation Insights catalog source not found!"
            exit 1
        fi
    fi
    ############## END - Apply new catalog sources for the BAI Standalone Operators ##############

    # Upgrade BAI Standalone operator
    info "Starting to upgrade IBM Business Automation Insights operator"

    if [[ $UPGRADE_MODE == "dedicated2dedicated"  ]]; then
        cs_service_target_namespace="$TARGET_PROJECT_NAME"
    elif [[ $UPGRADE_MODE == "shared2shared" || $UPGRADE_MODE == "shared2dedicated" ]]; then
        cs_service_target_namespace="ibm-common-services"
    fi

    
    # No longer required to the checks for cloud-native-postgresql/ibm-bts-operator upgrade as CPFS upgrade will handle that, so just setting these variables to yes
    # Check cloud-native-postgresql/ibm-bts-operator
    if [[ $ENABLE_PRIVATE_CATALOG -eq 0 ]]; then
        cloud_native_postgresql_ready="Yes"
        ibm_bts_operator_ready="Yes"
        valid_bai_operator_version=true
        #ibm_bts_operator_flag=$(${CLI_CMD} get subscription.operators.coreos.com ibm-bts-operator --no-headers --ignore-not-found -n $cs_service_target_namespace | wc -l)
    elif [[ $ENABLE_PRIVATE_CATALOG -eq 1 ]]; then
        # For shared2dedicated/dedicated2dedicated enable private catalog, we do not switch common service catalog source in ibm-common-services project.
        ibm_bts_operator_ready="Yes"
        cloud_native_postgresql_ready="Yes"
        valid_bai_operator_version=true
    fi

    

    if [[ "$valid_bai_operator_version" == true && (("$ibm_bts_operator_ready" == "Yes" && "$cloud_native_postgresql_ready" == "Yes" )) ]]; then
        READY_FOR_DIRECT_UPGRADE="Yes"
    else
        READY_FOR_DIRECT_UPGRADE="No"
        fail "Prerequisite for upgrade did not complete, exiting..."
        exit
    fi

    ############## START - upgrading the CPFS operators ##############
    
    # upgrading the CPFS operators
    if [[ $READY_FOR_DIRECT_UPGRADE == "Yes" ]]; then
        info "Prerequisites for upgrade have been completed with no errors, continue..."
        
        info "Starting to upgrade IBM Cloud Pak foundational services to $CS_OPERATOR_VERSION"
        # Check if without option --enable-private-catalog, the catalog is in target project, set the private catalog as default.
        info "Checking if ibm-bai-operator-catalog catalog source is global or private namespace scoped"
        if [[ $ENABLE_PRIVATE_CATALOG -eq 0 ]]; then
            if ${CLI_CMD} get catalogsource -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
                ENABLE_PRIVATE_CATALOG=1
            else
                info "ibm-bai-operator-catalog catalog source is not found under target project \"$TARGET_PROJECT_NAME\""
            fi
        fi
        # For 25.0.0 IF001 , CPFS scripts are not supported on CNCF, hence there is an additional function that will do the required steps
        if [[ "$PLATFORM_SELECTED" == "other" ]]; then
            upgrade_cpfs_operator_on_cncf
        else
            upgrade_cpfs_operator
        fi
        
    fi

    # Check IBM Cloud Pak foundational services Operator $CS_OPERATOR_VERSION
    maxRetry=30
    echo "****************************************************************************"
    info "Checking for IBM Cloud Pak foundational operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o jsonpath='{.status.phase}')
        # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $upgrade_operator_project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine $BAI_RELEASE_BASE")
        if [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
            printf "\n"
            warning "Timeout waiting for IBM Cloud Pak foundational operator to start"
            echo -e "\x1B[1mCheck the status of Pod by issuing the following command:\x1B[0m"
            echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-common-service-operator|awk '{print $1}') -n $TEMP_OPERATOR_PROJECT_NAME"
            printf "\n"
            echo -e "\x1B[1mCheck the status of ReplicaSet by issuing the following command:\x1B[0m"
            echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-common-service-operator|awk '{print $1}') -n $TEMP_OPERATOR_PROJECT_NAME"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            pod_name=$(${CLI_CMD} get pod -l=name=ibm-common-service-operator -n $TEMP_OPERATOR_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
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
    ############## END - upgrading the CPFS operators ##############
    
    # Function to check the csv version after upgrade
    validate_csv_version 
    success "Completed the check for channels of all subscriptions of BAI Standalone operators"

    # DBACLD-166239 -> Update EDB configmap ibm-zen-metastore-edb-cm to add new parameters with CPFS 4.10 or later by calling patch_edb_configmap()
    patch_edb_configmap $BAI_SERVICES_NS

    # For Major release upgrade
    if [[ "$bai_original_csv_ver_for_upgrade_script" != "$BAI_RELEASE_BASE_MAJOR_VERSION"* ]]; then
        printf "\n"
        echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
        step_num=1
        echo "  - STEP ${step_num} ${YELLOW_TEXT}(Optional)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeOperatorStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check whether the upgrade of the IBM Business Automation Insights operator and its dependencies was successful."
        printf "\n"
        step_num=$((step_num + 1))
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeployment -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to upgrade the IBM Business Automation Insights deployment."
        printf "\n"
        step_num=$((step_num + 1))
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check whether the upgrade of the IBM Business Automation Insights deployment was successful."
    # for upgrading IFIX by IFIX
    else
        printf "\n"
        echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
        step_num=1
        echo "  - STEP ${step_num} ${YELLOW_TEXT}(Optional)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeOperatorStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check whether the upgrade of the IBM Business Automation Insights operator and its dependencies was successful."
        printf "\n"
        step_num=$((step_num + 1))
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check whether the upgrade of the IBM Business Automation Insights deployment was successful."
    fi

}
