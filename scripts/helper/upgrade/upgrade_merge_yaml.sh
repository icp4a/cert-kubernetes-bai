

# This function seems to be a CP4BA related function
# All the logic in this function references CR sections that are not applicable to the BAI-S CR
# Leaving this function for now, but all function calls are commented out
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


