# Directory for upgrade deployment for CP4BA multiple deployment
UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/bai-upgrade/project/$1
UPGRADE_DEPLOYMENT_PROPERTY_FILE=${UPGRADE_DEPLOYMENT_FOLDER}/bai_upgrade.property

UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
UPGRADE_DEPLOYMENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR}/backup

UPGRADE_DEPLOYMENT_BAI_CR=${UPGRADE_DEPLOYMENT_CR}/insightsengine.yaml
UPGRADE_DEPLOYMENT_BAI_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.insightsengine_tmp.yaml
UPGRADE_DEPLOYMENT_BAI_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/insightsengine_cr_backup.yaml

UPGRADE_CS_ZEN_FILE=${UPGRADE_DEPLOYMENT_CR}/.cs_zen_parameter.yaml
UPGRADE_DEPLOYMENT_BAI_TMP=${UPGRADE_DEPLOYMENT_CR}/.bai_tmp.yaml

UPGRADE_BAI_SHARED_INFO_CM_FILE=${UPGRADE_DEPLOYMENT_CR}/ibm_bai_shared_info.yaml


#Function to create the bai shared info Configmap
function create_ibm_bai_shared_info_cm_yaml(){
    mkdir -p ${UPGRADE_DEPLOYMENT_CR}
cat << EOF > ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
kind: ConfigMap
apiVersion: v1
metadata:
  name: ibm-bai-shared-info
  namespace: <bai_namespace>
  labels:
    app.kubernetes.io/managed-by: Operator
    app.kubernetes.io/name: ibm-bai-shared-info
    app.kubernetes.io/version: <cr_version>
    release: <cr_version>
  ownerReferences:
    - apiVersion: bai.ibm.com/v1
      kind: InsightsEngine
      name: <cr_metaname>
      uid: <cr_uid>
data:
  bai_operator_of_last_reconcile: <csv_version>
EOF
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
        read -rsn1 -p "Press any key to continue to remove the defined image tags from the Custom Resource file...";echo
        printf "\n"
        # To remove the tags and prevent them from being added back by the last-applied-configuration annotation we need to 
        # 1. Remove it from the CR file that will be applied
        ${SED_COMMAND} "/tag: .*/d" ${CR_FILE}
        TAGS_REMOVED="true"
    fi         
}

function convert_olm_cr(){
    local cr_file=$1
    EXISTING_PATTERN_ARR=()
    EXISTING_OPT_COMPONENT_ARR=()
    # check the cr is olm format or not
    olm_cr_flag=`cat $cr_file | ${YQ_CMD} r - spec.olm_ibm_license`
    if [[ ! -z $olm_cr_flag ]]; then
        olm_cr_flag="Yes"

        local OLM_PATTERN_CR_MAPPING=("spec.olm_production_content"
                                "spec.olm_production_application"
                                "spec.olm_production_decisions"
                                "spec.olm_production_decisions_ads"
                                "spec.olm_production_document_processing"
                                "spec.olm_production_workflow"
                                "spec.olm_production_workflow_process_service")
        local SCRIPT_PATTERN_CR_MAPPING=("content"
                                "application"
                                "decisions"
                                "decisions_ads"
                                "document_processing"
                                "workflow"
                                "workflow-process-service")


        for i in "${!OLM_PATTERN_CR_MAPPING[@]}"; do
            # echo "Element $i: ${OLM_PATTERN_CR_MAPPING[$i]}"
            olm_pattern_flag=`cat $cr_file | ${YQ_CMD} r - ${OLM_PATTERN_CR_MAPPING[$i]}`
            if [[ $olm_pattern_flag == "true" ]]; then
                EXISTING_PATTERN_ARR=( "${EXISTING_PATTERN_ARR[@]}" "${SCRIPT_PATTERN_CR_MAPPING[$i]}" )
                if [[ ${SCRIPT_PATTERN_CR_MAPPING[$i]} == "workflow" ]]; then
                    olm_pattern_flag=`cat $cr_file | ${YQ_CMD} r - spec.olm_production_workflow_deploy_type`
                    EXISTING_PATTERN_ARR=( "${EXISTING_PATTERN_ARR[@]}" "$olm_pattern_flag" )
                    if [[ $olm_pattern_flag == "workflow_authoring" ]]; then
                        EXISTING_OPT_COMPONENT_ARR=( "${EXISTING_OPT_COMPONENT_ARR[@]}" "baw_authoring" )
                    fi
                fi
                if [[ ${SCRIPT_PATTERN_CR_MAPPING[$i]} == "document_processing" ]]; then
                    olm_pattern_flag=`cat $cr_file | ${YQ_CMD} r - spec.olm_production_option.adp.document_processing_runtime`
                    if [[ $olm_pattern_flag == "true" ]]; then
                        EXISTING_PATTERN_ARR=( "${EXISTING_PATTERN_ARR[@]}" "document_processing_runtime" )
                    elif [[ $olm_pattern_flag == "false" ]]; then
                        EXISTING_PATTERN_ARR=( "${EXISTING_PATTERN_ARR[@]}" "document_processing_designer" )
                    fi
                fi
            elif [[ -z $olm_pattern_flag ]]; then
                ${YQ_CMD} w -i ${cr_file} ${OLM_PATTERN_CR_MAPPING[$i]} "false"
            fi
        done

        local OLM_OPTIONAL_COMPONENT_CR_MAPPING=("spec.olm_production_option.adp.cmis"
                                                "spec.olm_production_option.adp.css"
                                                "spec.olm_production_option.adp.document_processing_runtime"
                                                "spec.olm_production_option.adp.es"
                                                "spec.olm_production_option.adp.tm"

                                                "spec.olm_production_option.ads.ads_designer"
                                                "spec.olm_production_option.ads.ads_runtime"
                                                "spec.olm_production_option.ads.bai"

                                                "spec.olm_production_option.application.app_designer"
                                                "spec.olm_production_option.application.ae_data_persistence"

                                                "spec.olm_production_option.content.bai"
                                                "spec.olm_production_option.content.cmis"
                                                "spec.olm_production_option.content.css"
                                                "spec.olm_production_option.content.es"
                                                "spec.olm_production_option.content.iccsap"
                                                "spec.olm_production_option.content.ier"
                                                "spec.olm_production_option.content.tm"

                                                "spec.olm_production_option.decisions.decisionCenter"
                                                "spec.olm_production_option.decisions.decisionRunner"
                                                "spec.olm_production_option.decisions.decisionServerRuntime"
                                                "spec.olm_production_option.decisions.bai"

                                                "spec.olm_production_option.wfps_authoring.bai"
                                                "spec.olm_production_option.wfps_authoring.pfs"
                                                "spec.olm_production_option.wfps_authoring.kafka"

                                                "spec.olm_production_option.workfow_authoring.bai"
                                                "spec.olm_production_option.workfow_authoring.pfs"
                                                "spec.olm_production_option.workfow_authoring.kafka"
                                                "spec.olm_production_option.workfow_authoring.ae_data_persistence"

                                                "spec.olm_production_option.workfow_runtime.bai"
                                                "spec.olm_production_option.workfow_runtime.kafka"
                                                "spec.olm_production_option.workfow_runtime.opensearch"
                                                "spec.olm_production_option.workfow_runtime.elasticsearch")
        for i in "${!OLM_OPTIONAL_COMPONENT_CR_MAPPING[@]}"; do
            # echo "Element $i: ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}"

            # migration from elasticsearch to opensearch in workflow_runtime
            if [[ ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]} == "spec.olm_production_option.workfow_runtime.elasticsearch" ]]; then
                olm_optional_component_flag=`cat $cr_file | ${YQ_CMD} r - ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}`
                if [[ $olm_optional_component_flag == "true" ]]; then
                    ${YQ_CMD} w -i ${cr_file} spec.olm_production_option.workfow_runtime.opensearch "true"
                elif [[ $olm_optional_component_flag == "false" ]]; then
                    ${YQ_CMD} w -i ${cr_file} spec.olm_production_option.workfow_runtime.opensearch "false"
                elif [[ -z $olm_optional_component_flag ]]; then
                    olm_workflow_runtime_flag=`cat $cr_file | ${YQ_CMD} r - spec.olm_production_workflow_deploy_type`
                    if [[ $olm_workflow_runtime_flag == "workflow_runtime" ]]; then
                        ${YQ_CMD} w -i ${cr_file} spec.olm_production_option.workfow_runtime.opensearch "true"
                    fi
                fi
                ${YQ_CMD} d -i $cr_file ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}
            fi

            # PFS is requird from 21.0.3/22.0.2 to 24.0.0 for workflow_authoring
            if [[ ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]} == "spec.olm_production_option.workfow_authoring.pfs" ]]; then
                olm_optional_component_flag=`cat $cr_file | ${YQ_CMD} r - ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}`
                if [[ $olm_optional_component_flag == "true" ]]; then
                    ${YQ_CMD} w -i ${cr_file} spec.olm_production_option.workfow_authoring.pfs "true"
                elif [[ $olm_optional_component_flag == "false" ]]; then
                    ${YQ_CMD} w -i ${cr_file} spec.olm_production_option.workfow_authoring.pfs "false"
                elif [[ -z $olm_optional_component_flag ]]; then
                    olm_workfow_authoring_flag=`cat $cr_file | ${YQ_CMD} r - spec.olm_production_workflow_deploy_type`
                    if [[ $olm_workfow_authoring_flag == "workflow_authoring" ]]; then
                        ${YQ_CMD} w -i ${cr_file} spec.olm_production_option.workfow_authoring.pfs "true"
                    fi
                fi
            fi

            # remove ae_data_persistence and enable olm_production_application
            if [[ ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]} == "spec.olm_production_option.workfow_authoring.ae_data_persistence" ]]; then
                olm_optional_component_flag=`cat $cr_file | ${YQ_CMD} r - ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}`
                if [[ $olm_optional_component_flag == "true" ]]; then
                    ${YQ_CMD} w -i ${cr_file} spec.olm_production_application "true"
                    ${YQ_CMD} w -i ${cr_file} spec.olm_production_option.application.ae_data_persistence "true"
                fi
                ${YQ_CMD} d -i $cr_file ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}
            fi

            olm_optional_component_flag=`cat $cr_file | ${YQ_CMD} r - ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}`
            if [[ $olm_optional_component_flag == "true" ]]; then
                OIFS=$IFS
                IFS='.' read -r -a array <<< "${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]}"
                last_element="${array[-1]}"
                EXISTING_OPT_COMPONENT_ARR=( "${EXISTING_OPT_COMPONENT_ARR[@]}" "$last_element" )
                IFS=$OIFS
            elif [[ -z $olm_pattern_flag && ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]} != "spec.olm_production_option.workfow_authoring.ae_data_persistence" && ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]} != "spec.olm_production_option.workfow_runtime.elasticsearch" ]]; then
                ${YQ_CMD} w -i ${cr_file} ${OLM_OPTIONAL_COMPONENT_CR_MAPPING[$i]} "false"
            fi
        done

        # remove duplicate element
        UNIQUE_COMPONENTS=$(printf "%s\n" "${EXISTING_OPT_COMPONENT_ARR[@]}" | sort -u)
        EXISTING_OPT_COMPONENT_ARR=($UNIQUE_COMPONENTS)

        # echo "EXISTING_PATTERN_ARR: ${EXISTING_PATTERN_ARR[*]}"
        # echo "EXISTING_OPT_COMPONENT_ARR: ${EXISTING_OPT_COMPONENT_ARR[*]}"
    else
        olm_cr_flag="No"
    fi
}

function create_upgrade_property(){

    mkdir -p ${UPGRADE_DEPLOYMENT_FOLDER}

cat << EOF > ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}
##############################################################################
## The property is for ZenService customize configuration used by Common Services $CS_OPERATOR_VERSION
##############################################################################

## The value for CS_OPERATOR_NAMESPACE/CS_SERVICES_NAMESPACE fill in by script.
## The value will be inserted into ibm-cp4ba-common-config configMap for upgrade CP4BA deployment automatically.
## kind: ConfigMap
## apiVersion: v1
## metadata:
##   name: ibm-cp4ba-common-config
##   namespace: <cp4ba-namespace>
## data:
##   operator_namespace: "<commonservice-operator-namespace>"
##   services_namespace: "<commonservice-namespace>"

## The namespace for Common Service Operator $CS_OPERATOR_VERSION
CS_OPERATOR_NAMESPACE=""

## The namespace for Common Service $CS_OPERATOR_VERSION
CS_SERVICES_NAMESPACE=""
EOF
  create_zen_yaml
  success "Created BAI Standalone upgrade property file\n"

}

function create_zen_yaml(){
    mkdir -p ${UPGRADE_DEPLOYMENT_CR}
cat << EOF > ${UPGRADE_CS_ZEN_FILE}
spec:
  shared_configuration:
    sc_common_service:
      ## common service operator namespace for CS4.0
      operator_namespace: ""
      ## common service service namespace for CS4.0
      services_namespace: ""
EOF
}

# This is a Validation Function to do a dry run of applying the CR and if there are any errors it will prompt remediation steps and exit out
function dryrun(){
    FILE=$1
    projectname=$2
    # Run kubectl apply with dry-run
    output=$(kubectl apply -f "$FILE" --dry-run=server 2>&1)
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
            error "ERROR: Unknown field \"$unknownfield\" found in ${FILE}. Please check the field names and values."
        elif echo "$output" | grep -q "error parsing"; then
            error "Error: Error parsing ${FILE}. Please fix the YAML syntax for this custom resource file."
        else
            # Handle other errors
            error "Unknown Error found while applying the Custom Resource file."
        fi
        # Display next steps when an error is encountered
        echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
        step_num=1
        printf "\n"
        echo "${YELLOW_TEXT}- Resolve the errors that were discovered earlier by modifying the Custom Resource file \"${FILE}\" .${RESET_TEXT}"
        echo "${YELLOW_TEXT}- If the error is related to an unknown field, please remove the unknown field from the Custom Resource file \"${FILE}\" .${RESET_TEXT}"
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

function upgrade_deployment(){
    local deployment_project_name=$1
    local operator_project_name=$2
    mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
    # trap 'startup_operator $project_name' EXIT
    shutdown_operator $project_name
    source ${CUR_DIR}/helper/upgrade/upgrade_check_status.sh
    # Retrieve existing ICP4ACluster CR
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $deployment_project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $insightsengine_cr_name ]; then
        info "Retrieving the existing BAI InsightsEngine (Kind: insightsengine.ibm.com) Custom Resource"
        cr_type="insightsengine"
        cr_metaname=$(kubectl get insightsengine $insightsengine_cr_name -n $deployment_project_name -o yaml | ${YQ_CMD} r - metadata.name)
        cr_version=$(kubectl get insightsengine $insightsengine_cr_name -n $deployment_project_name -o yaml | ${YQ_CMD} r - spec.appVersion)

        ${CLI_CMD} get $cr_type $insightsengine_cr_name -n $deployment_project_name -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
        convert_olm_cr "${UPGRADE_DEPLOYMENT_BAI_CR_TMP}"
        if [[ $olm_cr_flag == "No" ]]; then
            existing_pattern_list=""
            existing_opt_component_list=""

            EXISTING_PATTERN_ARR=()
            EXISTING_OPT_COMPONENT_ARR=()
            existing_pattern_list=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
            existing_opt_component_list=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`

            OIFS=$IFS
            IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
            IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
            IFS=$OIFS
        fi

        # # Check if the cp-console-iam-provider/cp-console-iam-idmgmt already created before upgrade CP4BA deployment.  
        # if [[ (" ${EXISTING_PATTERN_ARR[@]} " =~ "content") || (" ${EXISTING_PATTERN_ARR[@]} " =~ "workflow") || (" ${EXISTING_PATTERN_ARR[@]} " =~ "document_processing") || (" ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "baw_authoring") || (" ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "ae_data_persistence") ]]; then
        #     iam_idprovider=$(kubectl get route -n $project_name -o 'custom-columns=NAME:.metadata.name' --no-headers --ignore-not-found | grep cp-console-iam-provider)
        #     iam_idmgmt=$(kubectl get route -n $project_name -o 'custom-columns=NAME:.metadata.name' --no-headers --ignore-not-found | grep cp-console-iam-idmgmt)
        #     if [[ -z $iam_idprovider || -z $iam_idmgmt ]]; then
        #         fail "Not found route \"cp-console-iam-idmgmt\" and \"cp-console-iam-provider\" under project \"$project_name\"."
        #         info "You have to create \"cp-console-iam-idmgmt\" and \"cp-console-iam-provider\" before upgrade CP4BA deployment."
        #         exit 1
        #     fi
        # fi

        # Backup existing icp4acluster CR
        mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
        ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_CR_BAK}
        # fi
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
        kubectl apply -f ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} -n $deployment_project_name >/dev/null 2>&1

        # replace release/appVersion
        ${SED_COMMAND} "s|release: .*|release: ${BAI_RELEASE_BASE}|g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
        ${SED_COMMAND} "s|appVersion: .*|appVersion: ${BAI_RELEASE_BASE}|g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

        # Change ssl_protocol for PFS required in $CP4BA_RELEASE_BASE release
        pfs_ssl_protocol=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.pfs_configuration.security.ssl_protocol`
        if [ ! -z "$pfs_ssl_protocol" ]; then
            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} spec.pfs_configuration.security.ssl_protocol "TLSv1.2"
        fi


        ${SED_COMMAND} "s/route_reencrypt: .*/route_reencrypt: $ZEN_ROUTE_REENCRYPT/g" ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}
        # This block of is used to merge the BAI save point into the CR.  It's only executed when it's an n-1 to n upgrade, not ifix to ifix
        # The is_ifix_to_ifix_upgrade is set to false in the determine_type_of_upgrade function.
        # if [[ ! ("$cp4ba_original_csv_ver_for_upgrade_script" == "24.0."*) ]]; then
        # Sourcing upgrade_check_status.sh and calling determine_type_of_upgrade to dertmine the type of upgrade

        info "CR Version: $cr_version"
        determine_type_of_upgrade "$cr_version"
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
        info "${YELLOW_TEXT}Setting \"shared_configuration.sc_egress_configuration.sc_restricted_internet_access\" to \"false\" while upgrading BAI Standalone deployment, you could change it according to your requirements of security.${RESET_TEXT}"
        printf "\n"
        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access "false"
        # Set shared_configuration.enable_fips always "false" in upgrade
        info "${YELLOW_TEXT}Setting \"shared_configuration.enable_fips\" as \"false\" while upgrading BAI Standalone deployment, you could change it according to your requirements.${RESET_TEXT}"
        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} spec.shared_configuration.enable_fips "false"

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
        success "BAI Standalone Custom Resource File has been updated for release ($BAI_RELEASE_BASE)"


        #Function to remove the image tags from the CR if present
        remove_image_tags $UPGRADE_DEPLOYMENT_BAI_CR_TMP
        ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_CR}

        if [[ $TAGS_REMOVED == "true" ]]; then
            info "IMAGE TAGS ARE REMOVED FROM THE NEW VERSION OF THE CUSTOM RESOURCE \"${UPGRADE_DEPLOYMENT_BAI_CR}\"."
            printf "\n"
        fi

        echo "${YELLOW_TEXT}[ATTENTION]: ${RESET_TEXT}${YELLOW_TEXT}PLEASE DON'T SET ${RESET_TEXT}${RED_TEXT}\"shared_configuration.sc_egress_configuration.sc_restricted_internet_access\"${RESET_TEXT}${YELLOW_TEXT} AS ${RESET_TEXT}${RED_TEXT}\"true\"${RESET_TEXT}${YELLOW_TEXT} UNTIL AFTER YOU'VE COMPLETED THE BAI Standalone UPGRADE TO $BAI_RELEASE_BASE.${RESET_TEXT} ${GREEN_TEXT}(UNLESS YOU ALREADY HAD THIS SET TO \"true\" IN THE BAI Standalone 24.0.0.X deployment)${RESET_TEXT}"
        read -rsn1 -p"Press any key to continue ...";echo
        printf "\n"

        echo "${YELLOW_TEXT}[NEXT ACTION]:${RESET_TEXT}"
        step_num=1
        echo "${YELLOW_TEXT}- After reviewing or modifying the custom resource file \"${UPGRADE_DEPLOYMENT_BAI_CR}\", you need to follow the steps below to upgrade this BAI Standalone deployment.${RESET_TEXT}"
        # As a part of DBACLD-149126 solution we no longer needed the user to patch or annotate the custom resource file
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}:${GREEN_TEXT} # ${CLI_CMD} apply -f ${UPGRADE_DEPLOYMENT_BAI_CR} -n $deployment_project_name${RESET_TEXT}"  && step_num=$((step_num + 1))

        printf "\n"
        echo "${YELLOW_TEXT}- How to check the overall upgrade status for BAI Operators/zenService/IM.${RESET_TEXT}"
        echo "${YELLOW_TEXT}  [TIPS]: ${RESET_TEXT}The [upgradeDeploymentStatus] option will first start the necessary BAI Standalone operators (ibm-bai-insights-engine-operator/ibm-bai-foundation-operator) to upgrade zenService.Once the zenService upgrade is completed , the rest of the BAI Standalone deployment will be upgraded."
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}:${GREEN_TEXT} # ./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME${RESET_TEXT}"

        printf "\n"
        echo "${YELLOW_TEXT}[ATTENTION]: The zenService will be ready in about 120 minutes after the new version ($BAI_RELEASE_BASE) of BAI Standalone custom resource is applied.${RESET_TEXT}"
        printf "\n"
        
        
    fi

    if [[ (-z $insightsengine_cr_name) ]]; then
        fail "No found InsightsEngine custom resource in namespace \"$project_name\""
        exit 1
    fi
}
