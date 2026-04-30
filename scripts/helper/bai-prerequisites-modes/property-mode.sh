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


# This file is a helper script used to store all functions that are used by the bai-prerequistes.sh in the property mode


#### Start - Functions being called by the input_information function ####

# Function to select the platform type being used
# This function is called by the input_information function
function select_platform(){
    printf "\n"
    printf '%b\n' "\x1B[1mSelect the cloud platform to deploy: \x1B[0m"
    COLUMNS=12
    # options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "Other ( Certified Kubernetes Cloud Platform / CNCF)")
    # PS3='Enter a valid option [1 to 3]: '

    #Adding support for the other type of platform
    # DBACLD-168151
    otheroption="Other - Cloud Native Computing Foundation ( CNCF )"
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
}

# Function to select if LDAP is required
# This function is called by the input_information function
function select_ldap_type(){
    printf "\n"
    SELECTED_LDAP="Yes" # Setting the default value of selected LDAP to true since that is the default value
    while true; do
        printf "\x1B[1mDo you want to configure an LDAP for this IBM Business Automation Insights stand-alone deployment? (Yes/No, default: Yes): \x1B[0m"
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

        msgRed "You can change the parameter \"LDAP_SSL_ENABLED\" in the property file \"$LDAP_PROPERTY_FILE\" later. \"LDAP_SSL_ENABLED\" is \"TRUE\" by default."
    fi
}

# This is a function to enter the ldap user name for onboarding Zen
# Function is called only when LDAP option is selected
# Function is called by select_ldap_type
function select_ldap_user_for_zen(){
    printf "\n"
    LDAP_USER_NAME=""

    printf '%b\n'  "${YELLOW_TEXT}For BAI stand-alone, if you select LDAP, then provide one ldap user here for onboarding ZEN.${RESET_TEXT}"    
    while [[ $LDAP_USER_NAME == "" ]] # While get medium storage clase name
    do
        printf "\x1B[1mPlease enter one LDAP user for BAI stand-alone: \x1B[0m"
        read -rp "" LDAP_USER_NAME
        if [ -z "$LDAP_USER_NAME" ]; then
        printf '%b\n' "\x1B[1;31mEnter a valid LDAP user\x1B[0m"
        fi
    done
}

# Function to select the storage class to be used
# This function is called by the input_information function
function select_storage_class(){
    printf "\n"
    storage_class_name=""
    block_storage_class_name=""
    sc_slow_file_storage_classname=""
    sc_medium_file_storage_classname=""
    sc_fast_file_storage_classname=""
    local sample_pvc_name=""

    printf "\n"
    printf "\x1B[1mTo provision the persistent volumes and volume claims\n\x1B[0m"
    
    while [[ $sc_medium_file_storage_classname == "" ]] # While get medium storage clase name
    do
        printf "\x1B[1mPlease enter the file storage classname for medium storage(RWX): \x1B[0m"
        read -rp "" sc_medium_file_storage_classname
        if [ -z "$sc_medium_file_storage_classname" ]; then
        printf '%b\n' "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done

    while [[ $sc_fast_file_storage_classname == "" ]] # While get fast storage clase name
    do
        printf "\x1B[1mPlease enter the file storage classname for fast storage(RWX): \x1B[0m"
        read -rp "" sc_fast_file_storage_classname
        if [ -z "$sc_fast_file_storage_classname" ]; then
        printf '%b\n' "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done

    while [[ $block_storage_class_name == "" ]] # While get block storage clase name
    do
        printf "\x1B[1mPlease enter the block storage classname for Zen(RWO): \x1B[0m"
        read -rp "" block_storage_class_name
        if [ -z "$block_storage_class_name" ]; then
        printf '%b\n' "\x1B[1;31mEnter a valid block storage classname(RWO)\x1B[0m"
        fi
    done

    STORAGE_CLASS_NAME=${storage_class_name}
    SLOW_STORAGE_CLASS_NAME=${sc_slow_file_storage_classname}
    MEDIUM_STORAGE_CLASS_NAME=${sc_medium_file_storage_classname}
    FAST_STORAGE_CLASS_NAME=${sc_fast_file_storage_classname}
    BLOCK_STORAGE_CLASS_NAME=${block_storage_class_name}
}


# Function to select the profile type for the deployment
# This function is called by the input_information function
function select_profile_type(){
    printf "\n"
    COLUMNS=12
    PROFILE_TYPE="small" # Question defaults to small so initializing this value to small
    printf '%b\n' "\x1B[1mPlease select the deployment profile (default: small).  Refer to the documentation in BAI stand-alone Knowledge Center for details on profile.\x1B[0m"
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
# This function is called by the input_information function
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

# Function that generates asks the user if they want to generate sample network policies
function generate_sample_network_policies(){
    printf "\n"
    echo ""
    while true; do
        printf "\x1B[1mDo you want to generate the network policy templates for this BAI stand-alone deployment?\x1B[0m ${YELLOW_TEXT}(Notes: Starting from $BAI_RELEASE_BASE, the BAI stand-alone operators no longer install network policies automatically. If you want the operators to generate network policies from a set of templates, select Yes. You can install the network policies by running a script after the BAI Deployment is installed. If you select No, then no network policies will be generated.)${RESET_TEXT} (Yes/No, default: No):" 
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            GENERATE_SAMPLE_NETWORK_POLICIES="true"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            GENERATE_SAMPLE_NETWORK_POLICIES="false"
            break
            ;;
        *)
            printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

# Function that asks the user if they want to enable Instana monitoring
function enable_instana_monitoring(){
    printf "\n"
    echo ""
    while true; do
        printf "\x1B[1mDo you want to enable the Instana Monitoring for this BAI stand-alone deployment?\x1B[0m ${YELLOW_TEXT}(Notes: If you want the operators to enable the Instana monitoring for this bai deployment, select Yes.)${RESET_TEXT} (Yes/No, default: No):" 
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            ENABLE_INSTANA_MONITORING="true"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            ENABLE_INSTANA_MONITORING="false"
            break
            ;;
        *)
            printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}



#IM ZEN and BTS should be asked at the same time
#DBACLD-194974
function select_external_postgresdb_for_im_zen_bts(){
    printf "\n"
    echo ""
    while true; do
        #DBACLD-194974: Since there no EDB, we won't ask customer whether they want to use external Postgres DB for IM/Zen/BTS.  They must use external Postgres DB if they want to install IM/Zen for 25.0.1-GA
        # Display Knowledge Center link once
        echo "${GREEN_TEXT}Please refer to the Knowledge Center links listed below to create databases required for IM, Zen & BTS: ${RESET_TEXT}"
        echo "    - https://www.ibm.com/docs/en/cloud-paks/foundational-services/$CS_CHANNEL_KC?topic=im-setting-up-external-edb-postgresql-database-server#dbcreate${RESET_TEXT}"
        echo "    - https://www.ibm.com/docs/en/cloud-paks/foundational-services/$CS_CHANNEL_KC?topic=service-external-database#configuring-an-external-database-with-the-bts-custom-resource${RESET_TEXT}"
        echo
        
        if skip_edb_for_2501; then
            printf "\x1B[1m${YELLOW_TEXT}ATTENTION:${RESET_TEXT} For the version "$BAI_RELEASE_BASE"-"$BAI_PATCH_VERSION", you must use an external Postgres DB \x1B[0m[${RED_TEXT}YOU NEED TO CREATE THE POSTGRESQL DBs BY YOURSELF FIRST BEFORE APPLYING THE BAI Standalone CUSTOM RESOURCE${RESET_TEXT}] \x1B[1mfor IM, Zen and BTS services in this BAI Standalone deployment.\x1B[0m"
            printf "\n"
            ans="Yes"
            EXTERNAL_POSTGRESDB_FOR_IM="true"
            EXTERNAL_POSTGRESDB_FOR_ZEN="true"
            EXTERNAL_POSTGRESDB_FOR_BTS="true"
            prompt_press_any_key_to_continue
            break
        else
            printf "\x1B[1mDo you want to use an external Postgres DB for IM , Zen and BTS \x1B[0m[${RED_TEXT}YOU NEED TO CREATE THE POSTGRESQL DBs BY YOURSELF FIRST BEFORE APPLYING THE BAI Standalone CUSTOM RESOURCE${RESET_TEXT}] \x1B[1m for the IM, Zen and BTS services in this BAI Standalone deployment?\x1B[0m (Yes/No, default: No): "
            read -rp "" ans

            ans=$(echo "$ans" | tr '[:upper:]' '[:lower:]')

            case "$ans" in
            "y"|"yes")
                EXTERNAL_POSTGRESDB_FOR_IM="true"
                EXTERNAL_POSTGRESDB_FOR_ZEN="true"
                EXTERNAL_POSTGRESDB_FOR_BTS="true"
                break
                ;;
            "n"|"no"|"")
                EXTERNAL_POSTGRESDB_FOR_IM="false"
                EXTERNAL_POSTGRESDB_FOR_ZEN="false"
                EXTERNAL_POSTGRESDB_FOR_BTS="false"
                break
                ;;
            *)
                printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        fi
    done
}


# Function to display Multi select menu being used to allow the user to select the different components flink should be enabled for
# If no boxes are selected then no components are selected
# This function is called by the input_information function
function select_flink_job(){
    FLINK_JOB_SELECTED=""
    choices_pattern=()
    flink_job_arr=()
    flink_job_cr_arr=()

    options=("BAW" "BAW Advanced events" "ICM" "ODM" "Content" "ADS" "Navigator")
    options_cr_val=("flink_job_bpmn" "flink_job_bawadv" "flink_job_icm" "flink_job_odm" "flink_job_content" "flink_job_ads" "flink_job_navigator")

    patter_ent_input_array=("1" "2" "3" "4" "5" "6" "7")
    tips1="\x1B[1;31mTips\x1B[0m:\x1B[1mPress [ENTER] to accept the default (None of the components are selected)\x1B[0m"
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
        printf '%b\n' "\x1B[1mFor which components do you want to enable the Flink job for: \x1B[0m"
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
        warning "None of the components were selected for the Flink job. Continuing... \n"
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

# Function to create the temporary property file , used internally by the script to do additional validation and carry over parameters being used
# This function is called by the input_information function
function create_temp_property_file(){
    # Convert pattern array to pattern list by common
    delim=""
    pattern_joined=""
    for item in "${FLINK_JOB_CR_SELECTED[@]}"; do
        if [[ "${DEPLOYMENT_TYPE}" == "starter" ]]; then
            pattern_joined="$pattern_joined$delim$item"
            delim=","
        elif [[ ${DEPLOYMENT_TYPE} == "production" ]]
        then
            case "$item" in
            *)
                pattern_joined="$pattern_joined$delim$item"
                delim=","
                ;;
            esac
        fi
    done
    # pattern_joined="foundation$delim$pattern_joined"

   # Convert pattern display name array to list by common
    delim=""
    pattern_name_joined=""
    for item in "${flink_job_arr[@]}"; do
        pattern_name_joined="$pattern_name_joined$delim$item"
        delim=","
    done

   # Convert optional components array to list by common
    delim=""
    opt_components_joined=""
    for item in "${OPT_COMPONENTS_CR_SELECTED[@]}"; do
        opt_components_joined="$opt_components_joined$delim$item"
        delim=","
    done

   # Convert optional components name to list by common
    delim=""
    opt_components_name_joined=""
    for item in "${optional_component_arr[@]}"; do
        opt_components_name_joined="$opt_components_name_joined$delim$item"
        delim=","
    done

    
   # Convert foundation array to list by common
    delim=""
    foundation_components_joined=""
    for item in "${foundation_component_arr[@]}"; do
        foundation_components_joined="$foundation_components_joined$delim$item"
        delim=","
    done

    # Keep pattern_joined value in temp property file
    rm -rf $TEMPORARY_PROPERTY_FILE >/dev/null 2>&1
    mkdir -p $TEMP_FOLDER >/dev/null 2>&1
    > $TEMPORARY_PROPERTY_FILE
    # save pattern list
    echo "PATTERN_LIST=$pattern_joined" >> ${TEMPORARY_PROPERTY_FILE}
    
    # same pattern name list
    echo "PATTERN_NAME_LIST=$pattern_name_joined" >> ${TEMPORARY_PROPERTY_FILE}

    # save foundation list
    echo "FOUNDATION_LIST=$foundation_components_joined" >> ${TEMPORARY_PROPERTY_FILE}

    # save components list
    if [ "${#optional_component_cr_arr[@]}" -eq "0" ]; then
        echo "OPTION_COMPONENT_LIST=" >> ${TEMPORARY_PROPERTY_FILE}
        echo "OPTION_COMPONENT_NAME_LIST=" >> ${TEMPORARY_PROPERTY_FILE}
    else
        echo "OPTION_COMPONENT_LIST=$opt_components_joined" >> ${TEMPORARY_PROPERTY_FILE}
        echo "OPTION_COMPONENT_NAME_LIST=$opt_components_name_joined" >> ${TEMPORARY_PROPERTY_FILE}
    fi
    # save ldap selected
    echo "SELECTED_LDAP_FLAG=$SELECTED_LDAP" >> ${TEMPORARY_PROPERTY_FILE}

    # save ldap type
    echo "LDAP_TYPE=$LDAP_TYPE" >> ${TEMPORARY_PROPERTY_FILE}

    # save fips enabled flag 
    echo "FIPS_ENABLED_FLAG=false" >> ${TEMPORARY_PROPERTY_FILE}

    # save external Postgres DB as IM metastore DB flag
    if [[ $EXTERNAL_POSTGRESDB_FOR_IM == "true" ]]; then
        echo "EXTERNAL_POSTGRESDB_FOR_IM_FLAG=true" >> ${TEMPORARY_PROPERTY_FILE}
    else
        echo "EXTERNAL_POSTGRESDB_FOR_IM_FLAG=false" >> ${TEMPORARY_PROPERTY_FILE}
    fi

    # save external Postgres DB as Zen metastore DB flag
    if [[ $EXTERNAL_POSTGRESDB_FOR_ZEN == "true" ]]; then
        echo "EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG=true" >> ${TEMPORARY_PROPERTY_FILE}
    else
        echo "EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG=false" >> ${TEMPORARY_PROPERTY_FILE}
    fi

    # save external Postgres DB as BTS metastore DB flag
    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS == "true" ]]; then
        echo "EXTERNAL_POSTGRESDB_FOR_BTS_FLAG=true" >> ${TEMPORARY_PROPERTY_FILE}
    else
        echo "EXTERNAL_POSTGRESDB_FOR_BTS_FLAG=false" >> ${TEMPORARY_PROPERTY_FILE}
    fi

    # save profile size 
    echo "PROFILE_SIZE_FLAG=$PROFILE_TYPE" >> ${TEMPORARY_PROPERTY_FILE}
}

#### End - Functions being called by the input_information function ####


# Function to input the required information to generate the required property files
function input_information(){
    EXISTING_OPT_COMPONENT_ARR=()
    EXISTING_PATTERN_ARR=()
    retVal_baw=1
    # rm -rf $TEMPORARY_PROPERTY_FILE >/dev/null 2>&1
    DEPLOYMENT_TYPE="production"
    PLATFORM_SELECTED="OCP"
    select_platform
    select_ldap_type
    select_storage_class
    select_profile_type
    select_iam_default_admin
    generate_sample_network_policies
    enable_instana_monitoring
    select_external_postgresdb_for_im_zen_bts
    select_flink_job
    create_temp_property_file
}

#### Begin - Functions being called by the create_property_file function ####

# Function that creates the LDAP property file if required
# This function is called by create_property_file
function create_ldap_property_file(){
    mkdir -p $LDAP_SSL_CERT_FOLDER >/dev/null 2>&1
    > ${LDAP_PROPERTY_FILE}
    wait_msg "Creating LDAP Server property file for BAI stand-alone"
    
    tip="## Property file for ${LDAP_TYPE} ##"

    echo "###########################" >> ${LDAP_PROPERTY_FILE}
    echo "$tip" >> ${LDAP_PROPERTY_FILE}
    echo "###########################" >> ${LDAP_PROPERTY_FILE}
    for i in "${!LDAP_COMMON_PROPERTY[@]}"; do
        echo "${COMMENTS_LDAP_PROPERTY[i]}" >> ${LDAP_PROPERTY_FILE}
        echo "${LDAP_COMMON_PROPERTY[i]}=\"\"" >> ${LDAP_PROPERTY_FILE}
        echo "" >> ${LDAP_PROPERTY_FILE}
    done
    if [[ $LDAP_TYPE == "AD" ]]; then
        ${SED_COMMAND} "s|LDAP_TYPE=\"\"|LDAP_TYPE=\"Microsoft Active Directory\"|g" ${LDAP_PROPERTY_FILE}
        for i in "${!AD_LDAP_PROPERTY[@]}"; do
            echo "${COMMENTS_AD_LDAP_PROPERTY[i]}" >> ${LDAP_PROPERTY_FILE}
            echo "${AD_LDAP_PROPERTY[i]}=\"\"" >> ${LDAP_PROPERTY_FILE}
            echo "" >> ${LDAP_PROPERTY_FILE}
        done
    elif [[ $LDAP_TYPE == "TDS" ]]; then
        ${SED_COMMAND} "s|LDAP_TYPE=\"\"|LDAP_TYPE=\"IBM Security Directory Server\"|g" ${LDAP_PROPERTY_FILE}
        for i in "${!TDS_LDAP_PROPERTY[@]}"; do
            echo "${COMMENTS_TDS_LDAP_PROPERTY[i]}" >> ${LDAP_PROPERTY_FILE}
            echo "${TDS_LDAP_PROPERTY[i]}=\"\"" >> ${LDAP_PROPERTY_FILE}
            echo "" >> ${LDAP_PROPERTY_FILE}
        done
    # https://jsw.ibm.com/browse/DBACLD-178129 (Remove Custom LDAP type option which was not removed in BAI S scripts)
    #Removed the else part here
    fi
    # Set default value
    ${SED_COMMAND} "s|LDAP_SSL_ENABLED=\"\"|LDAP_SSL_ENABLED=\"True\"|g" ${LDAP_PROPERTY_FILE}
    ${SED_COMMAND} "s|LDAP_SSL_SECRET_NAME=\"\"|LDAP_SSL_SECRET_NAME=\"ibm-bai-ldap-ssl-secret\"|g" ${LDAP_PROPERTY_FILE}
    ${SED_COMMAND} "s|LDAP_SSL_CERT_FILE_FOLDER=\"\"|LDAP_SSL_CERT_FILE_FOLDER=\"${LDAP_SSL_CERT_FOLDER}\"|g" ${LDAP_PROPERTY_FILE}
    ${SED_COMMAND} "s|<LDAP_SSL_CERT_FOLDER>|\"${LDAP_SSL_CERT_FOLDER}\"|g" ${LDAP_PROPERTY_FILE}
    if [[ $LDAP_TYPE == "AD" ]]; then
        ${SED_COMMAND} "s|LDAP_USER_NAME_ATTRIBUTE=\"\"|LDAP_USER_NAME_ATTRIBUTE=\"user:sAMAccountName\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_USER_DISPLAY_NAME_ATTR=\"\"|LDAP_USER_DISPLAY_NAME_ATTR=\"sAMAccountName\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_NAME_ATTRIBUTE=\"\"|LDAP_GROUP_NAME_ATTRIBUTE=\"*:cn\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_DISPLAY_NAME_ATTR=\"\"|LDAP_GROUP_DISPLAY_NAME_ATTR=\"cn\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"\"|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"(\&(cn=%v)(objectcategory=group))\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_MEMBER_ID_MAP=\"\"|LDAP_GROUP_MEMBER_ID_MAP=\"memberOf:member\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LC_USER_FILTER=\"\"|LC_USER_FILTER=\"(\&(sAMAccountName=%v)(objectcategory=user))\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LC_GROUP_FILTER=\"\"|LC_GROUP_FILTER=\"(\&(cn=%v)(objectcategory=group))\"|g" ${LDAP_PROPERTY_FILE}
        # For https://jsw.ibm.com/browse/DBACLD-178021 where the GC PORT and GC HOST should be empty value. 
        ${SED_COMMAND} 's|LC_AD_GC_HOST=\"<Required>\"|LC_AD_GC_HOST=\"\"|g' ${LDAP_PROPERTY_FILE}
        OPTIONAL_PARAMETERS_LIST+=("LC_AD_GC_HOST")
        ${SED_COMMAND} "s|LC_AD_GC_PORT=\"<Required>\"|LC_AD_GC_PORT=\"\"|g" ${LDAP_PROPERTY_FILE}
        OPTIONAL_PARAMETERS_LIST+=("LC_AD_GC_PORT")
    elif [[ $LDAP_TYPE == "TDS" ]]; then
        ${SED_COMMAND} "s|LDAP_USER_NAME_ATTRIBUTE=\"\"|LDAP_USER_NAME_ATTRIBUTE=\"*:uid\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_USER_DISPLAY_NAME_ATTR=\"\"|LDAP_USER_DISPLAY_NAME_ATTR=\"cn\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_NAME_ATTRIBUTE=\"\"|LDAP_GROUP_NAME_ATTRIBUTE=\"*:cn\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_DISPLAY_NAME_ATTR=\"\"|LDAP_GROUP_DISPLAY_NAME_ATTR=\"cn\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"\"|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"(\|(\&(objectclass=groupofnames)(member={0}))(\&(objectclass=groupofuniquenames)(uniquemember={0})))\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_MEMBER_ID_MAP=\"\"|LDAP_GROUP_MEMBER_ID_MAP=\"groupofnames:member\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LC_USER_FILTER=\"\"|LC_USER_FILTER=\"(\&(cn=%v)(objectclass=person))\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LC_GROUP_FILTER=\"\"|LC_GROUP_FILTER=\"(\&(cn=%v)(\|(objectclass=groupofnames)(objectclass=groupofuniquenames)(objectclass=groupofurls)))\"|g" ${LDAP_PROPERTY_FILE}
    # https://jsw.ibm.com/browse/DBACLD-178129 (Remove Custom LDAP type option which was not removed in BAI S scripts)
    # Removed the else part here
    fi
    # For https://jsw.ibm.com/browse/DBACLD-154784 The error should be thrown when we select 'yes' to configure one LDAP.
    # Convert SELECTED_LDAP to lowercase so that it will match any variation of "yes"
    if [[ "$(echo "${SELECTED_LDAP}" | tr '[:upper:]' '[:lower:]')" == "yes" ]]; then
        ${SED_COMMAND} "s|LDAP_BIND_DN_PASSWORD=\"\"|LDAP_BIND_DN_PASSWORD=\"{Base64}<Required>\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_SERVER=\"\"|LDAP_SERVER=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_PORT=\"\"|LDAP_PORT=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_BASE_DN=\"\"|LDAP_BASE_DN=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_BIND_DN=\"\"|LDAP_BIND_DN=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|LDAP_GROUP_BASE_DN=\"\"|LDAP_GROUP_BASE_DN=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
    fi
    
    # Marks all entries in "OPTIONAL_PARAMETERS_LIST" as optional by appending them to the TEMPORARY_PROPERTY_FILE under "OPTIONAL_PARAMETERS:"
    mark_optional

    success "Created the LDAP Server property file for BAI stand-alone\n"
}

# Function that creates the user property file
# Called by create_property_file function
function create_user_property_file(){

    # Add global property into user_profile for BAI stand-alone
    tip="##           USER Property for BAI stand-alone               ##"
    echo "####################################################" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "$tip" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "####################################################" >> ${USER_PROFILE_PROPERTY_FILE}
    # license
    echo "## Use this parameter to specify the license for the BAI stand-alone deployment and" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## the possible values are: non-production and production and if not set, the license will" >> ${USER_PROFILE_PROPERTY_FILE}        
    echo "## be defaulted to production.  This value could be different from the other licenses in the CR." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.BAI_LICENSE=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    echo "## If the platform to be deployed is Other - Cloud Native Computing Foundation ( CNCF ), specify 'other' for the Platform type." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.PLATFORM_TYPE=\"$PLATFORM_SELECTED\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "" >> ${USER_PROFILE_PROPERTY_FILE} 

    echo "## On OCP 3.x and 4.x, the User script will populate these three (3) parameters based on your input for \"production\" deployment." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## If you manually deploying without using the User script, then you would provide the different storage classes for the slow, medium" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## and fast storage parameters below.  If you only have 1 storage class defined, then you can use that 1 storage class for all 3 parameters." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## sc_block_storage_classname is for Zen, Zen requires/recommends block storage (RWO) for metastoreDB" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.MEDIUM_FILE_STORAGE_CLASSNAME=\"$MEDIUM_STORAGE_CLASS_NAME\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.FAST_FILE_STORAGE_CLASSNAME=\"$FAST_STORAGE_CLASS_NAME\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.BLOCK_STORAGE_CLASS_NAME=\"$BLOCK_STORAGE_CLASS_NAME\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    echo "## Specify a profile size for BAI stand-alone deployment (valid values are small,medium,large - default is small)." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.DEPLOYMENT_PROFILE_SIZE=\"$PROFILE_TYPE\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    echo "## Provide non default admin user for IAM in case you do not want to use \"cpadmin\"." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ $USE_DEFAULT_IAM_ADMIN == "Yes" ]]; then
        echo "BAI_STANDALONE.IAM_ADMIN_USER_NAME=\"cpadmin\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.IAM_ADMIN_USER_NAME=\"$NON_DEFAULT_IAM_ADMIN\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    if [[ $SELECTED_LDAP == "Yes" ]]; then
        echo "## For BAI stand-alone, if you select LDAP, then provide one ldap user here for onboarding ZEN." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI_STANDALONE.LDAP_USER_NAME_ONBOARDING_ZEN=\"$LDAP_USER_NAME\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    # The below code will capture the GENERATE_SAMPLE_NETWORK_POLICIES value for the bai-deployment script  
    echo "BAI_STANDALONE.ENABLE_GENERATE_SAMPLE_NETWORK_POLICIES=\"$GENERATE_SAMPLE_NETWORK_POLICIES\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    # The below code will capture the ENABLE_INSTANA_MONITORING value for the bai-deployment script
    echo "## Enable or disable Instana instrumentation for bai deployment." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.ENABLE_INSTANA_MONITORING=\"$ENABLE_INSTANA_MONITORING\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    # For other type of platform we also need the DOMAIN_NAME
    # We are getting this value from the ibm-cpp-config map which is created during the execution of bai-clusteradmin-setup.sh
    # DBACLD-168151
    if [[ $PLATFORM_SELECTED == "other" ]]; then
        get_domain_name $TARGET_PROJECT_NAME "ibm-cpp-config"
        echo "## For Platform type as Other - Cloud Native Computing Foundation ( CNCF ), provide the domain name (e.g., acme.com) for your cluster (This is the ingress that must be created and provided as a prerequisite for the deployment)." >> ${USER_PROFILE_PROPERTY_FILE}
        if [[ -z $domain_name ]]; then
            echo "BAI_STANDALONE.DOMAIN_NAME=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
        else
            echo "BAI_STANDALONE.DOMAIN_NAME=\"$domain_name\"" >> ${USER_PROFILE_PROPERTY_FILE}
        fi
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    fi

    if [[ $EXTERNAL_POSTGRESDB_FOR_IM == "true" ]]; then
        rm -rf $IM_DB_SSL_CERT_FOLDER >/dev/null 2>&1
        mkdir -p $IM_DB_SSL_CERT_FOLDER >/dev/null 2>&1
        echo "## Configuration for external Postgres DB as IM metastore DB." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "## YOU NEED TO CREATE THIS POSTGRES DB BY YOURSELF FISTLY BEFORE APPLY BAI CUSTOM RESOURCE." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "## NOTES: " >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   YOU NEED TO CREATE THIS POSTGRES DB BY YOURSELF FISTLY BEFORE APPLY BAI CUSTOM RESOURCE." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   1. Postgres version is 14.7 or higher and 16.x." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   2. Client certificate based authentication is configured on the DB server." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   3. Client certificate rotation is managed by the customer." >> ${USER_PROFILE_PROPERTY_FILE}
        
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from server and client, and copy into this directory.Default value is \"$IM_DB_SSL_CERT_FOLDER\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER=\"$IM_DB_SSL_CERT_FOLDER\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database user. The default value is \"imcnp_user\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.IM_EXTERNAL_POSTGRES_DATABASE_USER=\"imcnp_user\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database. The default value is \"imcnpdb\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.IM_EXTERNAL_POSTGRES_DATABASE_NAME=\"imcnpdb\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Database port number. The default value is \"5432\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.IM_EXTERNAL_POSTGRES_DATABASE_PORT=\"5432\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the read database host cloud-native-postgresql on k8s provides this endpoint. If DB is not running on k8s then same hostname as DB host." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.IM_EXTERNAL_POSTGRES_DATABASE_R_ENDPOINT=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database host." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.IM_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    fi

    if [[ $EXTERNAL_POSTGRESDB_FOR_ZEN == "true" ]]; then
        rm -rf $ZEN_DB_SSL_CERT_FOLDER >/dev/null 2>&1
        mkdir -p $ZEN_DB_SSL_CERT_FOLDER >/dev/null 2>&1
        echo "## Configuration for external Postgres DB as Zen metastore DB." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "## YOU NEED TO CREATE THIS POSTGRES DB BY YOURSELF FISTLY BEFORE APPLY BAI CUSTOM RESOURCE." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "## NOTES: " >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   YOU NEED TO CREATE THIS POSTGRES DB BY YOURSELF FISTLY BEFORE APPLY BAI CUSTOM RESOURCE." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   1. Postgres version is 14.7 or higher and 16.x." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   2. Client certificate based authentication is configured on the DB server." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   3. Client certificate rotation is managed by the customer." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        # Name of the key in k8s secret ibm-zen-metastore-edb-secret do not need customized
        # echo "## Name of the key in k8s secret ibm-zen-metastore-edb-secret for CA certificate. The default value is \"ca.crt\"." >> ${USER_PROFILE_PROPERTY_FILE}
        # echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_CA_CERT=\"ca.crt\"" >> ${USER_PROFILE_PROPERTY_FILE}
        # echo "" >> ${USER_PROFILE_PROPERTY_FILE}
        
        # echo "## Name of the key in k8s secret ibm-zen-metastore-edb-secret for client certificate. The default value is \"tls.crt\"." >> ${USER_PROFILE_PROPERTY_FILE}
        # echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_CLIENT_CERT=\"tls.crt\"" >> ${USER_PROFILE_PROPERTY_FILE}
        # echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        # echo "## Name of the key in k8s secret ibm-zen-metastore-edb-secret for client key. The default value is \"tls.key\"." >> ${USER_PROFILE_PROPERTY_FILE}
        # echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_CLIENT_KEY=\"tls.key\"" >> ${USER_PROFILE_PROPERTY_FILE}
        # echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from server and client, and copy into this directory.Default value is \"$ZEN_DB_SSL_CERT_FOLDER\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER=\"$ZEN_DB_SSL_CERT_FOLDER\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the schema to store monitoring data. The default value is \"watchdog\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_MONITORING_SCHEMA=\"watchdog\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database. The default value is \"zencnpdb\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_NAME=\"zencnpdb\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Database port number. The default value is \"5432\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_PORT=\"5432\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the read database host cloud-native-postgresql on k8s provides this endpoint. If DB is not running on k8s then same hostname as DB host." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_R_ENDPOINT=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database host." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the schema to store zen metadata. The default value is \"public\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SCHEMA=\"public\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database user. The default value is \"zencnp_user\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_USER=\"zencnp_user\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    fi

    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS == "true" ]]; then
        rm -rf $BTS_DB_SSL_CERT_FOLDER >/dev/null 2>&1
        mkdir -p $BTS_DB_SSL_CERT_FOLDER >/dev/null 2>&1
        echo "## Configuration for external Postgres DB as BTS metastore DB." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "## YOU NEED TO CREATE THIS POSTGRES DB BY YOURSELF FISTLY BEFORE APPLY BAI CUSTOM RESOURCE." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "## NOTES: " >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   YOU NEED TO CREATE THIS POSTGRES DB BY YOURSELF FISTLY BEFORE APPLY BAI CUSTOM RESOURCE." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   1. Postgres version is 14.7 or higher and 16.x." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   2. Client certificate based authentication is configured on the DB server." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "##   3. Client certificate rotation is managed by the customer." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from server and client, and copy into this directory.Default value is \"$BTS_DB_SSL_CERT_FOLDER\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.BTS_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER=\"$BTS_DB_SSL_CERT_FOLDER\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database host." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.BTS_EXTERNAL_POSTGRES_DATABASE_HOSTNAME=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database user. The default value is \"btscnp_user\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.BTS_EXTERNAL_POSTGRES_DATABASE_USER_NAME=\"btscnp_user\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Name of the database. The default value is \"btscnpdb\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.BTS_EXTERNAL_POSTGRES_DATABASE_NAME=\"btscnpdb\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}

        echo "## Database port number. The default value is \"5432\"." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.BTS_EXTERNAL_POSTGRES_DATABASE_PORT=\"5432\"" >> ${USER_PROFILE_PROPERTY_FILE}
        echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    fi

    # generate property of flink job for BAW BAW Advanced events ICM ODM Content components
    
    echo "## The Flink job for processing BPMN events." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## Set to true to enable the Flink job for BAW." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ "${FLINK_JOB_CR_SELECTED[@]}" =~ "flink_job_bpmn" ]]; then
        echo "BAI_STANDALONE.FLINK_JOB_BPMN=\"True\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.FLINK_JOB_BPMN=\"False\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    
    # generate property of flink job for  BAW Advanced events
    echo "## The Flink job for processing BAW Advanced events.." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## Set to true to enable the Flink job for BAWAdv." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ "${FLINK_JOB_CR_SELECTED[@]}" =~ "flink_job_bawadv" ]]; then
        echo "BAI_STANDALONE.FLINK_JOB_BAWADV=\"True\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.FLINK_JOB_BAWADV=\"False\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    # generate property of flink job for ICM 
    echo "## The Flink job for processing ICM events." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## Set to true to enable the Flink job for ICM." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ "${FLINK_JOB_CR_SELECTED[@]}" =~ "flink_job_icm" ]]; then
        echo "BAI_STANDALONE.FLINK_JOB_ICM=\"True\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.FLINK_JOB_ICM=\"False\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    # generate property of flink job for  ODM 
    echo "## The Flink job for processing ODM events.." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## Set to true to enable the Flink job for ODM." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ "${FLINK_JOB_CR_SELECTED[@]}" =~ "flink_job_odm" ]]; then
        echo "BAI_STANDALONE.FLINK_JOB_ODM=\"True\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.FLINK_JOB_ODM=\"False\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}
    # generate property of flink job for Content
    echo "## The Flink job for processing Content events." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## Set to true to enable the Flink job for Content." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ "${FLINK_JOB_CR_SELECTED[@]}" =~ "flink_job_content" ]]; then
        echo "BAI_STANDALONE.FLINK_JOB_CONTENT=\"True\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.FLINK_JOB_CONTENT=\"False\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    # generate property of flink job for ADS
    echo "## The Flink job for processing ADS events." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## Set to true to enable the Flink job for ADS." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ "${FLINK_JOB_CR_SELECTED[@]}" =~ "flink_job_ads" ]]; then
        echo "BAI_STANDALONE.FLINK_JOB_ADS=\"True\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.FLINK_JOB_ADS=\"False\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    # generate property of flink job for Navigator
    echo "## The Flink job for processing Navigator events." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## Set to true to enable the Flink job for Navigator." >> ${USER_PROFILE_PROPERTY_FILE}
    if [[ "${FLINK_JOB_CR_SELECTED[@]}" =~ "flink_job_navigator" ]]; then
        echo "BAI_STANDALONE.FLINK_JOB_NAVIGATOR=\"True\"" >> ${USER_PROFILE_PROPERTY_FILE}
    else
        echo "BAI_STANDALONE.FLINK_JOB_NAVIGATOR=\"False\"" >> ${USER_PROFILE_PROPERTY_FILE}
    fi
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}
}

#### End - Functions being called by the create_property_file function ####

# Handler Function that creates the property files
function create_property_file(){
    printf "\n"
    # mkdir -p $PREREQUISITES_FOLDER_BAK >/dev/null 2>&1

    if [[ -d "$PROPERTY_FILE_FOLDER" ]]; then
        tmp_property_file_dir="${PROPERTY_FILE_FOLDER_BAK}_$(date +%Y-%m-%d-%H:%M:%S)"
        mkdir -p "$tmp_property_file_dir" >/dev/null 2>&1
        ${COPY_CMD} -rf "${PROPERTY_FILE_FOLDER}" "${tmp_property_file_dir}"
    fi
    rm -rf $PROPERTY_FILE_FOLDER >/dev/null 2>&1
    mkdir -p $PROPERTY_FILE_FOLDER >/dev/null 2>&1
    
    # If LDAP option was selected we will create the LDAP property file
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        create_ldap_property_file
    fi
    create_user_property_file
    

    INFO "Created all property files for BAI stand-alone"
    
    # Show some tips for property file
    tips
    printf '%b\n'  "Enter the <Required> values in the property files under $PROPERTY_FILE_FOLDER"
    msgRed   "The key name in the property file is created by the bai-prerequisites.sh and is NOT EDITABLE."
    msgRed   "The value in the property file must be within double quotes."
    msgRed   "The value for User/Password in [bai_user_profile.property] file should NOT include special characters: single quotation \"'\""
    echo

    if [[ $SELECTED_LDAP == "Yes" ]]; then
        msgRed   "The value in [bai_LDAP.property] [bai_user_profile.property] file should NOT include special character '\"'"
        printf '%b\n'  "\x1b[32m* [bai_LDAP.property]:\x1B[0m"
        printf '%b\n'  "  - Contains Properties for the LDAP server that is used by the BAI stand-alone deployment, such as LDAP_SERVER/LDAP_PORT/LDAP_BASE_DN/LDAP_BIND_DN/LDAP_BIND_DN_PASSWORD.\n"
        printf '%b\n' " - $RED_TEXT[REQUIRED]$RESET_TEXT If you plan to enable SSL-based connections for your LDAP server, retrieve the server certificate file from your remote LDAP server and copy it into the folder \"$LDAP_SSL_CERT_FOLDER\" before running bai-prerequisites.sh script in \"generate\" mode.$RED_TEXT The certificate must be named ldap-cert.crt. $RESET_TEXT"
    fi
    echo
    printf '%b\n'  "\x1b[32m* [bai_user_profile.property]:\x1B[0m"
    printf '%b\n'  "  - Contains Properties for the global value used by the BAI stand-alone deployment, such as \"sc_deployment_license\".\n"
    printf '%b\n'  "  - Contains Properties for the value used by each component of BAI stand-alone, such as \"sc_deployment_profile_size\"\n"

    # show tips for IM metastore external Postgres DB
    if [[ $EXTERNAL_POSTGRESDB_FOR_IM == "true" ]]; then
        msgB "* You have enabled IM metastore external Postgres DB, please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from your local or remote database server, and copy them into folder \"$IM_DB_SSL_CERT_FOLDER\" before you execute the generate mode of bai-prerequisites.sh script."
    fi

    # show tips for Zen metastore external Postgres DB
    if [[ $EXTERNAL_POSTGRESDB_FOR_ZEN == "true"  ]]; then
        msgB "* You have enabled Zen metastore external Postgres DB, please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from your local or remote database server, and copy them into folder \"$ZEN_DB_SSL_CERT_FOLDER\" before you execute the generate mode of bai-prerequisites.sh script."
    fi

    # show tips for BTS metastore external Postgres DB
    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS == "true" ]]; then
        msgB "* You have enabled BTS metastore external Postgres DB, please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from your local or remote database server, and copy them into folder \"$BTS_DB_SSL_CERT_FOLDER\" before you execute the generate mode of bai-prerequisites.sh script."
    fi
}
