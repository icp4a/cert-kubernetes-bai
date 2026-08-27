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


# This file is a helper script used to store all functions that are used by the bai-deployment.sh for the upgradeOperatorStatus mode
# Example : bai-deployment.sh -m upgradeOperatorStatus -n <bai-namespace>


# Main function that executes the upgradeOperatorStatus Mode
function upgradeoperatorstatus_mode(){
    project_name=$TARGET_PROJECT_NAME
    info "Checking if the BAI standalone operators upgrade is completed..."
    #check_bai_operator_version $TARGET_PROJECT_NAME #function definition helper/upgrade/upgrade_check_status.sh
    check_bai_separate_operand $TARGET_PROJECT_NAME #function definition helper/upgrade/upgrade_check_status.sh
    
    #UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/bai-upgrade/project/$BAI_SERVICES_NS
    #UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
    #UPGRADE_DEPLOYMENT_BAI_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.insightsengine_tmp.yaml
    #source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh
    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
        set_upgrade_file_paths $BAI_SERVICES_NS  #function definition in helper/upgrade/upgrade_check_status.sh
    else
        set_upgrade_file_paths $TARGET_PROJECT_NAME #function definition in helper/upgrade/upgrade_check_status.sh
    fi
     mkdir -p $UPGRADE_DEPLOYMENT_CR >/dev/null 2>&1
    
    bai_operator_csv_name_target_ns=$(${CLI_CMD} get csv -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep "IBM Business Automation Insights" | awk '{print $1}')
    if [[ (! -z $bai_operator_csv_name_target_ns) ]]; then
        success "Found IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        ALL_NAMESPACE_FLAG="No"
        TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME
    else
        fail "Failed to find IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        exit
    fi

    # Get value of bai_original_csv_ver_for_upgrade_script from the ibm-bai-shared-info
    get_preupgrade_csv_version $BAI_SERVICES_NS

    # Check if the insightsengine CR is present
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
    if [[ ! -z $insightsengine_cr_name ]]; then
        cr_type="insightsengine"
        bai_cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
        ${CLI_CMD} get $cr_type $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

        #bai_root_ca_secret_name=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.root_ca_secret`
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
    fi
    if [[ -z $insightsengine_cr_name ]]; then
        fail "No custom resource found for BAI Standalone under the project \"$BAI_SERVICES_NS\"."
        exit 1
    fi

    info "Checking if the BAI standalone operators upgrade is completed..."
    check_operator_status $TARGET_PROJECT_NAME "full" "channel"

    # Display next steps to the user based on the type of upgrade and if the upgrade passed
    if [[ " ${CHECK_BAI_OPERATOR_RESULT[@]} " =~ "FAIL" ]]; then
        fail "Failed to upgrade BAI standalone operators"
    else
        # For Major release upgrade
        if [[ "$bai_original_csv_ver_for_upgrade_script" != "$BAI_RELEASE_BASE_MAJOR_VERSION"* ]]; then
            success "Business Automation Insights operators upgraded successfully!"
            printf "\n"
            echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
            step_num=1
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeployment -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to upgrade the IBM Business Automation Insights deployment."
            printf "\n"
            step_num=$((step_num + 1))
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check that the upgrade of the IBM Business Automation Insights deployment is successful."
        # for upgrading IFIX by IFIX
        else
            success "Business Automation Insights operators upgraded successfully!"
            printf "\n"
            echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}: "
            printf "\n"
            echo "${YELLOW_TEXT}* Run the script in [upgradeDeploymentStatus] mode directly to upgrade BAI standalone from $BAI_RELEASE_BASE IFix to IFix.${RESET_TEXT}"
            echo "${GREEN_TEXT}# ./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME${RESET_TEXT}"
        fi
        
    fi
}