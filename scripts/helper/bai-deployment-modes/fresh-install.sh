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


# This file is a helper script used to store all functions that are used by the bai-deployment.sh for a fresh install mode
# Example : bai-deployment.sh -n <bai-namespace>

#### Start - Functions being called by the fresh_install function ####

#### BEGIN - Functions being called by the input_information function ####

function select_platform(){
    printf "\n"
    printf '%b\n' "\x1B[1mSelect the cloud platform to deploy: \x1B[0m"
    COLUMNS=12
    otheroption="Other - Cloud Native Computing Foundation ( CNCF )"
    if [ -z "$existing_platform_type" ]; then
        
        #Adding support for the other type of platform
        # DBACLD-168151
        options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "$otheroption")
        PS3='Enter a valid option [1 to 3]: '

        select opt in "${options[@]}"
        do
            case $opt in
                "RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud")
                    PLATFORM_SELECTED="ROKS"
                    use_entitlement="yes"
                    break
                    ;;
                "Openshift Container Platform (OCP) - Private Cloud")
                    PLATFORM_SELECTED="OCP"
                    use_entitlement="yes"
                    break
                    ;;
                "$otheroption")
                    PLATFORM_SELECTED="other"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    else
        if [[ "${SCRIPT_MODE}" == "OLM" ]]; then
            options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
            options_var=("ROKS" "OCP")
        else
            # options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "Other ( Certified Kubernetes Cloud Platform / CNCF)")
            # options_var=("ROKS" "OCP" "other")
            options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
            options_var=("ROKS" "OCP")
        fi
        for i in ${!options_var[@]}; do
            if [[ "${options_var[i]}" == "$existing_platform_type" ]]; then
                printf "%1d) %s \x1B[1m%s\x1B[0m\n" $((i+1)) "${options[i]}"  "(Selected)"
            else
                printf "%1d) %s\n" $((i+1)) "${options[i]}"
            fi
        done
        printf '%b\n' "\x1B[1;31mExisting platform type found in CR: \"$existing_platform_type\"\x1B[0m"
        # printf '%b\n' "\x1B[1;31mDo not need to select again.\n\x1B[0m"
        prompt_press_any_key_to_continue
    fi

    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        CLI_CMD=oc
    elif [[ "$PLATFORM_SELECTED" == "other" ]]
    then
        CLI_CMD=kubectl
    fi

    validate_kube_oc_cli
}

# Function to select the ldap user to onboard zen
function select_ldap_user_for_zen(){
    printf "\n"
    LDAP_USER_NAME=""

    printf '%b\n'  "${YELLOW_TEXT}For BAI standalone, if you select LDAP, then provide one ldap user here for onborading ZEN.${RESET_TEXT}"    
    while [[ $LDAP_USER_NAME == "" ]] # While get medium storage clase name
    do
        printf "\x1B[1mEnter one LDAP user for BAI standalone: \x1B[0m"
        read -rp "" LDAP_USER_NAME
        if [ -z "$LDAP_USER_NAME" ]; then
        printf '%b\n' "\x1B[1;31mEnter a valid LDAP user\x1B[0m"
        fi
    done
}

# Functon to select if LDAP is to be configured
function select_ldap_type(){
    printf "\n"
    SELECTED_LDAP="Yes" # Setting the default value to true since that is in line with the question being asked
    while true; do
        printf "\x1B[1mDo you want to configure one LDAP for this IBM Business Automation Insights standalone deployment? (Yes/No, default: Yes): \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES"|"")
            SELECTED_LDAP="Yes"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")
            SELECTED_LDAP="No"
            break
            ;;
        *)
            SELECTED_LDAP=""
            printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done

    if [[ $SELECTED_LDAP == "Yes" ]]; then
        select_ldap_user_for_zen
        printf "\n"
        COLUMNS=12
        printf '%b\n' "\x1B[1mWhat is the LDAP type that will be used for this deployment? \x1B[0m"
        options=("Microsoft Active Directory" "IBM Tivoli Directory Server / Security Directory Server")
        PS3='Enter a valid option [1 to 2]: '
        select opt in "${options[@]}"
        do
            case $opt in
                "Microsoft Active Directory")
                    LDAP_TYPE="AD"
                    break
                    ;;
                "IBM Tivoli"*)
                    LDAP_TYPE="TDS"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    fi
}


# function to get the storage class name
# This function is used when the user property file is not supplied or found
function get_storage_class_name(){

    # For dynamic storage classname
    # storage_class_name=""
    block_storage_class_name=""
    # sc_slow_file_storage_classname=""
    sc_medium_file_storage_classname=""
    sc_fast_file_storage_classname=""

    printf "\n"

    printf "\x1B[1mTo provision the persistent volumes and volume claims\n\x1B[0m"

    while [[ $sc_medium_file_storage_classname == "" ]] # While get medium storage clase name
    do
        printf "\x1B[1mEnter the file storage classname for medium storage(RWX): \x1B[0m"
        read -rp "" sc_medium_file_storage_classname
        if [ -z "$sc_medium_file_storage_classname" ]; then
            printf '%b\n' "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done

    while [[ $sc_fast_file_storage_classname == "" ]] # While get fast storage clase name
    do
        printf "\x1B[1mEnter the file storage classname for fast storage(RWX): \x1B[0m"
        read -rp "" sc_fast_file_storage_classname
        if [ -z "$sc_fast_file_storage_classname" ]; then
            printf '%b\n' "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done
    
    while [[ $block_storage_class_name == "" ]] # While get block storage clase name
    do
        printf "\x1B[1mEnter the block storage classname for Zen(RWO): \x1B[0m"
        read -rp "" block_storage_class_name
        if [ -z "$block_storage_class_name" ]; then
            printf '%b\n' "\x1B[1;31mEnter a valid block storage classname(RWO)\x1B[0m"
        fi
    done
    # fi
    # STORAGE_CLASS_NAME=${storage_class_name}
    # SLOW_STORAGE_CLASS_NAME=${sc_slow_file_storage_classname}
    MEDIUM_STORAGE_CLASS_NAME=${sc_medium_file_storage_classname}
    FAST_STORAGE_CLASS_NAME=${sc_fast_file_storage_classname}
    BLOCK_STORAGE_CLASS_NAME=${block_storage_class_name}
}

# Function to select the profile type
# This function is used when the user property file is not supplied or found
function select_profile_type(){
    printf "\n"
    COLUMNS=12
    printf '%b\n' "\x1B[1mSelect the deployment profile (default: small).  Refer to the documentation in BAI standalone Knowledge Center for details on profile.\x1B[0m"
    options=("small" "medium" "large")
    if [ -z "$existing_profile_type" ]; then
        PS3='Enter a valid option [1 to 3]: '
        select opt in "${options[@]}"
        do
            case $opt in
                "small")
                    PROFILE_TYPE="small"
                    break
                    ;;
                "medium")
                    PROFILE_TYPE="medium"
                    break
                    ;;
                "large")
                    PROFILE_TYPE="large"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    else
        options_var=("small" "medium" "large")
        for i in ${!options_var[@]}; do
            if [[ "${options_var[i]}" == "$existing_profile_type" ]]; then
                printf "%1d) %s \x1B[1m%s\x1B[0m\n" $((i+1)) "${options[i]}"  "(Selected)"
            else
                printf "%1d) %s\n" $((i+1)) "${options[i]}"
            fi
        done
        printf '%b\n' "\x1B[1;31mExisting profile size type found in CR: \"$existing_profile_type\"\x1B[0m"
        # printf '%b\n' "\x1B[1;31mDo not need to select again.\n\x1B[0m"
        prompt_press_any_key_to_continue        
    fi
}


# Function to select the default iam admin
# This function is used when the user property file is not supplied or found
function select_iam_default_admin(){
    printf "\n"
    while true; do
        printf '%b\n' "\x1B[33;5mATTENTION: \x1B[0m\x1B[1;31mIf you are unable to use [cpadmin] as the default IAM admin user due to it being already used in your LDAP Directory, you need to change the Cloud Pak administrator username. See: \" https://www.ibm.com/docs/en/cloud-paks/foundational-services/$CS_CHANNEL_KC?topic=configurations-changing-cluster-administrator-access-credentials#name\"\x1B[0m"
        printf "\x1B[1mDo you want to use the default IAM admin user: [cpadmin] (Yes/No, default: Yes): \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES"|"")
            USE_DEFAULT_IAM_ADMIN="Yes"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")
            USE_DEFAULT_IAM_ADMIN="No"
            while [[ $NON_DEFAULT_IAM_ADMIN == "" ]]; 
            do
                printf "\n"
                printf '%b\n' "\x1B[1mWhat is the non default IAM admin user you renamed?\x1B[0m"
                read -p "Enter the admin user name: " NON_DEFAULT_IAM_ADMIN
            
                if [ -z "$NON_DEFAULT_IAM_ADMIN" ]; then
                    printf '%b\n' "\x1B[1;31mEnter a valid admin user name, user name can not be blank\x1B[0m"
                    NON_DEFAULT_IAM_ADMIN=""
                elif [[ "$NON_DEFAULT_IAM_ADMIN" == "cpadmin" ]]; then
                    printf '%b\n' "\x1B[1;31mEnter a valid admin user name, user name should not be 'cpadmin'\x1B[0m"
                    NON_DEFAULT_IAM_ADMIN=""
                fi
            done
            break
            ;;
        *)
            printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

# Function to select the components for which flink jobs should be selected for
# This function is used when the user property file is not supplied or found
function select_flink_job(){
# This function support mutiple checkbox, if do not select anything, it will return None

    FLINK_JOB_SELECTED=""
    choices_pattern=()
    flink_job_arr=()
    flink_job_cr_arr=()

    options=("BAW" "BAW Advanced events" "ICM" "ODM" "Content" "ADS" "Navigator")
    options_cr_val=("flink_job_bpmn" "flink_job_bawadv" "flink_job_icm" "flink_job_odm" "flink_job_content" "flink_job_ads" "flink_job_navigator")

    patter_ent_input_array=("1" "2" "3" "4" "5" "6" "7")
    tips1="\x1B[1;31mTips\x1B[0m:\x1B[1mPress [ENTER] to accept the default (None of the components is selected)\x1B[0m"
    tips2="\x1B[1;31mTips\x1B[0m:\x1B[1mPress [ENTER] when you are done\x1B[0m"
    indexof() {
        i=-1
        for ((j=0;j<${#options_cr_val[@]};j++));
        do [ "${options_cr_val[$j]}" = "$1" ] && { i=$j; break; }
        done
        echo "$i"
    }
    menu() {
        clear
        printf '%b\n' "\x1B[1mWhich are the components you want to enable the Flink job for: \x1B[0m"
        for i in ${!options[@]}; do
            containsElement "${options_cr_val[i]}" "${EXISTING_PATTERN_ARR[@]}"
            retVal=$?
            if [ $retVal -ne 0 ]; then
                printf "%1d) %s \x1B[1m%s\x1B[0m\n" $((i+1)) "${options[i]}"  "${choices_pattern[i]}"
            else
                if [[ "${choices_pattern[i]}" == "(To Be Uninstalled)" ]]; then
                    printf "%1d) %s \x1B[1m%s\x1B[0m\n" $((i+1)) "${options[i]}"  "${choices_pattern[i]}"
                else
                    printf "%1d) %s \x1B[1m%s\x1B[0m\n" $((i+1)) "${options[i]}"  "(Installed)"
                fi
            fi
        done
        if [[ "$msg" ]]; then echo "$msg"; fi
        # Show different tips according components select or unselect
        containsElement "(Selected)" "${choices_pattern[@]}"
        retVal=$?
        if [ $retVal -ne 0 ]; then
            printf '%b\n' "${tips1}"
        else
            printf '%b\n' "${tips2}"
        fi
# ##########################DEBUG############################
#     for i in "${!choices_pattern[@]}"; do
#         printf "%s\t%s\n" "$i" "${choices_pattern[$i]}"
#     done
# ##########################DEBUG############################
    }

    prompt="Enter a valid option [1 to ${#options[@]}]: "

    while menu && read -rp "$prompt" num && [[ "$num" ]]; do
        [[ "$num" != *[![:digit:]]* ]] &&
        (( num > 0 && num <= ${#options[@]} )) ||
        { msg="Invalid option: $num"; continue; }
        ((num--));
        [[ "${choices_pattern[num]}" ]] && choices_pattern[num]="" || choices_pattern[num]="(Selected)"
    done

    # echo "choices_pattern: ${choices_pattern[*]}"
    # read -rsn1 -p"Press Enter/Return to continue (DEBUG MODEL)";echo
    # Generate list of the pattern which will be installed or To Be Uninstalled
    for i in ${!options[@]}; do
        [[ "${choices_pattern[i]}" ]] && { flink_job_arr=( "${flink_job_arr[@]}" "${options[i]}" ); flink_job_cr_arr=( "${flink_job_cr_arr[@]}" "${options_cr_val[i]}" ); msg=""; }
    done
    # printf '%b\n' "$msg"

    if [ "${#flink_job_arr[@]}" -eq "0" ]; then
        FLINK_JOB_SELECTED="None"
        warning "No components selected for Flink job. Continuing... \n"
        sleep 3
        # exit 1
    else
        FLINK_JOB_SELECTED=$( IFS=$','; echo "${flink_job_arr[*]}" )
        FLINK_JOB_CR_SELECTED=$( IFS=$','; echo "${flink_job_cr_arr[*]}" )
    fi

    FLINK_JOB_CR_SELECTED=($(echo "${flink_job_cr_arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    # echo "options_cr_val: ${options_cr_val[*]}"
    # echo "flink_job_arr: ${flink_job_arr[*]}"
    # echo "flink_job_cr_arr: ${flink_job_cr_arr[*]}"
    # echo "FLINK_JOB_SELECTED: ${FLINK_JOB_SELECTED[*]}"
    # echo "FLINK_JOB_CR_SELECTED: ${FLINK_JOB_CR_SELECTED[*]}"

    # read -rsn1 -p"Press Enter/Return to continue (DEBUG MODEL)";echo
}

# Function that prepares the pattern file
function prepare_pattern_file(){
    DEPLOY_TYPE_IN_FILE_NAME="production"

    BAI_PATTERN_FILE=${PARENT_DIR}/descriptors/patterns/ibm_cp4a_cr_${DEPLOY_TYPE_IN_FILE_NAME}_bai.yaml
    BAI_PATTERN_FILE_TMP=$TEMP_FOLDER/.ibm_cp4a_cr_${DEPLOY_TYPE_IN_FILE_NAME}_bai_tmp.yaml
    BAI_PATTERN_FILE_BAK=$BAK_FOLDER/.ibm_cp4a_cr_${DEPLOY_TYPE_IN_FILE_NAME}_bai.yaml

    ${COPY_CMD} -rf "${BAI_PATTERN_FILE}" "${BAI_PATTERN_FILE_BAK}"
    ${COPY_CMD} -rf "${BAI_PATTERN_FILE_BAK}" "${BAI_PATTERN_FILE_TMP}"
}

#### End - Functions being called by the input_information function ####

# Function that takes the inputs for information required
function input_information(){
    #set -x
    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" || $DEPLOYMENT_TYPE == "starter" ]]; then
        # select_installation_type
        INSTALLATION_TYPE="new"
    elif [[ $DEPLOYMENT_WITH_PROPERTY == "Yes" ]]; then
        INSTALLATION_TYPE="new"
    fi

    mkdir -p $TEMP_FOLDER >/dev/null 2>&1
    mkdir -p $BAK_FOLDER >/dev/null 2>&1
    mkdir -p $FINAL_CR_FOLDER >/dev/null 2>&1

    #if [[ ${INSTALLATION_TYPE} == "existing" ]]; then
    #    # INSTALL_BAW_IAWS="No"
    #    prepare_pattern_file
    #    select_deployment_type
    #    if [[ $DEPLOYMENT_TYPE == "production" && (-z $PROFILE_TYPE) ]]; then
    #        select_profile_type
    #    fi
    #    select_platform
    #    if [[ ("$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS") && "$DEPLOYMENT_TYPE" == "production" ]]; then
    #        select_iam_default_admin
    #    fi
    #    check_ocp_version
    #    validate_docker_podman_cli
    if [[ ${INSTALLATION_TYPE} == "new" ]]; then
        # select_ocp_olm
        # select_deployment_type
        # BAI standalone only support Production
        DEPLOYMENT_TYPE="production"
        if [[ $DEPLOYMENT_WITH_PROPERTY == "Yes" && $DEPLOYMENT_TYPE == "production" ]]; then
            load_properties_from_temp_file # Function definition in helper/common.sh
            if [[ -f $USER_PROFILE_PROPERTY_FILE ]]; then
                PLATFORM_SELECTED=$(prop_user_profile_property_file BAI_STANDALONE.PLATFORM_TYPE)
                if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
                    CLI_CMD=oc
                elif [[ "$PLATFORM_SELECTED" == "other" ]]
                then
                    CLI_CMD=kubectl
                fi
                validate_kube_oc_cli

                # Fixing the retrieval of this property LDAP_USER_NAME_ONBOARDING_ZEN after the spelling was corrected in the property files
                # DBACLD-167210
                LDAP_USER_NAME=$(prop_user_profile_property_file BAI_STANDALONE.LDAP_USER_NAME_ONBOARDING_ZEN)
                NON_DEFAULT_IAM_ADMIN=$(prop_user_profile_property_file BAI_STANDALONE.IAM_ADMIN_USER_NAME)
                MEDIUM_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.MEDIUM_FILE_STORAGE_CLASSNAME)
                FAST_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.FAST_FILE_STORAGE_CLASSNAME)
                BLOCK_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.BLOCK_STORAGE_CLASS_NAME)
                
                # Retrieving the domain name from property files to generate CR, only for other type of platform
                # DBACLD-168345
                if [[ "$PLATFORM_SELECTED" == "other" ]]; then
                    OTHER_DOMAIN_NAME=$(prop_user_profile_property_file BAI_STANDALONE.DOMAIN_NAME)
                else
                    OTHER_DOMAIN_NAME=""
                fi
                
                flink_job_cr_arr=()
                for i in $(cat $USER_PROFILE_PROPERTY_FILE | grep BAI_STANDALONE.FLINK_JOB_  | grep "True" | tr '[:upper:]' '[:lower:]' | sed 's/.*\.//; s/=.*//')
                do
                    # echo $i
                    flink_job_cr_arr+=("$i")
                done
                # echo "flink_job_cr_arr: ${flink_job_cr_arr[@]}"
            else 
                fail "No existing property files found under \"$PROPERTY_FILE_FOLDER\". Run \"bai-prerequisites.sh\" to complete prerequisites"
                exit 1
            fi
            # show_summary
        fi
        #if [[ $DEPLOYMENT_TYPE == "production" && (-z $PROFILE_TYPE) ]]; then
        #    select_platform
        #    select_ldap_type          
        #
        #    if [[ -f $USER_PROFILE_PROPERTY_FILE ]]; then
        #        MEDIUM_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.MEDIUM_FILE_STORAGE_CLASSNAME)
        #        FAST_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.FAST_FILE_STORAGE_CLASSNAME)
        #        BLOCK_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.BLOCK_STORAGE_CLASS_NAME)
        #    fi
        #    if [[ -z $MEDIUM_STORAGE_CLASS_NAME || -z $FAST_STORAGE_CLASS_NAME || -z $BLOCK_STORAGE_CLASS_NAME ]]; then
        #        get_storage_class_name
        #    fi
        #
        #    select_profile_type
        #    select_iam_default_admin
        #
        #    select_flink_job
        #fi
        check_ocp_version
        validate_docker_podman_cli
        prepare_pattern_file
    fi

    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.license.accept "true"
}

# Function that shows the summary of input options selected
function show_summary(){
    printf "\n"
    printf '%b\n' "\x1B[1m*******************************************************\x1B[0m"
    printf '%b\n' "\x1B[1m                    Summary of input                   \x1B[0m"
    printf '%b\n' "\x1B[1m*******************************************************\x1B[0m"

    printf '%b\n' "${YELLOW_TEXT}1. Platform Type: ${RESET_TEXT}${PLATFORM_SELECTED}"

    if [[ $SELECTED_LDAP == "No" ]]; then
        printf '%b\n' "${YELLOW_TEXT}2. LDAP Type: ${RESET_TEXT}None"
    else
        printf '%b\n' "${YELLOW_TEXT}2. LDAP Type: ${RESET_TEXT}${LDAP_TYPE}"
        printf '%b\n'  "   * ${YELLOW_TEXT}LDAP User Name onboarding Zen:${RESET_TEXT} ${LDAP_USER_NAME}"
    fi

    printf '%b\n' "${YELLOW_TEXT}3. Profile Size: ${RESET_TEXT}${PROFILE_TYPE}"

    if [[ $USE_DEFAULT_IAM_ADMIN == "Yes" ]]; then
        printf '%b\n' "${YELLOW_TEXT}4. IAM default admin user name: ${RESET_TEXT}cpadmin"
    else
        printf '%b\n' "${YELLOW_TEXT}4. IAM default admin user name: ${RESET_TEXT}$NON_DEFAULT_IAM_ADMIN"
    fi


    printf '%b\n' "${YELLOW_TEXT}5. File storage classname(RWX):${RESET_TEXT}"
    printf '%b\n'  "   * ${YELLOW_TEXT}Medium:${RESET_TEXT} ${MEDIUM_STORAGE_CLASS_NAME}"
    printf '%b\n'  "   * ${YELLOW_TEXT}Fast:${RESET_TEXT} ${FAST_STORAGE_CLASS_NAME}"
    printf '%b\n' "${YELLOW_TEXT}6. Block storage classname(RWO): ${RESET_TEXT}${BLOCK_STORAGE_CLASS_NAME}"

    printf '%b\n' "${YELLOW_TEXT}7. Target project for this BAI standalone deployment: ${RESET_TEXT}${TARGET_PROJECT_NAME}"

    printf '%b\n' "${YELLOW_TEXT}9. The Flink job for which components selected: ${RESET_TEXT}"
    if [ "${#flink_job_cr_arr[@]}" -eq "0" ]; then
        printf '   * %s\n' "None"
    else
        for each_flink_job in "${flink_job_cr_arr[@]}"
        do
            if [[ ${each_flink_job} == "flink_job_bpmn" ]]; then
                printf '   * %s\n' "BAW"
            elif [[ ${each_flink_job} == "flink_job_bawadv" ]]
            then
                printf '   * %s\n' "BAW Advanced events"
            elif [[ ${each_flink_job} == "flink_job_icm" ]]
            then
                printf '   * %s\n' "ICM"
            elif [[ ${each_flink_job} == "flink_job_odm" ]]
            then
                printf '   * %s\n' "ODM"
            elif [[ ${each_flink_job} == "flink_job_content" ]]
            then
                printf '   * %s\n' "Content"
            elif [[ ${each_flink_job} == "flink_job_ads" ]]
            then
                printf '   * %s\n' "ADS"
            elif [[ ${each_flink_job} == "flink_job_navigator" ]]
            then
                printf '   * %s\n' "Navigator"
            fi
        done
    fi

    printf '%b\n' "\x1B[1m*******************************************************\x1B[0m"
}


# Function that syncs values into the final CR
function sync_property_into_final_cr(){
    printf "\n"

    wait_msg "Applying value in property file into final CR"

    # Applying platform type in user profile property into final CR
    tmp_platform_value="$(prop_user_profile_property_file BAI_STANDALONE.PLATFORM_TYPE)"
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_deployment_platform \"$tmp_platform_value\"
    # For other type of platform we need to add the below parameters
    # DBACLD-168151
    if [[ $tmp_platform_value == "other" ]]; then
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_cloudpak "true"
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_deployment_hostname_suffix "{{ meta.namespace }}.$OTHER_DOMAIN_NAME"
    fi

    # Applying profile size from user profile property into final CR
    tmp_profile_value="$(prop_user_profile_property_file BAI_STANDALONE.DEPLOYMENT_PROFILE_SIZE)"
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_deployment_profile_size "\"$tmp_profile_value\""

    # Applying global value in user profile property into final CR
    tmp_value="$(prop_user_profile_property_file BAI_STANDALONE.BAI_LICENSE)"
    ${SED_COMMAND} "s|sc_deployment_license:.*|sc_deployment_license: \"$tmp_value\"|g" ${BAI_PATTERN_FILE_TMP}

    # Apply shared_configuration.enable_fips to always be false
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.enable_fips "false"

    
    # Set generate_sample_network_policies
    generate_network_policy_flag="$(prop_user_profile_property_file BAI_STANDALONE.ENABLE_GENERATE_SAMPLE_NETWORK_POLICIES)"
    generate_network_policy_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$generate_network_policy_flag")
    generate_network_policy_flag=$(echo "$generate_network_policy_flag" | tr '[:upper:]' '[:lower:]')
    if [[ ! -z $generate_network_policy_flag ]]; then
        if [[ $generate_network_policy_flag == "true" ]]; then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_generate_sample_network_policies "true"
        else
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_generate_sample_network_policies "false"
        fi
    else
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_generate_sample_network_policies "false"
    fi

    # Set the Instana monitroing eanble/disable flag.
    enable_instana_monitoring_flag="$(prop_user_profile_property_file BAI_STANDALONE.ENABLE_INSTANA_MONITORING)"
    enable_instana_monitoring_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$enable_instana_monitoring_flag")
    enable_instana_monitoring_flag=$(echo "$enable_instana_monitoring_flag" | tr '[:upper:]' '[:lower:]')
    if [[ ! -z $enable_instana_monitoring_flag ]]; then
        if [[ $enable_instana_monitoring_flag == "true" ]]; then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_enable_instana_metric_collection "true"
        else
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_enable_instana_metric_collection "false"
        fi
    else
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_enable_instana_metric_collection "true"
    fi 

    # echo "FAST_STORAGE_CLASS_NAME: $FAST_STORAGE_CLASS_NAME, STORAGE_CLASS_NAME=$STORAGE_CLASS_NAME, MEDIUM_STORAGE_CLASS_NAME=$MEDIUM_STORAGE_CLASS_NAME, BLOCK_STORAGE_CLASS_NAME=$BLOCK_STORAGE_CLASS_NAME, BAI_PATTERN_FILE_TMP=$BAI_PATTERN_FILE_TMP"
    # Set sc_dynamic_storage_classname
    if [[ "$PLATFORM_SELECTED" == "ROKS" ]]; then
        ${SED_COMMAND} "s|sc_dynamic_storage_classname:.*|sc_dynamic_storage_classname: \"${FAST_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
    else
        ${SED_COMMAND} "s|sc_dynamic_storage_classname:.*|sc_dynamic_storage_classname: \"${STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
    fi
    ${SED_COMMAND} "s|sc_medium_file_storage_classname:.*|sc_medium_file_storage_classname: \"${MEDIUM_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s|sc_fast_file_storage_classname:.*|sc_fast_file_storage_classname: \"${FAST_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s|sc_block_storage_classname:.*|sc_block_storage_classname: \"${BLOCK_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}

    # set the sc_iam.default_admin_username
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_iam.default_admin_username "\"$NON_DEFAULT_IAM_ADMIN\""

    if [[ $FIPS_ENABLED == "true" ]]; then
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.enable_fips "true"
    else
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.enable_fips "false"
    fi

    # Applying value in LDAP property file into final CR, if LDAP option was selected
    # DBACLD-168779
    if [[ "$(echo "$selected_ldap_flag" | tr '[:upper:]' '[:lower:]')" == "yes" ]]; then
        for i in "${!LDAP_COMMON_CR_MAPPING[@]}"; do
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} "${LDAP_COMMON_CR_MAPPING[i]}" "\"$(prop_ldap_property_file ${LDAP_COMMON_PROPERTY[i]})\""
        done

        if [[ $LDAP_TYPE == "AD" ]]; then
            for i in "${!AD_LDAP_CR_MAPPING[@]}"; do
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} "${AD_LDAP_CR_MAPPING[i]}" "\"$(prop_ldap_property_file ${AD_LDAP_PROPERTY[i]})\""
            done
        elif [[ $LDAP_TYPE == "TDS" ]]; then
            for i in "${!TDS_LDAP_CR_MAPPING[@]}"; do
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} "${TDS_LDAP_CR_MAPPING[i]}" "\"$(prop_ldap_property_file ${TDS_LDAP_PROPERTY[i]})\""
            done
        # https://jsw.ibm.com/browse/DBACLD-178129 (Remove Custom LDAP type option which was not removed in BAI S scripts)    
        fi

        # set lc_bind_secret
        tmp_secret_name=`${CLI_CMD} get secret -l name=ldap-bind-secret -o yaml | ${YQ_CMD} r - items.[0].metadata.name`
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration.lc_bind_secret "\"$tmp_secret_name\""
    else 
        ${YQ_CMD} d -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration
    fi

    # echo "DOCKER_REG_SERVER=$DOCKER_REG_SERVER, use_entitlement=$use_entitlement, CONVERT_LOCAL_REGISTRY_SERVER=$CONVERT_LOCAL_REGISTRY_SERVER, PLATFORM_SELECTED=$PLATFORM_SELECTED,"
    # Set bai_configuration.admin_user
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.admin_user "$LDAP_USER_NAME"

    # Set flink job for each components
    for each_flink_job in "${flink_job_cr_arr[@]}"
    do
        if [[ ${each_flink_job} == "flink_job_bpmn" ]]; then
            if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
                # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
                # DBACLD-168151
                update_repository_and_tags "spec.bai_configuration.bpmn"
            fi
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.bpmn.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_bawadv" ]]
        then
            if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
                # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
                # DBACLD-168151
                update_repository_and_tags "spec.bai_configuration.bawadv"
            fi
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.bawadv.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_icm" ]]
        then
            if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
                # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
                # DBACLD-168151
                update_repository_and_tags "spec.bai_configuration.icm"
            fi
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.icm.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_odm" ]]
        then
            if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
                # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
                # DBACLD-168151
                update_repository_and_tags "spec.bai_configuration.odm"
            fi
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.odm.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_content" ]]
        then
            if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
                # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
                # DBACLD-168151
                update_repository_and_tags "spec.bai_configuration.content"
            fi
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.content.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_ads" ]]
        then
            if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
                # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
                # DBACLD-168151
                update_repository_and_tags "spec.bai_configuration.ads"
            fi
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.ads.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_navigator" ]]
        then
            if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
                # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
                # DBACLD-168151
                update_repository_and_tags "spec.bai_configuration.navigator"
            fi
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.navigator.install "\"true\""
        fi
    done
    
    # For dev mode only 
    # the function update_repository_and_tags updates the CR with the staging repo and tag for this component for dev mode
    # DBACLD-168151
    if [[ $SCRIPT_MODE == "dev" && $tmp_platform_value == "other" ]]; then
        update_repository_and_tags "spec.bai_configuration.application_setup"
        update_repository_and_tags "spec.bai_configuration.setup"
        update_repository_and_tags "spec.bai_configuration.management"
        update_repository_and_tags "spec.bai_configuration.management.backend"
        update_repository_and_tags "spec.bai_configuration.init_image"
        update_repository_and_tags "spec.bai_configuration.business_performance_center"
        # For dev mode and other type of platform , we need to add the ibm-staging-entitlement-key which will be used to store the cp.stg.icr.io credentials
        # the function update_repository_and_tags updates the CR with the staging repo and tag 
        # DBACLD-168151
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.image_pull_secrets.[1] "ibm-staging-entitlement-key"
        update_repository_and_tags "spec.shared_configuration.images.keytool_init_container"
    fi

    # Remove optional as a value and replacing it as a empty string
    ${SED_COMMAND} "s/: \"<Optional>\"/: \"\"/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"\"<Optional>\"\"/: \"\"/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: <Optional>/: \"\"/g" ${BAI_PATTERN_FILE_TMP}

    ${SED_COMMAND} "s/database_ip: \"<Required>\"/database_ip: \"\"/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/dc_hadr_standby_ip: \"<Required>\"/dc_hadr_standby_ip: \"\"/g" ${BAI_PATTERN_FILE_TMP}


    # comment out sc_ingress_tls_secret_name if OCP platform
    if [[ $PLATFORM_SELECTED == "OCP" ]]; then
        ${SED_COMMAND} "s/sc_ingress_tls_secret_name: /# sc_ingress_tls_secret_name: /g" ${BAI_PATTERN_FILE_TMP}
    fi

    if [[ "$PLATFORM_SELECTED" == "ROKS" || "$PLATFORM_SELECTED" == "OCP" ]]; then
        use_entitlement="yes"
    fi

    # set sc_image_repository
    if [ "$use_entitlement" = "yes" ] ; then
        ${SED_COMMAND} "s|sc_image_repository:.*|sc_image_repository: ${DOCKER_REG_SERVER}|g" ${BAI_PATTERN_FILE_TMP}
    else
        ${SED_COMMAND} "s|sc_image_repository:.*|sc_image_repository: ${CONVERT_LOCAL_REGISTRY_SERVER}|g" ${BAI_PATTERN_FILE_TMP}
    fi

    if [[ ! "$SCRIPT_MODE" == "dev" ]]; then
        # Replace image URL
        old_initcontainer="$REGISTRY_IN_FILE\/cp\/cp4a\/bai"
        
        if [ "$use_entitlement" = "yes" ] ; then
            ${SED_COMMAND} "s/$REGISTRY_IN_FILE/$DOCKER_REG_SERVER/g" ${BAI_PATTERN_FILE_TMP}
        else
            ${SED_COMMAND} "s/$old_initcontainer/$CONVERT_LOCAL_REGISTRY_SERVER/g" ${BAI_PATTERN_FILE_TMP}
        fi
    fi

    # ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_BAK}
    success "All values in the property file have been applied in the final CR under $FINAL_CR_FOLDER"
    msgB "Confirm final custom resource under $FINAL_CR_FOLDER"
}


# Main Function to create the final CR for BAI Standalone
function apply_bai_final_cr(){

    # Keep existing value
    # This IF condition never gets executed anymore, keeping it only in case we change something
    #if [[ "${INSTALLATION_TYPE}" == "existing" ]]; then
    #    # read -rsn1 -p"Before Merge: Press Enter/Return to continue";echo
    #    ${YQ_CMD} d -i ${BAI_EXISTING_TMP} spec.shared_configuration.sc_deployment_patterns
    #    ${YQ_CMD} d -i ${BAI_EXISTING_TMP} spec.shared_configuration.sc_optional_components
    #    ${SED_COMMAND} '/tag: /d' ${BAI_EXISTING_TMP}
    #    ${SED_COMMAND} '/appVersion: /d' ${BAI_EXISTING_TMP}
    #    ${SED_COMMAND} '/release: /d' ${BAI_EXISTING_TMP}
    #    # ${YQ_CMD} m -a -i -M ${BAI_EXISTING_BAK} ${BAI_PATTERN_FILE_TMP}
    #    # ${COPY_CMD} -rf ${BAI_EXISTING_BAK} ${BAI_PATTERN_FILE_TMP}
    #    # ${YQ_CMD} m -a -i -M ${BAI_PATTERN_FILE_TMP} ${BAI_EXISTING_BAK}
    #    # read -rsn1 -p"After Merge: Press Enter/Return to continue";echo
    #fi

    ${SED_COMMAND_FORMAT} ${BAI_PATTERN_FILE_TMP}

    # Apply value in property file into final cr
    sync_property_into_final_cr

    # Format values of the CR
    ${YQ_CMD} d -i ${BAI_PATTERN_FILE_TMP} null
    ${SED_COMMAND} "s|'\"|\"|g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s|\"'|\"|g" ${BAI_PATTERN_FILE_TMP}

    # convert ssl enable true or false to meet CSV
    ${SED_COMMAND} "s/: \"True\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"False\"/: false/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"true\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"false\"/: false/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"Yes\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"yes\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"No\"/: false/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"no\"/: false/g" ${BAI_PATTERN_FILE_TMP}

    # remove ldap_configuration when select LDAP is false for BAI standalone
    if [[ $SELECTED_LDAP == "No" ]]; then
        ${YQ_CMD} d -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration
    fi

    ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_BAK}

    ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_FINAL}

    printf '%b\n' "\x1B[1mThe custom resource file used is: \"${BAI_PATTERN_FILE_FINAL}\"\x1B[0m"
    printf "\n"
    printf '%b\n' "\x1B[1mTo monitor the deployment status, follow the Operator logs.\x1B[0m"
    printf '%b\n' "\x1B[1mFor details, refer to the troubleshooting section in Knowledge Center here: \x1B[0m"
    printf '%b\n' "\x1B[1m https://www.ibm.com/docs/en/bai/$BAI_RELEASE_BASE?topic=troubleshooting \x1B[0m"

    # For platform type other, we are displaying the next steps on how to generate ingress templates to be applied
    if [[ "$PLATFORM_SELECTED" == "other" ]]; then
        echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
        step_num=1
        printf "\n"
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}:Once the BAI Standalone custom resource file has been applied, monitor the Insights Engine Operator logs and the status section of the Insights Engine CR to make sure the components are being installed."
        echo "The status of BAI Standalone components can be checked by executing \"${CLI_CMD} get InsightsEngine -o json | grep -A100 \"status\" \" "
        step_num=$((step_num + 1))
        printf "\n"
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: After the components have been installed , You can execute ./bai-deployment.sh to create the required ingresses for your platform."
        info "  If you are using a Other - Cloud Native Computing Foundation ( CNCF ) type cluster ,run ${GREEN_TEXT}\" ./bai-deployment.sh --ingress -n $TARGET_PROJECT_NAME\"${RESET_TEXT}"
        printf "\n"
        
    fi

}


#### End - Functions being called by the fresh_install function ####

# Main handler function for performing the steps required to generate the CR for fresh install of BAI Standalone
function fresh_install(){
    
    # This function definition is in common.sh
    prompt_license "Starting the script to generate the IBM Business Automation Insights standalone custom resource file..." "https://www.ibm.com/support/customer/csol/terms/?id=L-UXBF-EQ4UGB"


    DEPLOYMENT_WITH_PROPERTY="Yes"
    # Check cluster login
    check_cluster_login # Function definition is in common.sh

    input_information # Function definition is in fresh-install.sh

    show_summary

    while true; do

        printf "\n"
        printf "\x1B[1mVerify that the information above is correct.\n\x1B[0m"
        printf "\x1B[1mTo proceed with the deployment, enter \"Yes\".\n\x1B[0m"
        printf "\x1B[1mTo make changes, enter \"No\" (default: No): \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            if [[ ("$SCRIPT_MODE" != "review") && ("$SCRIPT_MODE" != "OLM") ]]; then
                if [[ $DEPLOYMENT_TYPE == "production" ]];then
                    printf "\n"
                    printf '%b\n' "\x1B[1mCreating the Custom Resource of the IBM Business Automation Insights standalone Operator...\x1B[0m"
                fi
            fi
            printf "\n"
            if [[ "${INSTALLATION_TYPE}"  == "new" ]]; then
                if [[ "$SCRIPT_MODE" == "review" ]]; then
                    printf '%b\n' "\x1B[1mReview mode running, just generate final CR, will not deploy operator\x1B[0m"
                    # prompt_press_any_key_to_continue
                elif [[ "$SCRIPT_MODE" == "OLM" ]]
                then
                    printf '%b\n' "\x1B[1mA custom resource file to apply in the OCP Catalog is being generated.\x1B[0m"
                    # prompt_press_any_key_to_continue
                else
                    if [ "$use_entitlement" = "no" ] ; then
                        isReady=$(${CLI_CMD} get secret | grep ibm-entitlement-key)
                        if [[ -z $isReady ]]; then
                            echo "Secret \"ibm-entitlement-key\" not found, exiting..."
                            exit 1
                        else
                            echo "Secret \"ibm-entitlement-key\" found, continuing...."
                        fi
                    fi
                fi
            fi
            apply_bai_final_cr
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|*)
            while true; do
                printf "\n"
                show_summary
                printf "\n"

                printf "\x1B[1mEnter the number from 1 to 9 that you want to change: \x1B[0m"

                read -rp "" ans
                case "$ans" in
                "1")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_platform
                    else
                        info "Run bai-prerequisites.sh to modify the platform type"
                        prompt_press_any_key_to_continue
                    fi
                    break
                    ;;
                "2")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_ldap_type
                    else
                        info "Run bai-prerequisites.sh to modify the LDAP type"
                        prompt_press_any_key_to_continue
                    fi
                    break
                    ;;
                "3")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_profile_type
                    else
                        info "Run bai-prerequisites.sh to modify the profile size"
                        prompt_press_any_key_to_continue
                    fi
                    break
                    ;;
                "4")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_iam_default_admin
                    else
                        info "Run bai-prerequisites.sh to modify the IAM default admin"
                        prompt_press_any_key_to_continue
                    fi
                    break
                    ;;
                "5"|"6")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        get_storage_class_name
                    else
                        info "Run bai-prerequisites.sh to modify the storage class"
                        prompt_press_any_key_to_continue
                    fi
                    break
                    ;;
                "7")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        TARGET_PROJECT_NAME=""
                        select_project
                    else
                        info "Run bai-prerequisites.sh to modify the target project"
                        prompt_press_any_key_to_continue
                    fi
                    break
                    ;;
                "8")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_flink_job
                    else
                        info "Run bai-prerequisites.sh to modify the flink job for which component(s)"
                        prompt_press_any_key_to_continue
                    fi
                    break
                    ;;
                *)
                    printf '%b\n' "\x1B[1mEnter a valid number [1 to 9] \x1B[0m"
                    ;;
                esac
            done
            show_summary
            ;;
        esac
    done
}
