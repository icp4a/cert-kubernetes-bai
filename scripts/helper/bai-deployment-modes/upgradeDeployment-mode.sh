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


# This file is a helper script used to store all functions that are used by the bai-deployment.sh for the upgradeDeployment mode
# Example : bai-deployment.sh -m upgradeDeployment -n <bai-namespace>


# Function that checks if the customer wants to rerun the upgradeDeployment mode if the CR applied is already is in sync with the upgraded version
function rerun_upgrade_check(){
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $insightsengine_cr_name ]; then
        cr_version=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $project_name -o yaml | ${YQ_CMD} r - spec.appVersion)
        if [[ $cr_version == "${BAI_RELEASE_BASE}" ]]; then
            warning "The release version of insightsengine custom resource \"$insightsengine_cr_name\" is already \"$cr_version\"."
            printf "\n"
            while true; do
                printf "\x1B[1mDo you want to continue running the upgrade? (Yes/No, default: No): \x1B[0m"
                read -rp "" ans
                case "$ans" in
                "y"|"Y"|"yes"|"Yes"|"YES")
                    RERUN_UPGRADE_DEPLOYMENT="Yes"
                    break
                    ;;
                "n"|"N"|"no"|"No"|"NO"|"")
                    echo "Exiting..."
                    exit 1
                    ;;
                *)
                    printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
                    ;;
                esac
            done
        else #DBACLD-160277: Setting the original version of the ICP4ACluster CR to the current version of the content CR
            export original_cr_version=$cr_version
        fi
    fi
}

# This is a Validation Function to do a dry run of applying the CR and if there are any errors it will prompt remediation steps and exit out
function dryrun(){
    FILE=$1
    projectname=$2
    # Run kubectl apply with dry-run
    output=$(${CLI_CMD} apply -f "$FILE" --dry-run=server 2>&1)
    exit_code=$?
    info "Validating the BAI Standalone Custom Resource file by executing a dry run..."
    printf "\n"
    # Check the exit code and output to handle different cases
    if [ $exit_code -eq 0 ]; then
        info "${GREEN_TEXT} The Custom Resource file does not contain any errors.${RESET_TEXT}"
        echo "Done!"
    else
        # Handle specific errors
        if echo "$output" | grep -q "unknown field"; then
            # The sample output of the dry run when there is an unknown/invalid field ends with "strict decoding error: unknown field \"<field_name>\""
            # The sed command first removes the entire output string before and including unknown_field " and then removes everything the next quote it finds,keep only <field_name> to be assigned to the unknownfield variable
            unknownfield=$(echo "$output" | sed 's/.*unknown field "//;s/".*//')
            error "ERROR: Unknown field \"$unknownfield\" found in ${FILE}. Check the field names and values."
        elif echo "$output" | grep -q "error parsing"; then
            error "Error: Error parsing ${FILE}. Fix the YAML syntax for this custom resource file."
        else
            # Handle other errors
            error "Unknown Error found while applying the Custom Resource file."
        fi
        # Display next steps when an error is encountered
        echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
        step_num=1
        printf "\n"
        echo "${YELLOW_TEXT}- Resolve the errors that were discovered earlier by modifying the Custom Resource file \"${FILE}\" .${RESET_TEXT}"
        echo "${YELLOW_TEXT}- If the error is related to an unknown field, remove the unknown field from the Custom Resource file \"${FILE}\" .${RESET_TEXT}"
        echo "${YELLOW_TEXT}- If the error is due to YAML parsing, fix the YAML syntax or indentation of the Custom Resource file \"${FILE}\" .${RESET_TEXT}"
        echo "${YELLOW_TEXT}[NOTE]:${RESET_TEXT} This step will fix the custom resource file errors that were found in the previous executed of the upgradeDeployment mode."
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}:${GREEN_TEXT} # ${CLI_CMD} apply -f ${FILE} -n $projectname${RESET_TEXT}" && step_num=$((step_num + 1))
        printf "\n"
        echo "${YELLOW_TEXT}[NOTE]:${RESET_TEXT} Rerun the script bai-deployent.sh in upgradeDeployment mode to continue with the upgrade of IBM Business Automation Insights Engine deployment."
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeDeployment -n $projectname${RESET_TEXT}"

        printf "\n"
        exit
    fi
}

# This is a function to remove all image tags from a CR
# Called during the upgradeDeployment mode
function remove_image_tags(){
    local CR_FILE=$1
    TAGS_REMOVED="false"
    ## remove all image tags
    # jq -r paths generates all possible paths in a json/yaml as comma seperated lists
    # select(.[-1] == "tag" selects all the paths ending with tag 
    # the map(tostring) | join("/") joins the list into the full path and stores it in the list tag_paths
    # the reason there are two different arrays is because to display the values from the yaml , yq needs the yaml path to be seperated by . but the oc patch command needs the path seperated by /
    tag_paths_display=$(${YQ_CMD} r -j ${CR_FILE} | jq -r 'paths | select(.[-1] == "tag") | map(tostring) | join(".")')
    tag_paths_patch=$(${YQ_CMD} r -j ${CR_FILE} | jq -r 'paths | select(.[-1] == "tag") | map(tostring) | join("/")')
    # Removing tags only if the list is populated
    if [[ -n "$tag_paths_display" ]]; then
        echo "${YELLOW_TEXT}[ATTENTION]: The script detects image tags set in the current version of the Custom Resource file.\n[ATTENTION]: The script will remove the tags in the new version of the Custom Resource file and patch the current Custom Resource by removing those image tags since the tags are old and prevent the operator from deploying the updated software."
        info "The list of image tags that will be removed are listed below :"
        for path in $tag_paths_display; do
            tag_value=$(${YQ_CMD} r ${CR_FILE} "$path")
            # Extract the parent path (all parts except the last)
            parent_path=$(echo "$path" | awk -F'.' '{print substr($0, 1, length($0)-length($NF)-1)}')
            repository_value=$(${YQ_CMD} r ${CR_FILE} "$parent_path.repository")
            info "$repository_value:$tag_value"
        done
        printf "\n"
        prompt_press_any_key_to_continue "to remove the defined image tags from the Custom Resource file..."
        printf "\n"
        # To remove the tags and prevent them from being added back by the last-applied-configuration annotation we need to 
        # 1. Remove it from the CR file that will be applied
        ${SED_COMMAND} "/tag: .*/d" ${CR_FILE}
        TAGS_REMOVED="true"
    fi         
}

# Function to scale down operators before retrieving the CR and making changes
function shutdown_operator(){
    # scale down BAI standalone operators
    local project_name=$1
    info "Scaling down \"IBM BAI standalone Insights Engine\" operator"
    ${CLI_CMD} scale --replicas=0 deployment ibm-bai-insights-engine-operator -n $project_name >&3 2>&3
    sleep 1
    echo "Done!"
    info "Scaling down \"IBM BAI standalone Foundation\" operator"
    ${CLI_CMD} scale --replicas=0 deployment ibm-bai-foundation-operator -n $project_name >&3 2>&3
    sleep 1
    echo "Done!"
}

#Function that applies the changes required for the new network policy design as part of 25.0.0
# 1.Retrieves the existing network policies
# 2.Removes owner references from the network policies and reapplies the modified templates
# 3.Notifies the user about the new flag that will generate new network policy templates after the operator is brought up
# 4.Removes the restricted_internet_access flag as it is no longer supported
# https://jsw.ibm.com/browse/DBACLD-167389
function update_network_policies(){
    local namespace=$1
    local cr_type=$2
    local cr_file=$3
    local netpol_targ_path=${CUR_DIR}/network-policies/${namespace}/templates
    printf "\n"
    echo "${RED_TEXT}[ATTENTION]: ${RESET_TEXT}${YELLOW_TEXT} Starting with 25.0.0, the operator is no longer creating network policies automatically.${RESET_TEXT}"
    echo "${YELLOW_TEXT}In addition, the script will remove the ownerReference of any network policies created by the operators, and save the definition of the network policies to ${RESET_TEXT}${GREEN_TEXT}$netpol_targ_path${RESET_TEXT}."
    echo "${YELLOW_TEXT}The script will not delete any existing network policies. The user is now responsible for maintaining these network policies moving forward.${RESET_TEXT}"
    printf "\n"
    prompt_press_any_key_to_continue
    sh ${CUR_DIR}/bai-network-policies.sh -m retrieveExisting -n $namespace --kind $cr_type
    sh ${CUR_DIR}/bai-network-policies.sh -m removeRef -n $namespace
    printf "\n"
    echo "${YELLOW_TEXT}(Notes: Starting from $BAI_RELEASE_BASE, the IBM BAI standalone Insights Engine operator will no longer install network policies automatically.${RESET_TEXT}"
    echo "However, the script \"bai-network-policies.sh\" is provided as a tool you can optionally use to generate network policy templates which you can review and apply.  If you want to generate network policy templates, then do the following:"
    echo "1. Make sure the flag \"shared_configuration.sc_generate_sample_network_policies\" is set to \"true\" in your custom resource file. (By default, the script will set the sc_generate_sample_network_policies to \"false\" )"
    echo "2. Wait for your deployment complete."
    # Will be adding the KC link after its been created
    echo "3. You can retrieve and apply the network policies by running the bai-network-policies.sh script after the IBM BAI standalone Insights Engine upgrade has been completed ."
    printf "\n"
    prompt_press_any_key_to_continue
    ${YQ_CMD} d -i ${cr_file} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access
    ${YQ_CMD} w -i ${cr_file} spec.shared_configuration.sc_generate_sample_network_policies "false"

}

# Function that does all CR updates required to generate the CR to be applied after upgrade to the new version
function upgrade_deployment(){
    local deployment_project_name=$1
    local operator_project_name=$2
    mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
    # trap 'startup_operator $project_name' EXIT
    shutdown_operator $project_name
    # Retrieve existing ICP4ACluster CR
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $deployment_project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [[ (-z $insightsengine_cr_name) ]]; then
        fail "InsightsEngine custom resource not found in the namespace \"$project_name\""
        exit 1
    fi
    info "Retrieving the existing BAI InsightsEngine (Kind: insightsengine.ibm.com) Custom Resource"
    cr_type="insightsengine"
    cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $deployment_project_name -o yaml | ${YQ_CMD} r - metadata.name)
    cr_version=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $deployment_project_name -o yaml | ${YQ_CMD} r - spec.appVersion)

    ${CLI_CMD} get $cr_type $insightsengine_cr_name -n $deployment_project_name -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    #convert_olm_cr "${UPGRADE_DEPLOYMENT_BAI_CR_TMP}"
    #if [[ $olm_cr_flag == "No" ]]; then
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

    # Backup existing icp4acluster CR
    mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
    ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_CR_BAK}

    info "Merging existing BAI Standalone Custom Resource with new version ($BAI_RELEASE_BASE)"
    
    # Delete unnecessary section in CR
    ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} status
    ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} metadata.creationTimestamp
    ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} metadata.generation
    ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} metadata.resourceVersion
    ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} metadata.uid

    #Validate the CR by performing a dry run
    dryrun $UPGRADE_DEPLOYMENT_BAI_CR_TMP $deployment_project_name
    #applying the latest tmp CR so that we can update the kubectl.kubernetes.io/last-applied-configuration section to include any potential user edits
    ${CLI_CMD} apply -f ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} -n $deployment_project_name >/dev/null 2>&1

    # replace release/appVersion
    ${SED_COMMAND} "s|release: .*|release: ${BAI_RELEASE_BASE}|g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s|appVersion: .*|appVersion: ${BAI_RELEASE_BASE}|g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

    # Change ssl_protocol for PFS required in $CP4BA_RELEASE_BASE release
    # No PFS configuration for BAI S
    #pfs_ssl_protocol=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.pfs_configuration.security.ssl_protocol`
    #if [ ! -z "$pfs_ssl_protocol" ]; then
    #    ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} spec.pfs_configuration.security.ssl_protocol "TLSv1.2"
    #fi


    ${SED_COMMAND} "s/route_reencrypt: .*/route_reencrypt: $ZEN_ROUTE_REENCRYPT/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    # This block of is used to merge the BAI save point into the CR.  It's only executed when it's an n-1 to n upgrade, not ifix to ifix
    # The is_ifix_to_ifix_upgrade is set to false in the determine_type_of_upgrade function.
    # if [[ ! ("$cp4ba_original_csv_ver_for_upgrade_script" == "24.0."*) ]]; then
    # Sourcing upgrade_check_status.sh and calling determine_type_of_upgrade to dertmine the type of upgrade

    info "CR Version: $cr_version"
    determine_type_of_upgrade "$cr_version"
    # Merging in the BAI Flink Savepoints
    # Only executed for the major release upgrade
    if [[ "$is_ifix_to_ifix_upgrade" == "false" ]]; then
        info "Merging Flink job savepoint from \"${UPGRADE_DEPLOYMENT_BAI_TMP}\" into new version of custom resource \"${UPGRADE_DEPLOYMENT_BAI_CR}\"."
        if [ -s ${UPGRADE_DEPLOYMENT_BAI_TMP} ]; then
            ${YQ_CMD} m -i -a -M --overwrite ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_TMP}
            success "Merged Flink job savepoint into new version of custom resource."
        else
            warning "Not found file ${UPGRADE_DEPLOYMENT_BAI_TMP}."
        fi
    fi

    
    # Set sc_restricted_internet_access always "false" in upgrade
    #info "${YELLOW_TEXT}Setting \"shared_configuration.sc_egress_configuration.sc_restricted_internet_access\" to \"false\" while upgrading BAI Standalone deployment, you could change it according to your requirements of security.${RESET_TEXT}"
    #printf "\n"
    #${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access "false"
    # Function that will retrieve the network policies created in 24.0.1 by the operators and remove the references and re-apply them
    # For https://jsw.ibm.com/browse/DBACLD-167387
    update_network_policies $deployment_project_name "InsightsEngine" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

    # Function that retrieves the networktype and network cidr range
    # https://jsw.ibm.com/browse/DBACLD-173602
    retrieve_network_details "upgrade" $deployment_project_name
    
    ${SED_COMMAND} "s|'\"|\"|g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s|\"'|\"|g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

    # convert ssl enable true or false to meet CSV
    ${SED_COMMAND} "s/: \"True\"/: true/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s/: \"False\"/: false/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s/: \"true\"/: true/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s/: \"false\"/: false/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s/: \"Yes\"/: true/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s/: \"yes\"/: true/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s/: \"No\"/: false/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    ${SED_COMMAND} "s/: \"no\"/: false/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
    # Remove all null string
    ${SED_COMMAND} "s/: null/: /g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

    ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_CR}


    #Function to remove the image tags from the CR if present
    remove_image_tags $UPGRADE_DEPLOYMENT_BAI_CR_TMP
    ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_CR}

    if [[ $TAGS_REMOVED == "true" ]]; then
        info "IMAGE TAGS ARE REMOVED FROM THE NEW VERSION OF THE CUSTOM RESOURCE \"${UPGRADE_DEPLOYMENT_BAI_CR}\"."
        printf "\n"
    fi

    success "BAI Standalone Custom Resource File has been updated for release ($BAI_RELEASE_BASE)"
    printf "\n"

}

# Main function that executes the code required for the upgradeDeployment mode
function upgradedeployment_mode() {
    project_name=$TARGET_PROJECT_NAME
    # Check whether the BAI is separation of operators and operands.
    check_bai_separate_operand $TARGET_PROJECT_NAME
    ALL_NAMESPACE_FLAG="No"
    TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME

    # Get value of bai_original_csv_ver_for_upgrade_script from ibm-bai-shared-info
    get_preupgrade_csv_version $BAI_SERVICES_NS

    if [[ "$bai_original_csv_ver_for_upgrade_script" == "$BAI_RELEASE_BASE_MAJOR_VERSION"* ]]; then
        warning "DO NOT NEED to run [upgradeDeployment] mode for upgrading from ${BAI_RELEASE_BASE}GA/${BAI_RELEASE_BASE}.X to ${BAI_RELEASE_BASE}.X"
        echo "Exiting ..."
        exit 1
    fi
    source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh
    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
        set_upgrade_file_paths $BAI_SERVICES_NS #function definition helper/upgrade/upgrade_check_status.sh
    else
        set_upgrade_file_paths $TARGET_PROJECT_NAME #function definition helper/upgrade/upgrade_check_status.sh
    fi

    # Check app version of the CR and ask if the user wants to rerun the upgradeDeployment mode
    rerun_upgrade_check

    # $TARGET_PROJECT_NAME for BAI deployment, $TEMP_OPERATOR_PROJECT_NAME for BAI operators
    upgrade_deployment $BAI_SERVICES_NS $TEMP_OPERATOR_PROJECT_NAME

    
    # Displaying all next actions and tips after executing this mode
    echo "${YELLOW_TEXT}[NEXT ACTION]:${RESET_TEXT}"
    step_num=1
    echo "${YELLOW_TEXT}- After reviewing or modifying the custom resource file \"${UPGRADE_DEPLOYMENT_BAI_CR}\", you need to follow the steps below to upgrade this BAI Standalone deployment.${RESET_TEXT}"
    # As a part of DBACLD-149126 solution we no longer needed the user to patch or annotate the custom resource file
    echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}:${GREEN_TEXT} # ${CLI_CMD} apply -f ${UPGRADE_DEPLOYMENT_BAI_CR} -n $BAI_SERVICES_NS ${RESET_TEXT}"  && step_num=$((step_num + 1))
    printf "\n"

    # Adding a statement to delete the old elastic search CR since we are updating the elastic search CR to switch the quiesce flag from false to true in 24.0.1 to 25.0.0 upgrade
    # https://jsw.ibm.com/browse/DBACLD-166681
    echo "${YELLOW_TEXT}[IMPORTANT]: ${RESET_TEXT}From ($BAI_RELEASE_BASE) ,BAI Standalone will be moving from Opensearch version 2.17.0 (kind: ElasticsearchCluster) to Opensearch version 2.19.x (kind: Cluster). The upgrade process will automatically migrate all the existing indices to new Opensearch version.After the upgrade is completed you must validate and verify all the existing indices are migrated successfully."
    echo "Once you have verified that indices are migrated successfully you may delete the old Opensearch instance (kind: ElasticsearchCluster) by executing \"${GREEN_TEXT} ${CLI_CMD} delete ElasticsearchCluster opensearch -n $BAI_SERVICES_NS ${RESET_TEXT} \" . "
    echo "${YELLOW_TEXT}[NOTE]: ${RESET_TEXT} There will be no functional impact of leaving the old Opensearch  (kind: ElasticsearchCluster) running in the cluster."
    printf "\n"

    echo "${YELLOW_TEXT}- How to check the overall upgrade status for BAI Operators/zenService/IM.${RESET_TEXT}"
    echo "${YELLOW_TEXT}  [TIPS]: ${RESET_TEXT}The [upgradeDeploymentStatus] option will first start the necessary BAI Standalone operators (ibm-bai-insights-engine-operator/ibm-bai-foundation-operator) to upgrade zenService.Once the zenService upgrade is completed , the rest of the BAI Standalone deployment will be upgraded."
    echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}:${GREEN_TEXT} # ./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME${RESET_TEXT}"

    printf "\n"
    echo "${YELLOW_TEXT}[ATTENTION]: The zenService will be ready in about 120 minutes after the new version ($BAI_RELEASE_BASE) of BAI Standalone custom resource is applied.${RESET_TEXT}"
    printf "\n"
    
    
    echo "${YELLOW_TEXT}[TIPS]${RESET_TEXT}"
    echo "* When running the script in [upgradeDeploymentStatus] mode, the script will detect the Zen/IM ready or not."
    echo "* After the Zen/IM is ready, the script will start up all BAI Standalone operators automatically."
    printf "\n"
    echo "If the script runs in [upgradeDeploymentStatus] mode for checking the Zen/IM timeout, you could check status by following the below command."
    msgB "To check zenService version manually: "
    echo "  # ${CLI_CMD} get zenService $(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $BAI_SERVICES_NS |awk '{print $1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.currentVersion}'"
    printf "\n"
    msgB "To check zenService status and progress manually: "
    echo "  # ${CLI_CMD} get zenService $(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $BAI_SERVICES_NS |awk '{print $1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.zenStatus}'"
    echo "  # ${CLI_CMD} get zenService $(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $BAI_SERVICES_NS |awk '{print $1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.progress}'"
}
