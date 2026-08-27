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


# This file is a helper script used to store all functions that are used by the bai-deployment.sh for the upgradeDeploymentStatus mode
# Example : bai-deployment.sh -m upgradeDeploymentStatus -n <bai-namespace>

function upgradedeploymentstatus_mode(){
    #UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/bai-upgrade/project/$TARGET_PROJECT_NAME
    #check_bai_operator_version $TARGET_PROJECT_NAME #function definition helper/upgrade/upgrade_check_status.sh
    check_bai_separate_operand $TARGET_PROJECT_NAME #function definition helper/upgrade/upgrade_check_status.sh
    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
        set_upgrade_file_paths $BAI_SERVICES_NS  #function definition in helper/upgrade/upgrade_check_status.sh
    else
        set_upgrade_file_paths $TARGET_PROJECT_NAME #function definition in helper/upgrade/upgrade_check_status.sh
    fi
    
    project_name=$TARGET_PROJECT_NAME
    
    bai_operator_csv_name_target_ns=$(${CLI_CMD} get csv -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep "IBM Business Automation Insights" | awk '{print $1}')
    if [[ (! -z $bai_operator_csv_name_target_ns) ]]; then
        success "Found IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        ALL_NAMESPACE_FLAG="No"
        TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME
    else
        fail "Failed to Find IBM Cloud Pak for Business Automation Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        exit
    fi
    # Get value of bai_original_csv_ver_for_upgrade_script from the ibm-bai-shared-info
    get_preupgrade_csv_version $BAI_SERVICES_NS

    # Scaling up the BAI Standalone operator and BAI Foundation operator
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $insightsengine_cr_name ]; then
        info "Scaling up \"IBM Business Automation Insights \" operator"
        ${CLI_CMD} scale --replicas=1 deployment ibm-bai-insights-engine-operator -n $TEMP_OPERATOR_PROJECT_NAME >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            sleep 1
        else
            fail "Failed to scale up \"IBM Business Automation Insights (BAI)\" operator"
        fi

        info "Scaling up \"IBM Business Automation Insights Foundation\" operator"
        ${CLI_CMD} scale --replicas=1 deployment ibm-bai-foundation-operator -n $TEMP_OPERATOR_PROJECT_NAME >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            sleep 1
        else
            fail "Failed to scale up \"IBM Business Automation Insights (BAI) Foundation\" operator"
        fi

        cr_version=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - spec.appVersion)
        if [[ $cr_version != "${BAI_RELEASE_BASE}" ]]; then
            fail "The release version: \"$cr_version\" in insightsengine custom resource \"$insightsengine_cr_name\" is not correct, apply new version of the custom resource file first."
            exit 1
        fi
    fi

    # The control variable used to detect if the strimzi patch function has to be executed.
    strimzi_patched=false

    ################## Start - Apply CPFS 4.19.2 operandConfig WORKAROUND ####################
    # WORKAROUND: https://jsw.ibm.com/browse/DBACLD-251442
    # Applied once at the start of upgradeDeploymentStatus to unblock zenService if it is stuck
    # due to the common-service-db PostgreSQL Cluster resource referencing an invalid imageCatalogRef.
    # Patches operandConfig 'common-service': removes .data.spec.imageCatalogRef and pins
    # .data.spec.imageName to the correct digest on the postgresql-operator / common-service-db entry.
    # Remove once the CPFS team ships an official fix.
    # NOTE: uses yq v3 d|w pipe syntax — this repo bundles yq v3, not v4.
    cpfs_services_ns="$BAI_SERVICES_NS"
    info "Applying CPFS 4.19.2 workaround: patching operandConfig 'common-service' in namespace \"$cpfs_services_ns\""
    if ${CLI_CMD} get operandconfig common-service -n "$cpfs_services_ns" --no-headers --ignore-not-found >&3 2>&3; then
        _cpfs_patched=$(${CLI_CMD} get operandconfig common-service -n "$cpfs_services_ns" -o yaml 2>&3 | \
          ${YQ_CMD} d - 'spec.services.(name==common-service-cnpg).resources.(name==common-service-db).data.spec.imageCatalogRef' | \
          ${YQ_CMD} w - 'spec.services.(name==common-service-cnpg).resources.(name==common-service-db).data.spec.imageName' \
            'icr.io/cpopen/ibm-pg/ibm-pg-16:16.14-v28.4.0@sha256:cd1fd631b3e20141cbd462cdd713bee9e2b062472b674fd20ee4c64f923c5cbf')
        if echo "$_cpfs_patched" | grep -q 'apiVersion:'; then
            echo "$_cpfs_patched" | ${CLI_CMD} apply -f - >&3 2>&3
            if [[ $? -eq 0 ]]; then
                success "Successfully applied CPFS 4.19.2 workaround to operandConfig 'common-service' in namespace \"$cpfs_services_ns\""
            else
                warning "Failed to patch operandConfig 'common-service' in namespace \"$cpfs_services_ns\" — apply the following command manually:"
                echo "  ${CLI_CMD} get operandconfig common-service -n $cpfs_services_ns -o yaml | ${YQ_CMD} d - 'spec.services.(name==common-service-cnpg).resources.(name==common-service-db).data.spec.imageCatalogRef' | ${YQ_CMD} w - 'spec.services.(name==common-service-cnpg).resources.(name==common-service-db).data.spec.imageName' 'icr.io/cpopen/ibm-pg/ibm-pg-16:16.14-v28.4.0@sha256:cd1fd631b3e20141cbd462cdd713bee9e2b062472b674fd20ee4c64f923c5cbf' | ${CLI_CMD} apply -f -"
            fi
        else
            warning "Could not read operandConfig 'common-service' from namespace \"$cpfs_services_ns\" — skipping CPFS 4.19.2 workaround."
        fi
    else
        info "operandConfig 'common-service' not found in namespace \"$cpfs_services_ns\" — skipping CPFS 4.19.2 workaround."
    fi
    ################## End - Apply CPFS 4.19.2 operandConfig WORKAROUND ####################

    # check for zenStatus and currentverison for zen

    zen_service_name=$(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $BAI_SERVICES_NS |awk '{print $1}')
    if [[ ! -z "$zen_service_name" ]]; then
        clear
        maxRetry=360
        for ((retry=0;retry<=${maxRetry};retry++)); do
            # # As workaround for https://github.ibm.com/IBMPrivateCloud/roadmap/issues/64207
            # # update secret postgresql-operator-controller-manager-config in <bai> namespace and/or ibm-common-services namespace and add this annotation ibm-bts/skip-updates: "true"
            # if ${CLI_CMD} get secret -n $BAI_SERVICES_NS --no-headers --ignore-not-found | grep postgresql-operator-controller-manager-config >/dev/null 2>&1; then
            #     ${CLI_CMD} patch secret postgresql-operator-controller-manager-config -n $BAI_SERVICES_NS -p '{"metadata": {"annotations": {"ibm-bts/skip-updates": "true"}}}' >/dev/null 2>&1
            # fi

            zenservice_version=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.currentVersion}')
            isCompleted=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.zenStatus}')
            # DBACLD-165802:Updated zenService check from "Progress" to "progress" for CPFS 4.10 and above.
            isProgressDone=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.progress}')

            if [[ "$isCompleted" != "Completed" || "$isProgressDone" != "100%" || "$zenservice_version" != "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                clear
                BAI_DEPLOYMENT_STATUS="Waiting for the zenService to be ready (could take up to 120 minutes) before upgrade the BAI Standalone capabilities..."
                printf '%s %s\n' "$(date)" "[refresh interval: 60s]"
                printf '%b' "[Press Ctrl+C to exit] \t\t"
                printf "\n"
                echo "${YELLOW_TEXT}$BAI_DEPLOYMENT_STATUS${RESET_TEXT}"
                printHeaderMessage "BAI Standalone Upgrade Status"
                if [[ "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Version (Expected - ${ZEN_OPERATOR_VERSION//v/})       : ${GREEN_TEXT}$zenservice_version${RESET_TEXT}"
                else
                    echo "zenService Version (Expected - ${ZEN_OPERATOR_VERSION//v/})       : ${RED_TEXT}$zenservice_version${RESET_TEXT}"
                fi
                if [[ "$isCompleted" == "Completed" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Status (Expected - Completed)    : ${GREEN_TEXT}$isCompleted${RESET_TEXT}"
                else
                    echo "zenService Status (Expected - Completed)    : ${RED_TEXT}$isCompleted${RESET_TEXT}"
                fi

                if [[ "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Progress (Expected - 100%)       : ${GREEN_TEXT}$isProgressDone${RESET_TEXT}"
                else
                    echo "zenService Progress (Expected - 100%)       : ${RED_TEXT}$isProgressDone${RESET_TEXT}"
                fi
                sleep 60
            elif [[ "$isCompleted" == "Completed" && "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                break
            elif [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for the Zen Service to start"
                printf '%b\n' "\x1B[1mCheck the status of the Zen Service\x1B[0m"
                printf "\n"
                exit 1
            fi
        done
        BAI_DEPLOYMENT_STATUS="The Zen Service (${ZEN_OPERATOR_VERSION//v/}) is ready for BAI Standalone"
        printf '%s %s\n' "$(date)" "[refresh interval: 30s]"
        printf '%b' "[Press Ctrl+C to exit] \t\t"
        printf "\n"
        echo "${YELLOW_TEXT}$BAI_DEPLOYMENT_STATUS${RESET_TEXT}"
        info "Starting all BAI Standalone Operators to upgrade BAI Standalone capabilities"
        printHeaderMessage "BAI Standalone Upgrade Status"
        if [[ "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
            echo "zenService Version        : ${GREEN_TEXT}$zenservice_version${RESET_TEXT}"
        else
            echo "zenService Version        : ${RED_TEXT}$zenservice_version${RESET_TEXT}"
        fi
        if [[ "$isCompleted" == "Completed" ]]; then
            echo "zenService Status         : ${GREEN_TEXT}$isCompleted${RESET_TEXT}"
        else
            echo "zenService Status         : ${RED_TEXT}$isCompleted${RESET_TEXT}"
        fi

        if [[ "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
            echo "zenService Progress       : ${GREEN_TEXT}$isProgressDone${RESET_TEXT}"
        else
            echo "zenService Progress       : ${RED_TEXT}$isProgressDone${RESET_TEXT}"
        fi

    else
        fail "ZenService not found in the project \"$BAI_SERVICES_NS\", exiting..."
        echo "****************************************************************************"
        exit 1
    fi

    while true
    do
        # Each refresh of the zen upgrade , we check if we need to update the kafka strimzi podset
        # The function patch_strimzi_podset which is defined in common.sh will set strimzi_patched  to true once the patch is completed
        # For upgrades to 24.0.1 or newer, kafka tasks in the foundation-operator happen after zen is upgraded so this block is after zen upgrade completes
        # For upgrades to 24.0.0, kafka tasks in the foundation-operator happen before zen is upgraded
        if [[ $strimzi_patched == "false" ]]; then
            patch_strimzi_podset $bai_operators_namespace $bai_services_namespace
        fi
        printf '%s\n' "$(show_bai_upgrade_status)"
        sleep 30
    done
}