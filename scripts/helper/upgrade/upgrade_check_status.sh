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

# Based on if it is a separation of duties based deployment or not, some of the upgrade file paths will change
# Called during upgradeDeployment and UpgradeOperatorStatus
function set_upgrade_file_paths(){
    local namespace=$1
    UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/bai-upgrade/project/$namespace
    UPGRADE_DEPLOYMENT_PROPERTY_FILE=${UPGRADE_DEPLOYMENT_FOLDER}/bai_upgrade.property

    UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
    UPGRADE_DEPLOYMENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR}/backup

    UPGRADE_DEPLOYMENT_BAI_CR=${UPGRADE_DEPLOYMENT_CR}/insightsengine.yaml
    UPGRADE_DEPLOYMENT_BAI_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.insightsengine_tmp.yaml
    UPGRADE_DEPLOYMENT_BAI_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/insightsengine_cr_backup.yaml

    UPGRADE_CS_ZEN_FILE=${UPGRADE_DEPLOYMENT_CR}/.cs_zen_parameter.yaml
    UPGRADE_DEPLOYMENT_BAI_TMP=${UPGRADE_DEPLOYMENT_CR}/.bai_tmp.yaml

    UPGRADE_BAI_SHARED_INFO_CM_FILE=${UPGRADE_DEPLOYMENT_CR}/ibm_bai_shared_info.yaml
}

#Determine if it's an Ifix to ifix upgrade or a n-1 upgrade using CSV
# Format of CSV x.y.z where x is major version, y is minor version and z is ifix version
# For example: 
# - 24.0.1 version will have 24.1.0 in the CSV
# - 24.0.1-IF001 version will 24.1.1 in the CSV
# - 25.0.0-GA version will have 25.0.0 in the CSV 
# The rules are:
# 1. n-1 upgrade: Use the desired major version such as 24 from the BAI_CSV_VERSION in the common.sh  to compare with the current install version
#   - If x version of the current CSV is equal to the desired major version, then it's a n-1 upgrade.  For example, if the current version is 24.0.0-IF003 (24.0.3) and the desired version is 24.0.1 (24.1.0), then it's a n-1 upgrade
#   - If x version of the current CSV is equal to the desired major version (x+1), then it's the n-1 upgrade. For example, if the current version is 24.x and the desired version is 25.x, then it's a n-1 upgrade
# 2. Ifix to Ifix upgrade: Use the desired major version such as 24 from the BAI_CSV_VERSION in the common.sh  to compare with the current install version
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
# 3. The current cpfs csv version so that it can be used to compare against the cpfs csv version in the common.sh defined as CS_OPERATOR_VERSION.
# 4. The function will return true if the version is supported and false if it is not supported
function check_bai_minimum_version(){
    local existing_bai_csv_version=$1
    local existing_cpfs_csv_version=$2
    local cpfs_csv_version=${CS_OPERATOR_VERSION//v/}
    local versions_string="${MINIMUM_SUPPORTED_UPGRADE_VERSIONS[*]}"
    local valid_bai_version=false
    local valid_cpfs_version=false
    valid_version=false

    # Check for BAI S version  by comparing the existing bai csv version with the minimum supported upgrade versions defined in the array
    info "Checking existing IBM Business Automation Insights Standalone version $existing_bai_csv_version against the minimum supported upgrade version(s) ($versions_string) for this BAI Standalone release version."
    info "Checking the existing CPFS version $existing_cpfs_csv_version against the $cpfs_csv_version being used for this BAI Standalone release version."
    for abs_min in "${MINIMUM_SUPPORTED_UPGRADE_VERSIONS[@]}"; do
        # Extract major.minor from both versions
        local abs_major_minor="${abs_min%.*}"
        local curr_major_minor="${existing_bai_csv_version%.*}"
   
        if [[ "$curr_major_minor" == "$abs_major_minor" ]]; then
            # Print the versions, sort 2 number using version sort which understands the versioning scheme(24.1.0 is after 24.1.2), take the first/smallest one
            # and compare it with the absolute minimum version. If the smallest version is abs_min, then the current version is equal or greater than the abs_min
            if [[ "$(printf '%s\n' "$abs_min" "$existing_bai_csv_version" | sort -V | head -n1)" = "$abs_min"  && "$_allow_direct_upgrade" != 1 ]]; then  
                valid_bai_version=true

            else
                fail "The current IBM Business Automation Insights Standalone (BAI-S) version you are upgrading from is $existing_bai_csv_version and it does not meet the minimum requirement. Please upgrade the BAI Standalone deployment to "$abs_min" or higher before upgrading to "$BAI_CSV_VERSION"."
                valid_bai_version=false
                break
            fi

        fi
    done

    # Check for CPFS version by comparing existing_cpfs_csv_version with the cpfs_csv_version which is CS_OPERATOR_VERSION without the `v` prefix
    # If the existing_cpfs_csv_version is less than or equal the cpfs_csv_version, then it's a valid version
    # If the existing_cpfs_csv_version is greater than the cpfs_csv_version, then it's not a valid version
    if [[ "$valid_bai_version" == true ]]; then
        # Compare versions using sort -V
        if [[ "$(printf '%s\n' "$existing_cpfs_csv_version" "$cpfs_csv_version" | sort -V | head -n1)" = "$existing_cpfs_csv_version"  ]]; then
            valid_cpfs_version=true
        else
            valid_cpfs_version=false
            fail "The current IBM Cloud Pak foundational services (CPfs) version you are upgrading from is $existing_cpfs_csv_version and it is newer than the CPfs version ("$cpfs_csv_version") you are upgrading to.  If you wish to upgrade to the BAI Standalone release stream $BAI_RELEASE_BASE you must check for newer $BAI_RELEASE_BASE IFIX versions that contain CPFS $existing_cpfs_csv_version or newer. You may have to wait until a new $BAI_RELEASE_BASE IFIX version is released before you can upgrade."

        fi
    fi

    if [[ ("$valid_bai_version" == true && "$valid_cpfs_version" == true) || ("$_allow_direct_upgrade" == 1) ]]; then
        export valid_version=true
        success "The IBM Cloud Pak for Business Automation version "$existing_bai_csv_version" with Cloud Pak foundational services version "$existing_cpfs_csv_version" is supported for upgrade to "$BAI_CSV_VERSION"."
    else
        export valid_version=false
        fail "The IBM Cloud Pak for Business Automation version "$existing_bai_csv_version" with Cloud Pak foundational services version "$existing_cpfs_csv_version" is NOT supported for upgrade to "$BAI_CSV_VERSION"."
        exit 1
    fi
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
    cpfs_operator_csv_name_target_ns=$(${CLI_CMD} get csv -n $project_name --no-headers --ignore-not-found | grep "IBM Cloud Pak foundational services" | awk '{print $1}')
    if [[ -z $cpfs_operator_csv_name_target_ns ]]; then
        fail "No IBM Cloud Pak foundational services CSV found in \"$project_name\" project."
        warning "Input correct project name for BAI Standalone."
        exit 1
    fi
    info "Checking the IBM Foundational Services Operator CSV version"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        valid_version=false  #this is flag to check if the BAI S operator is a valid version
        if [[ (! -z $bai_operator_csv_name) ]]; then
            success "Found IBM Business Automation Insights Operator deployed in the project \"$project_name\"."
            ALL_NAMESPACE_FLAG="No"
            TEMP_OPERATOR_PROJECT_NAME=$project_name
            # We will only use the current csv versions for bai and cpfs operators to perform any pre upgrade version checks.
            # https://jsw.ibm.com/browse/DBACLD-180433
            bai_operator_csv_version=$(${CLI_CMD} get csv $bai_operator_csv_name -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')
            cpfs_operator_csv_version=$(${CLI_CMD} get csv $cpfs_operator_csv_name_target_ns -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')
            success "IBM Foundational Services Operator version is $cpfs_operator_csv_version"
        fi
        
        
        if [[ ! -z $BAI_ORIGINAL_CSV_VERSION ]]; then
            BAI_ORIGINAL_CSV_VERSION=$(sed -e 's/^"//' -e 's/"$//' <<<"$BAI_ORIGINAL_CSV_VERSION")
            bai_operator_csv_version=$BAI_ORIGINAL_CSV_VERSION
        fi
        # DBACLD-165816: Calling check_bai_minimum_version function to check the minimum supported version
        check_bai_minimum_version "$bai_operator_csv_version" "$cpfs_operator_csv_version"

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

# Function to check the operator status and if they are ready for next steps of the upgrade
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
            isReadyWebhook=$(${CLI_CMD} get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-webhook -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')
            isReadyCertmanager=$(${CLI_CMD} get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-controller -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')
            isReadyCainjector=$(${CLI_CMD} get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-cainjector -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')
            isReadyCertmanagerOperator=$(${CLI_CMD} get pod -l=app.kubernetes.io/name=cert-manager,app.kubernetes.io/instance=ibm-cert-manager-operator -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')

            if [[ -z $isReadyWebhook || -z $isReadyCertmanager || -z $isReadyCainjector || -z $isReadyCertmanagerOperator ]]; then
            # if [[ -z $isReadyCertmanagerOperator ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    printf "\n"
                    warning "Timeout Waiting for IBM Cert-manager Operator to start"
                    echo -e "\x1B[1mCheck the status of Pod by issuing the following command: \x1B[0m"
                    if [[ -z $isReadyWebhook ]]; then
                        echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-webhook --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
                    fi
                    if [[ -z $isReadyCertmanager ]]; then
                        echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-controller --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
                    fi
                    if [[ -z $isReadyCainjector ]]; then
                        echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-cainjector --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
                    fi
                    if [[ -z $isReadyCertmanagerOperator ]]; then
                        echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -l=app.kubernetes.io/name=cert-manager,app.kubernetes.io/instance=ibm-cert-manager-operator --all-namespaces --no-headers|awk '{print $1}') --all-namespaces"
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
            isReady=$(${CLI_CMD} get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            # isReady=$(kubectl exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
            if [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout Waiting for IBM Cloud Pak foundational operator to start"
                echo -e "\x1B[1mCheck the status of Pod by issuing the following command:\x1B[0m"
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-common-service-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mCheck the status of ReplicaSet by issuing the following command:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-common-service-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-common-service-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
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


    # Check BAI Standalone operator upgrade status
    if [[ "$check_mode" == "full" ]]; then
        local maxRetry=20
        echo "****************************************************************************"
        info "Checking for IBM Business Automation Insights stand-alone (BAI S) operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(${CLI_CMD} get csv ibm-bai-insights-engine-operator.$BAI_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
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
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mCheck the status of ReplicaSet by executing the below command:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') -n $project_name"
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

    # Check BAI Standalone Foundation operator upgrade status
    echo "****************************************************************************"
    info "Checking for BAI Foundation operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv ibm-bai-foundation-operator.$BAI_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        # isReady=$(kubectl exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-bai-foundation-operator.v |awk '{print $1}') --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
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
            echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-bai-foundation-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mCheck the status of ReplicaSet by issuing the following command:\x1B[0m"
            echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-bai-foundation-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-bai-foundation-operator,release=$BAI_RELEASE_BASE --no-headers --ignore-not-found -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
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

    bai_cr_name=$(${CLI_CMD} get insightsengine -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z "$bai_cr_name" ]; then
        cp4ba_cr_metaname=$(${CLI_CMD} get insightsengine $bai_cr_name -n $project_name --no-headers --ignore-not-found -o yaml | ${YQ_CMD} r - metadata.name)
        ${CLI_CMD} get insightsengine $bai_cr_name -n ${project_name} --no-headers --ignore-not-found -o yaml > ${UPGRADE_STATUS_BAI_FILE}
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
        #convert_olm_cr "${UPGRADE_STATUS_FILE}"
        #if [[ $olm_cr_flag == "No" ]]; then
        #    #this variable is being used to check what the version of CP4BA was used before upgrade and is used later in a check if some alert message is to be printed
        #    # initial_app_version=`cat $UPGRADE_DEPLOYMENT_insightsengine_CR_BAK | ${YQ_CMD} r - spec.appVersion`
        #    existing_pattern_list=""
        #    existing_opt_component_list=""
        #    EXISTING_PATTERN_ARR=()
        #    EXISTING_OPT_COMPONENT_ARR=()
        #    existing_pattern_list=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
        #    existing_opt_component_list=`cat $UPGRADE_STATUS_FILE | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`
        #
        #    OIFS=$IFS
        #    IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
        #    IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
        #    IFS=$OIFS
        #fi

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
    echo "  - ${YELLOW_TEXT} Retrieve the the logs of of the Insights Engine operator pod by exiting the script and running \"${CLI_CMD} logs $(${CLI_CMD} get pod -n $project_name|grep ibm-bai-insights-engine-operator|awk '{print $1}') \"${RESET_TEXT}"
    echo "  - ${YELLOW_TEXT} AFTER UPGRADING the IBM Business Automations Insights (BAI) DEPLOYMENT SUCCESSFULLY, YOU NEED TO REMOVE${RESET_TEXT} ${RED_TEXT}\"recovery_path\"${RESET_TEXT} ${YELLOW_TEXT}FROM THE CUSTOM RESOURCE FILE UNDER${RESET_TEXT} ${RED_TEXT}\"the bai_configuration section\"${RESET_TEXT} ${YELLOW_TEXT}MANUALLY IF IT EXISTS.${RESET_TEXT}"
    
}

# Function that retrieves the pre upgrade csv version and assigns it to the variable bai_original_csv_ver_for_upgrade_script
# Function looks into the ibm-bai-shared-info to retrieve this detail
function get_preupgrade_csv_version(){
    local namespace=$1
    ibm_bai_shared_info_cm=$(${CLI_CMD} get configmap ibm-bai-shared-info --no-headers --ignore-not-found -n $namespace)
    if [[ ! -z $ibm_bai_shared_info_cm ]]; then
        tmp_csv_val=$(${CLI_CMD} get configmap ibm-bai-shared-info -n $namespace -o jsonpath='{.data.bai_original_csv_ver_for_upgrade_script}')
        if [[ ! -z $tmp_csv_val ]]; then
            bai_original_csv_ver_for_upgrade_script=$tmp_csv_val
        else
            fail "Configmap ibm-bai-shared-info created incorrectly, run upgradeOperator mode to fix this issue."
            exit
        fi
    else
        fail "Failed to find configMap ibm-bai-shared-info deployed in the project \"$namespace\"."
        exit
    fi
}


#Function to create the bai shared info Configmap
# Function called during upgradeOperator mode
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
