#!/bin/bash
#set -x
###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2022. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Import common utilities and environment variables
source ${CUR_DIR}/helper/common.sh

# Import verification func
source ${CUR_DIR}/helper/bai-verification.sh

# Import variables for property file
source ${CUR_DIR}/helper/bai-property.sh

# Import function for secret
source ${CUR_DIR}/helper/bai-secret.sh

JDBC_DRIVER_DIR=${CUR_DIR}/jdbc
PLATFORM_SELECTED=""
PATTERN_SELECTED=""
COMPONENTS_SELECTED=""
OPT_COMPONENTS_CR_SELECTED=""
OPT_COMPONENTS_SELECTED=()
LDAP_TYPE=""
TARGET_PROJECT_NAME=""

optional_component_arr=()
optional_component_cr_arr=()

function show_help() {
    echo -e "\nUsage: bai-prerequisites.sh -m [modetype] -n [BAI-NAMESPACE] [options]\n"
    echo "Options:"
    echo "  -h  Display help"
    echo "  -m  The valid mode types are: [property], [generate], or [validate]"
    echo "  -n  The target namespace of the BAI deployment."
    echo " --java-path Optional path to Java (JRE) installation directory"
    echo ""
    echo "  STEP1: Run the script in [property] mode. It creates property files (LDAP property file) with default values (BASE DN/BIND DN ...)."
    echo "  STEP2: Modify the LDAP/user property files with your values."
    echo "  STEP3: Run the script in [generate] mode. Generates the YAML templates for the secrets based on the values in the property files."
    echo "  STEP4: Create the secrets by using the modified YAML templates for the secrets."
    echo "  STEP5: Run the script in [validate] mode. Checks the secrets are created before you install IBM Business Automation Insights."
}

function prompt_license(){
    # clear

    echo -e "\x1B[1;31mIMPORTANT: Review the IBM Business Automation Insights stand-alone license information here: \n\x1B[0m"
    echo -e "\x1B[1;31mhttps://www14.software.ibm.com/cgi-bin/weblap/lap.pl?li_formnum=L-PSZC-SHQFWS\n\x1B[0m"

    prompt_press_any_key_to_continue

    printf "\n"
    while true; do
        printf "\x1B[1mDo you accept the IBM Business Automation Insights stand-alone license (Yes/No, default: No): \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            printf "\n"
            IBM_LICENS="Accept"
            validate_cli
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            echo -e "The license agreement was not accepted. The license agreement must be accepted to continue. The script is exiting...\n"
            exit 0
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

function validate_utility_tool_for_validation(){
    which kubectl &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e  "\x1B[1;31mUnable to locate Kubernetes CLI. You must install it to run this script.\x1B[0m" && \
        while true; do
            printf "\x1B[1mDo you want install the Kubernetes CLI by the bai-prerequisites.sh script? (Yes/No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                install_kubectl_cli
                break
                ;;
            "n"|"N"|"no"|"No"|"NO")
                info "Kubernetes CLI must be installed to continue the next validation"
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    fi
    # DBACLD-198782: Check if Java is installed and meets the minimum version requirement
    # Priority: --java-path > JAVA_HOME > system PATH
    JAVA_PATH="${CUSTOM_JAVA_PATH:-$JAVA_HOME}"
    validate_java_runtime "$JAVA_PATH"

    which openssl &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e  "\x1B[1;31mUnable to locate openssl. You must install it to run this script.\x1B[0m" && \
        while true; do
            printf "\x1B[1mDo you want install the OpenSSL by the bai-prerequisites.sh script? (Yes/No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                install_openssl
                break
                ;;
            "n"|"N"|"no"|"No"|"NO")
                info "OpenSSL must be installed for the next validation"
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    fi
}

function containsElement(){
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}


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
        echo $i
    }
    menu() {
        clear
        echo -e "\x1B[1mWhich are the components you want to enable the Flink job for: \x1B[0m"
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
            echo -e "${tips1}"
        else
            echo -e "${tips2}"
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
    # echo -e "$msg"

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

# Function that checks if there are any missing quotes in any property files after the user updates the property files
# For https://jsw.ibm.com/browse/DBACLD-161426
function check_missing_quotes(){
    missing_quotes=0
    property_files=("${USER_PROFILE_PROPERTY_FILE}" "${LDAP_PROPERTY_FILE}" "${EXTERNAL_LDAP_PROPERTY_FILE}")
    for input_file in "${property_files[@]}"; do
        # Check if the property file exists
        if [ ! -f "$input_file" ]; then
            continue
        fi
        #<https://jsw.ibm.com/browse/DBACLD-170488> Remove the return character that sometimes gets added on a linux machine
        tmp_file=$(mktemp)
        sed $'s/\r//g' "$input_file" > "$tmp_file" && mv "$tmp_file" "$input_file"
        # Array to store incorrect entries
        incorrect_values=()

        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comment lines or empty lines
            if [[ $line =~ ^[[:space:]]*# ]] || [[ -z $line ]]; then
                continue
            fi

            # Skip lines that are completely empty or contain only whitespace
            if [[ "$line" =~ ^[[:space:]]*$ ]]; then
                continue
            fi

            # Ensure the line contains '=' before processing
            if [[ $line != *"="* ]]; then
                continue
            fi

            # Extract the key and value
            key=$(echo "$line" | cut -d'=' -f1)
            value=$(echo "$line" | cut -d'=' -f2-)

            # Check if the value is enclosed in quotes
            if [[ ! $value =~ ^\".*\"$ ]]; then
                # Add to the list of incorrect values
                incorrect_values+=("$key")
            fi
        done < "$input_file"

        # Output results
        if [ ! ${#incorrect_values[@]} -eq 0 ]; then
            missing_quotes=1
            error "Validation failed: The following values in the property file located at \"${input_file}\" are not enclosed in quotes:"
            printf "\n"
            echo "---------------------------------------------------------------"
            for entry in "${incorrect_values[@]}"; do
                echo "  - $entry"
            done
            echo "---------------------------------------------------------------"

        fi
    done
    if [[ "$missing_quotes" == 1 ]] ; then
        info "[NEXT_STEPS]: Reference the table above and ensure all values in all property files are enclosed in quotes and re-run bai-prerequisites.sh script in generate mode."
        exit 1
    fi
}

## -- https://jsw.ibm.com/browse/DBACLD-172803 - Function created to improve code
# Function to check for unfilled <Required> parameters, takes two arguments:
# 1) The style of <Required> filed, e.g. {Base}<Required>, {xor}<Required>
# 2) The property file name to check.
function check_required_values(){
    required_field=$1
    property_file=$2
    search_text="=\"${required_field}\""
    value_empty=$(grep "${search_text}" "${property_file}" | wc -l)
    if [ $value_empty -ne 0 ] ; then
        #Extract ALL the parameter names and include them in a comma separated list to the error message when the parameters are not properly filled out.
        parameter_name=$(grep "${search_text}" "${property_file}" | awk -F'=' '{print $1}'  | tr -d ' ' | paste -sd ',' -)
        error "Found invalid value(s) \"$required_field\" for parameter \"$parameter_name\" in property file \"${property_file}\", please input the correct value."
        empty_value_tag=1
    fi
}

function check_property_file(){

    # Function to check for valid certificates (LDAP, IM, ZEN, BTS)
    # For https://jsw.ibm.com/browse/DBACLD-180201
    validate_ssl_certificates

    # Validate required properties in configuration files
    INFO "Validating required properties in configuration files"

    # Function to check for missing quotes in any of the property files
    # For https://jsw.ibm.com/browse/DBACLD-161426
    check_missing_quotes
    local empty_value_tag=0

    # Check <Required> values for cp4ba_user_profile.property
    check_required_values "<Required>" "${USER_PROFILE_PROPERTY_FILE}"
    check_required_values "{Base64}<Required>" "${USER_PROFILE_PROPERTY_FILE}"
    ## -- https://jsw.ibm.com/browse/DBACLD-172803 - We are now asking user to use {xor} for special characters in password for some parameters, so we need to check if the "{xor}<Required>" is not filled out.
    check_required_values "{xor}<Required>" "${USER_PROFILE_PROPERTY_FILE}"

    # Check for empty values in the user profile property file
    validate_property_file_required_fields "${USER_PROFILE_PROPERTY_FILE}"

    # Conditionally mark LDAP SSL params optional BEFORE validating LDAP files
    # so the validator will skip them when SSL is disabled
    
    # First, remove any existing SSL parameters from the optional list to handle toggling
    OPTIONAL_PARAMETERS_LIST=($(printf '%s\n' "${OPTIONAL_PARAMETERS_LIST[@]}" | grep -v "^LDAP_SSL_SECRET_NAME$" | grep -v "^LDAP_SSL_CERT_FILE_FOLDER$" | grep -v "^EXT_LDAP_SSL_SECRET_NAME$" | grep -v "^EXT_LDAP_SSL_CERT_FILE_FOLDER$"))
    
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_ldap_property_file LDAP_SSL_ENABLED)")
        tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
        if [[ ${tmp_flag} =~ ^(no|n|false)$ ]]; then
            OPTIONAL_PARAMETERS_LIST+=("LDAP_SSL_SECRET_NAME")
            OPTIONAL_PARAMETERS_LIST+=("LDAP_SSL_CERT_FILE_FOLDER")
        fi
    fi

    if [[ $SET_EXT_LDAP == "Yes" ]]; then
        tmp_ext_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_ext_ldap_property_file LDAP_SSL_ENABLED)")
        tmp_ext_flag=$(echo $tmp_ext_flag | tr '[:upper:]' '[:lower:]')
        if [[ ${tmp_ext_flag} =~ ^(no|n|false)$ ]]; then
            OPTIONAL_PARAMETERS_LIST+=("EXT_LDAP_SSL_SECRET_NAME")
            OPTIONAL_PARAMETERS_LIST+=("EXT_LDAP_SSL_CERT_FILE_FOLDER")
        fi
    fi

    # Persist optional list before any LDAP validations
    mark_optional

     # Check <Required> values for cp4ba_LDAP.property
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        check_required_values "<Required>" "${LDAP_PROPERTY_FILE}"
        check_required_values "{Base64}<Required>" "${LDAP_PROPERTY_FILE}"
        ## -- https://jsw.ibm.com/browse/DBACLD-172803 - We are now asking user to use {xor} for special characters in password for some parameters, so we need to check if the "{xor}<Required>" is not filled out.
        check_required_values "{xor}<Required>" "${LDAP_PROPERTY_FILE}"
        
        # Check for empty values in the ldap property file
        validate_property_file_required_fields "${LDAP_PROPERTY_FILE}"
    fi


    if [[ $SET_EXT_LDAP == "Yes" ]]; then
        check_required_values "<Required>" "${EXTERNAL_LDAP_PROPERTY_FILE}"

        # Check for empty values in the external ldap property file
        validate_property_file_required_fields "${EXTERNAL_LDAP_PROPERTY_FILE}"
    fi


    if [[ "$empty_value_tag" == "1" ]]; then
        exit 1
    fi
    
    # Check keystorePassword in ibm-fncm-secret and ibm-ban-secret must exceed 16 characters when fips enabled.
    # FIPS is always false (not supported)
    fips_flag="false"
    
    # Check the directory for certificate should be different for IM/Zen/BTS/cp4ba_tls_issuer
    # IM metastore external Postgres DB
    cert_dir_array=()
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        im_external_db_cert_folder="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        im_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$im_external_db_cert_folder")
        cert_dir_array=( "${cert_dir_array[@]}" "${im_external_db_cert_folder}" )
    fi

    # Zen metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        zen_external_db_cert_folder="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        zen_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$zen_external_db_cert_folder")
        cert_dir_array=( "${cert_dir_array[@]}" "${zen_external_db_cert_folder}" )
    fi

    # BTS metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        bts_external_db_cert_folder="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        bts_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$bts_external_db_cert_folder")
        cert_dir_array=( "${cert_dir_array[@]}" "${bts_external_db_cert_folder}" )
    fi

    declare -A dir_count
    for element in "${cert_dir_array[@]}"; do
        if [[ -n "${dir_count[$element]}" ]]; then
            dir_count[$element]=$((dir_count[$element] + 1))
        else
            dir_count[$element]=1
        fi
    done

    duplicates_dir_found="No"
    for element in "${!dir_count[@]}"; do
        if [[ ${dir_count[$element]} -gt 1 ]]; then
            duplicates_dir_found="Yes"
        fi
    done

    if [[ $duplicates_dir_found == "Yes" ]]; then
        error_value_tag=1
        error "Found the same directory is used for below certificate folder's property."
        if [[ ! -z $im_external_db_cert_folder ]]; then
            msg "BAI.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER: \"$im_external_db_cert_folder\""
        fi
        if [[ ! -z $im_external_db_cert_folder ]]; then
            msg "BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER: \"$zen_external_db_cert_folder\""
        fi
        if [[ ! -z $im_external_db_cert_folder ]]; then
            msg "BAI.BTS_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER: \"$bts_external_db_cert_folder\""
        fi
        warning "You need to use different directory for above certificate folder's property."

    fi

    if [[ "$error_value_tag" == "1" || "$SSL_CERT_ERROR_TAG" == "true" || "$MISSING_REQUIRED_PARAMETERS" == "true" ]]; then
        exit 1
    fi
}

function create_prerequisites() {
    rm -rf $SECRET_FILE_FOLDER
    INFO "Generating YAML templates for secrets required by BAI stand-alone deployment based on property file"
    printf "\n"
    wait_msg "Creating YAML templates for secrets"

    if [[ $SELECTED_LDAP == "Yes" ]]; then
        # Create LDAP bind secret
        create_ldap_secret_template
        #  replace ldap user
        tmp_dbuser="$(prop_ldap_property_file LDAP_BIND_DN)"
        ${SED_COMMAND} "s|\"<LDAP_BIND_DN>\"|\"$tmp_dbuser\"|g" ${LDAP_SECRET_FILE}

        # For https://jsw.ibm.com/browse/DBACLD-157020
        # Function that updates the secret template with the base64 password
        tmp_ldapuserpwd="$(prop_ldap_property_file LDAP_BIND_DN_PASSWORD)"
        update_secret_template_passwords $tmp_ldapuserpwd "ldapPassword" "$LDAP_SECRET_FILE"

        if [[ "${tmp_ldapuserpwd:0:8}" == "{Base64}"  ]]; then
            temp_val=$(echo "$tmp_ldapuserpwd" | sed -e "s/^{Base64}//" | base64 --decode) 
            ${SED_COMMAND} "s|\"<LDAP_PASSWORD>\"|'$(printf '%q' $temp_val)'|g" ${LDAP_SECRET_FILE}
        else
            ${SED_COMMAND} "s|\"<LDAP_PASSWORD>\"|\"$tmp_ldapuserpwd\"|g" ${LDAP_SECRET_FILE}
        fi
        # ${SED_COMMAND} "s|\"<LDAP_PASSWORD>\"|\"$tmp_dbuserpwd\"|g" ${LDAP_SECRET_FILE}

        # Create LDAP bind secret for external share
        if [[ $SET_EXT_LDAP == "Yes" ]]; then
            create_ext_ldap_secret_template
            #  replace ldap user
            tmp_dbuser="$(prop_ext_ldap_property_file LDAP_BIND_DN)"
            ${SED_COMMAND} "s|\"<LDAP_BIND_DN>\"|\"$tmp_dbuser\"|g" ${EXT_LDAP_SECRET_FILE}

            # For https://jsw.ibm.com/browse/DBACLD-157020
            # Function that updates the secret template with the base64 password
            tmp_ldapuserpwd="$(prop_ext_ldap_property_file LDAP_BIND_DN_PASSWORD)"
            update_secret_template_passwords $tmp_ldapuserpwd "ldapPassword" "$EXT_LDAP_SECRET_FILE"
        fi
    fi

    if [[ $SELECTED_LDAP == "Yes" ]]; then
        # LDAP SSL Enabled
        tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_ldap_property_file LDAP_SSL_ENABLED)")
        tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
        while true; do
            case "$tmp_flag" in
            "true"|"yes"|"y")
                create_cp4a_ldap_ssl_secret_template
                #  replace ldap secret name
                tmp_ldap_secret_name="$(prop_ldap_property_file LDAP_SSL_SECRET_NAME)"
                tmp_ldap_secret_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_ldap_secret_name")
                if [[ -z $tmp_ldap_secret_name || -n $tmp_ldap_secret_name || $tmp_ldap_secret_name != "" ]]; then
                    ${SED_COMMAND} "s|<cp4a-ldap_ssl_secret_name>|$tmp_ldap_secret_name|g" ${CP4A_LDAP_SSL_SECRET_FILE}
                fi

                #  replace secret file folder
                tmp_name="$(prop_ldap_property_file LDAP_SSL_CERT_FILE_FOLDER)"
                if [[ -z $tmp_name || $tmp_name == "" ]]; then
                    tmp_name=$LDAP_SSL_CERT_FOLDER
                fi
                ${SED_COMMAND} "s|<cp4a-ldap-crt-file-in-local>|$tmp_name|g" ${CP4A_LDAP_SSL_SECRET_FILE}
                break
                ;;
            "false"|"no"|"n"|"")
                break
                ;;
            *)
                fail "LDAP_SSL_ENABLED is not valid value in the \"BAI_LDAP.property\"! Exiting ..."
                exit 1
                ;;
            esac
        done
        
        # External LDAP SSL Enabled
        if [[ $SET_EXT_LDAP == "Yes" ]]; then
            tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_ext_ldap_property_file LDAP_SSL_ENABLED)")
            tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
            while true; do
                case "$tmp_flag" in
                "true"|"yes"|"y")
                    create_cp4a_ext_ldap_ssl_secret_template
                    #  replace ldap secret name
                    tmp_ldap_secret_name="$(prop_ext_ldap_property_file LDAP_SSL_SECRET_NAME)"
                    tmp_ldap_secret_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_ldap_secret_name")
                    if [[ -z $tmp_ldap_secret_name || -n $tmp_ldap_secret_name || $tmp_ldap_secret_name != "" ]]; then
                        ${SED_COMMAND} "s|<cp4a-ldap_ssl_secret_name>|$tmp_ldap_secret_name|g" ${CP4A_EXT_LDAP_SSL_SECRET_FILE}
                    fi

                    #  replace secret file folder
                    tmp_name="$(prop_ext_ldap_property_file LDAP_SSL_CERT_FILE_FOLDER)"
                    if [[ -z $tmp_name || $tmp_name == "" ]]; then
                        tmp_name=$EXT_LDAP_SSL_CERT_FOLDER
                    fi
                    ${SED_COMMAND} "s|<cp4a-ldap-crt-file-in-local>|$tmp_name|g" ${CP4A_EXT_LDAP_SSL_SECRET_FILE}
                    break
                    ;;
                "false"|"no"|"n"|"")
                    break
                    ;;
                *)
                    fail "LDAP_SSL_ENABLED is not valid value in the \"BAI_External_LDAP.property\"! Exiting ..."
                    exit 1
                    ;;
                esac
            done
        fi
    fi

    # Create Secret/configMap for IM metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        create_im_external_db_secret_template
        #  replace secret file folder
        im_external_db_cert_folder="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        im_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$im_external_db_cert_folder")
        if [[ -z $im_external_db_cert_folder || $im_external_db_cert_folder == "" ]]; then
            im_external_db_cert_folder=$IM_DB_SSL_CERT_FOLDER
        fi
        ${SED_COMMAND} "s|<cp4a-db-crt-file-in-local>|$im_external_db_cert_folder|g" ${IM_SECRET_FILE}

        create_im_external_db_configmap_template
        #  replace <DatabasePort>
        tmp_name="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_PORT)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabasePort>|$tmp_name|g" ${IM_CONFIGMAP_FILE}

        #  replace <DatabaseReadHostName>
        tmp_name="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_R_ENDPOINT)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseReadHostName>|$tmp_name|g" ${IM_CONFIGMAP_FILE}

        #  replace <DatabaseHostName>
        im_external_db_host_name="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
        im_external_db_host_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$im_external_db_host_name")
        ${SED_COMMAND} "s|<DatabaseHostName>|$im_external_db_host_name|g" ${IM_CONFIGMAP_FILE}

        #  replace <DatabaseUser>
        tmp_name="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_USER)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseUser>|$tmp_name|g" ${IM_CONFIGMAP_FILE}

        #  replace <DatabaseName>
        tmp_name="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_NAME)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseName>|$tmp_name|g" ${IM_CONFIGMAP_FILE}
    fi

    # Create Secret/configMap for Zen metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        create_zen_external_db_secret_template
        #  replace secret file folder
        zen_external_db_cert_folder="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        zen_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$zen_external_db_cert_folder")
        if [[ -z $zen_external_db_cert_folder || $zen_external_db_cert_folder == "" ]]; then
            zen_external_db_cert_folder=$ZEN_DB_SSL_CERT_FOLDER
        fi
        ${SED_COMMAND} "s|<cp4a-db-crt-file-in-local>|$zen_external_db_cert_folder|g" ${ZEN_SECRET_FILE}

        create_zen_external_db_configmap_template
        #  replace MonitoringSchema
        tmp_name="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_MONITORING_SCHEMA)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<MonitoringSchema>|$tmp_name|g" ${ZEN_CONFIGMAP_FILE}

        #  replace <DatabaseName>
        tmp_name="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_NAME)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseName>|$tmp_name|g" ${ZEN_CONFIGMAP_FILE}

        #  replace <DatabasePort>
        tmp_name="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_PORT)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabasePort>|$tmp_name|g" ${ZEN_CONFIGMAP_FILE}

        #  replace <DatabaseReadHostName>
        tmp_name="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_R_ENDPOINT)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseReadHostName>|$tmp_name|g" ${ZEN_CONFIGMAP_FILE}

        #  replace <DatabaseHostName>
        zen_external_db_host_name="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
        zen_external_db_host_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$zen_external_db_host_name")
        ${SED_COMMAND} "s|<DatabaseHostName>|$zen_external_db_host_name|g" ${ZEN_CONFIGMAP_FILE}

        #  replace <DatabaseSchema>
        tmp_name="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SCHEMA)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseSchema>|$tmp_name|g" ${ZEN_CONFIGMAP_FILE}

        #  replace <DatabaseUser>
        tmp_name="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_USER)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseUser>|$tmp_name|g" ${ZEN_CONFIGMAP_FILE}

    fi

    # Create Secret/configMap for BTS metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        create_bts_external_db_secret_template
        #  replace secret file folder
        bts_external_db_cert_folder="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        bts_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$bts_external_db_cert_folder")
        if [[ -z $bts_external_db_cert_folder || $bts_external_db_cert_folder == "" ]]; then
            bts_external_db_cert_folder=$BTS_DB_SSL_CERT_FOLDER
        fi
        ${SED_COMMAND} "s|<cp4a-db-crt-file-in-local>|$bts_external_db_cert_folder|g" ${BTS_SSL_SECRET_FILE}


        create_bts_external_db_configmap_template
        #  replace <DatabaseHostName>
        tmp_name="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_HOSTNAME)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseHostName>|$tmp_name|g" ${BTS_CONFIGMAP_FILE}

        #  replace <DatabasePort>
        tmp_name="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_PORT)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabasePort>|$tmp_name|g" ${BTS_CONFIGMAP_FILE}

        #  replace <DatabaseName>
        tmp_name="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_NAME)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseName>|$tmp_name|g" ${BTS_CONFIGMAP_FILE}

        #  replace <DatabaseUserName>
        tmp_name="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_USER_NAME)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<DatabaseUserName>|$tmp_name|g" ${BTS_CONFIGMAP_FILE}

    fi


    tips
    msgB "* Enter the <Required> values in the YAML templates for the secrets under $SECRET_FILE_FOLDER"


    msgB "* You can use this shell script to create the secret automatically: $CREATE_SECRET_SCRIPT_FILE"
    msgB "* Create the Kubernetes secrets manually based on your modified \"YAML template for secret\".\n* And then run the  \"bai-prerequisites.sh -m validate\" command to verify that the secrets are created correctly."
}

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
    
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        mkdir -p $LDAP_SSL_CERT_FOLDER >/dev/null 2>&1
        > ${LDAP_PROPERTY_FILE}
        wait_msg "Creating LDAP Server property file for BAI stand-alone"
        
        tip="## Property file for ${LDAP_TYPE} ##"

        echo "###########################" >> ${LDAP_PROPERTY_FILE}
        echo $tip >> ${LDAP_PROPERTY_FILE}
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
        # Removed the else part here
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
            # For https://jsw.ibm.com/browse/DBACLD-155190 where the GC PORT and GC HOST should be optional parameters
            ${SED_COMMAND} "s|LC_AD_GC_HOST=\"\"|LC_AD_GC_HOST=\"<Optional>\"|g" ${LDAP_PROPERTY_FILE}
            OPTIONAL_PARAMETERS_LIST+=("LC_AD_GC_HOST")
            ${SED_COMMAND} "s|LC_AD_GC_PORT=\"\"|LC_AD_GC_PORT=\"<Optional>\"|g" ${LDAP_PROPERTY_FILE}
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
        #Removed the else part here
        fi

        # Marks all entries in "OPTIONAL_PARAMETERS_LIST" as optional by appending them to the TEMPORARY_PROPERTY_FILE under "OPTIONAL_PARAMETERS:"
        mark_optional

        success "Created the LDAP Server property file for BAI stand-alone\n"
    fi

    # Add global property into user_profile for BAI stand-alone
    tip="##           USER Property for BAI stand-alone               ##"
    echo "####################################################" >> ${USER_PROFILE_PROPERTY_FILE}
    echo $tip >> ${USER_PROFILE_PROPERTY_FILE}
    echo "####################################################" >> ${USER_PROFILE_PROPERTY_FILE}
    # license
    echo "## Use this parameter to specify the license for the BAI stand-alone deployment and" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "## the possible values are: non-production and production and if not set, the license will" >> ${USER_PROFILE_PROPERTY_FILE}        
    echo "## be defaulted to production.  This value could be different from the other licenses in the CR." >> ${USER_PROFILE_PROPERTY_FILE}
    echo "BAI_STANDALONE.BAI_LICENSE=\"<Required>\"" >> ${USER_PROFILE_PROPERTY_FILE}
    echo "" >> ${USER_PROFILE_PROPERTY_FILE}

    echo "## The platform to be deployed specified by the user. Possible values are: OCP and ROKS and other" >> ${USER_PROFILE_PROPERTY_FILE}
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

    # generate property of flink job for BAW BAW Advanced events ICM ODM Content
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

    # For https://jsw.ibm.com/browse/DBACLD-154784 The error should be thrown when we select 'yes' to configure one LDAP.
    # Convert SELECTED_LDAP to lowercase so that it will match any variation of "yes"
    if [[ "$(echo "${SELECTED_LDAP}" | tr '[:upper:]' '[:lower:]')" == "yes" ]]; then
        ${SED_COMMAND} "s|LDAP_BIND_DN_PASSWORD=\"\"|LDAP_BIND_DN_PASSWORD=\"{xor}<Required>\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|=\"\"|=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
    fi

    INFO "Created all property files for BAI stand-alone"
    
    # Show some tips for property file
    tips
    echo -e  "Enter the <Required> values in the property files under $PROPERTY_FILE_FOLDER"
    msgRed   "The key name in the property file is created by the bai-prerequisites.sh and is NOT EDITABLE."
    msgRed   "The value in the property file must be within double quotes."
    msgRed   "The value for User/Password in [bai_user_profile.property] file should NOT include special characters: single quotation \"'\""
    echo
    
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        msgRed   "The value in [bai_LDAP.property] [bai_user_profile.property] file should NOT include special character '\"'"
        echo -e  "\x1b[32m* [bai_LDAP.property]:\x1B[0m"
        echo -e  "  - Properties for the LDAP server that is used by the BAI stand-alone deployment, such as LDAP_SERVER/LDAP_PORT/LDAP_BASE_DN/LDAP_BIND_DN/LDAP_BIND_DN_PASSWORD.\n"
        echo -e "  - $RED_TEXT[REQUIRED]$RESET_TEXT If you plan to enable SSL-based connections for your LDAP server, retrieve the server certificate file from your remote LDAP server and copy it into the folder \"$LDAP_SSL_CERT_FOLDER\" before running the bai-prerequisites.sh script in \"generate\" mode.$RED_TEXT The certificate must be named ldap-cert.crt. $RESET_TEXT"  
    fi

    echo -e  "\x1b[32m* [bai_user_profile.property]:\x1B[0m"
    echo -e  "  - Properties for the global value used by the BAI stand-alone deployment, such as \"sc_deployment_license\".\n"
    echo -e  "  - Properties for the value used by each component of BAI stand-alone, such as \"sc_deployment_profile_size\"\n"

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
        echo -e "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done

    while [[ $sc_fast_file_storage_classname == "" ]] # While get fast storage clase name
    do
        printf "\x1B[1mPlease enter the file storage classname for fast storage(RWX): \x1B[0m"
        read -rp "" sc_fast_file_storage_classname
        if [ -z "$sc_fast_file_storage_classname" ]; then
        echo -e "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done

    while [[ $block_storage_class_name == "" ]] # While get block storage clase name
    do
        printf "\x1B[1mPlease enter the block storage classname for Zen(RWO): \x1B[0m"
        read -rp "" block_storage_class_name
        if [ -z "$block_storage_class_name" ]; then
        echo -e "\x1B[1;31mEnter a valid block storage classname(RWO)\x1B[0m"
        fi
    done

    STORAGE_CLASS_NAME=${storage_class_name}
    SLOW_STORAGE_CLASS_NAME=${sc_slow_file_storage_classname}
    MEDIUM_STORAGE_CLASS_NAME=${sc_medium_file_storage_classname}
    FAST_STORAGE_CLASS_NAME=${sc_fast_file_storage_classname}
    BLOCK_STORAGE_CLASS_NAME=${block_storage_class_name}
}

function load_property_before_generate(){
    if [[ ! -f $TEMPORARY_PROPERTY_FILE || ! -f $USER_PROFILE_PROPERTY_FILE ]]; then
        fail "Not Found existing property file under \"$PROPERTY_FILE_FOLDER\""
        exit 1
    fi

    # load db ldap type
    SELECTED_LDAP="$(prop_tmp_property_file SELECTED_LDAP_FLAG)"

    # load db ldap type
    LDAP_TYPE="$(prop_tmp_property_file LDAP_TYPE)"
}

function select_external_postgresdb_for_im(){
    printf "\n"
    echo ""
    while true; do
        printf "\x1B[1mDo you want to use an external Postgres DB \x1B[0m${RED_TEXT}[YOU NEED TO CREATE THIS POSTGRESQL DB BY YOURSELF FIRST BEFORE YOU APPLY THE BAI CUSTOM RESOURCE]${RESET_TEXT}${GREEN_TEXT}PLEASE REFER THE KNOWLEDGE CENTER: https://www.ibm.com/docs/en/cloud-paks/foundational-services/$CS_CHANNEL_KC?topic=im-setting-up-external-edb-postgresql-database-server#dbcreate ${RESET_TEXT}]\x1B[1mas IM metastore DB for this BAI deployment?\x1B[0m ${YELLOW_TEXT}(Notes: IM service can use an external Postgres DB to store IM data. If you select \"Yes\", IM service uses an external Postgres DB as IM metastore DB. If you select \"No\", IM service uses an embedded cloud native postgresql DB as IM metastore DB.)${RESET_TEXT} (Yes/No, default: No):  "
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            EXTERNAL_POSTGRESDB_FOR_IM="true"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            EXTERNAL_POSTGRESDB_FOR_IM="false"
            break
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

function select_external_postgresdb_for_zen(){
    printf "\n"
    echo ""
    while true; do
        # Updating this question to reflect zen instead of BTS
        # DBACLD-166156
        printf "\x1B[1mDo you want to use an external Postgres DB \x1B[0m${RED_TEXT}[YOU NEED TO CREATE THIS POSTGRESQL DB BY YOURSELF FIRST BEFORE YOU APPLY THE BAI CUSTOM RESOURCE]${RESET_TEXT}${GREEN_TEXT}PLEASE REFER THE KNOWLEDGE CENTER: https://www.ibm.com/docs/en/cloud-paks/foundational-services/$CS_CHANNEL_KC?topic=im-setting-up-external-edb-postgresql-database-server#dbcreate ${RESET_TEXT}]\x1B[1m as Zen metastore DB for this BAI deployment?\x1B[0m ${YELLOW_TEXT}(Notes: Zen stores all metadata such as users, groups, service instances, vault integration and secret references in metastore DB. If you select \"Yes\", Zen service uses an external Postgres DB as Zen metastore DB.. If you select \"No\", Zen service uses an embedded cloud native postgresql DB as Zen metastore DB )${RESET_TEXT} (Yes/No, default: No): "
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            EXTERNAL_POSTGRESDB_FOR_ZEN="true"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            EXTERNAL_POSTGRESDB_FOR_ZEN="false"
            break
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

function select_external_postgresdb_for_bts(){
    printf "\n"
    echo ""
    while true; do
        printf "\x1B[1mDo you want to use an external Postgres DB \x1B[0m${RED_TEXT}[YOU NEED TO CREATE THIS POSTGRESQL DB BY YOURSELF FIRST BEFORE APPLY BAI CUSTOM RESOURCE]${RESET_TEXT}${GREEN_TEXT}PLEASE REFER THE KNOWLEDGE CENTER: https://www.ibm.com/docs/en/cloud-paks/foundational-services/$CS_CHANNEL_KC?topic=im-setting-up-external-edb-postgresql-database-server#dbcreate ${RESET_TEXT}]\x1B[1m as BTS metastore DB for this BAI deployment?\x1B[0m ${YELLOW_TEXT}(Notes: BTS service can use an external Postgres DB to store meta data. If select \"Yes\", BTS service uses an external Postgres DB as BTS metastore DB. If select \"No\", BTS service uses an embedded cloud native postgresql DB as BTS metastore DB )${RESET_TEXT} (Yes/No, default: No): "
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            EXTERNAL_POSTGRESDB_FOR_BTS="true"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            EXTERNAL_POSTGRESDB_FOR_BTS="false"
            break
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}


function select_restricted_internet_access(){
    printf "\n"
    echo ""
    while true; do
        printf "\x1B[1mDo you want to restrict network egress to unknown external destination for this BAI stand-alone deployment?\x1B[0m ${YELLOW_TEXT}(Notes: BAI stand-alone $BAI_RELEASE_BASE prevents all network egress to unknown destinations by default. You can either (1) enable all egress or (2) accept the new default and create network policies to allow your specific communication targets as documented in the knowledge center.)${RESET_TEXT} (Yes/No, default: Yes): "
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES"|"")
            RESTRICTED_INTERNET_ACCESS="true"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")
            RESTRICTED_INTERNET_ACCESS="false"
            break
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

function select_project() {
    while [[ $TARGET_PROJECT_NAME == "" ]]; 
    do
        printf "\n"
        echo -e "\x1B[1mWhere do you want to deploy IBM Business Automation Insights stand-alone?\x1B[0m"
        read -p "Enter the name for an existing project (namespace): " TARGET_PROJECT_NAME
        if [ -z "$TARGET_PROJECT_NAME" ]; then
            echo -e "\x1B[1;31mEnter a valid project name, project name can not be blank\x1B[0m"
        elif [[ "$TARGET_PROJECT_NAME" == openshift* ]]; then
            echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
            TARGET_PROJECT_NAME=""
        elif [[ "$TARGET_PROJECT_NAME" == kube* ]]; then
            echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
            TARGET_PROJECT_NAME=""
        else
            isProjExists=`${CLI_CMD} get project $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1

            if [ "$isProjExists" -ne 2 ] ; then
                echo -e "\x1B[1;31mInvalid project name, please enter a existing project name ...\x1B[0m"
                TARGET_PROJECT_NAME=""
            else
                echo -e "\x1B[1mUsing project ${TARGET_PROJECT_NAME}...\x1B[0m"
            fi
        fi
    done
}

function select_fips_enable(){
    select_project
    all_fips_enabled_flag=$(${CLI_CMD} get configmap bai-fips-status --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath={.data.all-fips-enabled})
    if [ -z $all_fips_enabled_flag ]; then
        warning "Not found configmap \"bai-fips-status\" in project \"$TARGET_PROJECT_NAME\". setting BAI_STANDALONE.ENABLE_FIPS as \"false\" by default in the \"BAI_user_profile.property\""
        FIPS_ENABLED="false"
    elif [[ "$all_fips_enabled_flag" == "Yes" ]]; then
        printf "\n"
        while true; do
            printf "\x1B[1mYour OCP cluster has FIPS enabled, do you want to enable FIPS with this BAI stand-alone deployment？\x1B[0m (Yes/No, default: No): "
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                if [[ (" ${optional_component_cr_arr[@]}" =~ "bai") && (! " ${optional_component_cr_arr[@]}" =~ "kafka") ]]; then
                    FIPS_ENABLED="false"
                    msg_tmp="BAI"
                elif [[ (! " ${optional_component_cr_arr[@]}" =~ "bai") && (" ${optional_component_cr_arr[@]}" =~ "kafka") ]]; then
                    FIPS_ENABLED="false"
                    msg_tmp="Exposed Kafka Services"
                elif [[  (" ${optional_component_cr_arr[@]}" =~ "bai") && (" ${optional_component_cr_arr[@]}" =~ "kafka") ]]; then
                    FIPS_ENABLED="false"
                    msg_tmp="BAI/Exposed Kafka Services"
                else
                    FIPS_ENABLED="true"
                fi
                if [[ $FIPS_ENABLED == "false" ]]; then
                    echo -e "${YELLOW_TEXT}[ATTENTION]: ${RESET_TEXT}\x1B[1;31mBecause \"$msg_tmp\" selected does not support FIPS enabled, the script will disable FIPS mode for this BAI stand-alone deployment (shared_configuration.enable_fips: false).\x1B[0m"
                    sleep 3
                fi
                break
                ;;
            "n"|"N"|"no"|"No"|"NO"|"")
                FIPS_ENABLED="false"
                break
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    elif [[ "$all_fips_enabled_flag" == "No" ]]; then
        FIPS_ENABLED="false"
    fi
}

function select_ldap_type(){
    printf "\n"
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
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done

    if [[ $SELECTED_LDAP == "Yes" ]]; then
        select_ldap_user_for_zen
        printf "\n"
        COLUMNS=12
        echo -e "\x1B[1mWhat is the LDAP type that will be used for this deployment? \x1B[0m"
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

function select_ldap_user_for_zen(){
    printf "\n"
    LDAP_USER_NAME=""

    echo -e  "${YELLOW_TEXT}For BAI stand-alone, if you select LDAP, then provide one ldap user here for onboarding ZEN.${RESET_TEXT}"    
    while [[ $LDAP_USER_NAME == "" ]] # While get medium storage clase name
    do
        printf "\x1B[1mPlease enter one LDAP user for BAI stand-alone: \x1B[0m"
        read -rp "" LDAP_USER_NAME
        if [ -z "$LDAP_USER_NAME" ]; then
        echo -e "\x1B[1;31mEnter a valid LDAP user\x1B[0m"
        fi
    done
}

function select_iam_default_admin(){
    printf "\n"
    while true; do
        echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1;31mIf you are unable to use [cpadmin] as the default IAM admin user due to it being already used in your LDAP Directory, you need to change the Cloud Pak administrator username. See: \" https://www.ibm.com/docs/en/cloud-paks/foundational-services/$CS_CHANNEL_KC?topic=configurations-changing-cluster-administrator-access-credentials#name\"\x1B[0m"
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
                echo -e "\x1B[1mWhat is the non default IAM admin user you renamed?\x1B[0m"
                read -p "Enter the admin user name: " NON_DEFAULT_IAM_ADMIN
            
                if [ -z "$NON_DEFAULT_IAM_ADMIN" ]; then
                    echo -e "\x1B[1;31mEnter a valid admin user name, user name can not be blank\x1B[0m"
                    NON_DEFAULT_IAM_ADMIN=""
                elif [[ "$NON_DEFAULT_IAM_ADMIN" == "cpadmin" ]]; then
                    echo -e "\x1B[1;31mEnter a valid admin user name, user name should not be 'cpadmin'\x1B[0m"
                    NON_DEFAULT_IAM_ADMIN=""
                fi
            done
            break
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

function select_platform(){
    printf "\n"
    echo -e "\x1B[1mSelect the cloud platform to deploy: \x1B[0m"
    COLUMNS=12
    # options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "Other ( Certified Kubernetes Cloud Platform / CNCF)")
    # PS3='Enter a valid option [1 to 3]: '
    options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
    PS3='Enter a valid option [1 to 2]: '
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
            "Other ( Certified Kubernetes Cloud Platform / CNCF)")
                PLATFORM_SELECTED="other"
                break
                ;;
            *) echo "invalid option $REPLY";;
        esac
    done
}

function select_profile_type(){
    printf "\n"
    COLUMNS=12
    echo -e "\x1B[1mPlease select the deployment profile (default: small).  Refer to the documentation in BAI stand-alone Knowledge Center for details on profile.\x1B[0m"
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
        echo -e "\x1B[1;31mExisting profile size type found in CR: \"$existing_profile_type\"\x1B[0m"
        # echo -e "\x1B[1;31mDo not need to select again.\n\x1B[0m"
        read -rsn1 -p"Press Enter/Return to continue ...";echo        
    fi
}

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

    if  [[ $PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "ROKS" ]]; then
        select_restricted_internet_access
        select_external_postgresdb_for_im
        select_external_postgresdb_for_zen
        select_external_postgresdb_for_bts
    fi
    select_flink_job
    create_temp_property_file
}

function clean_up_temp_file(){
    local files=()
    files=($(find $PREREQUISITES_FOLDER -name '*.*""'))
    for item in ${files[*]}
    do
        rm -rf $item >/dev/null 2>&1
    done
    
    files=($(find $TEMP_FOLDER -name '*.*""'))
    for item in ${files[*]}
    do
        rm -rf $item >/dev/null 2>&1
    done
}

function generate_create_secret_script(){
    local files=()
    local CREATE_SECRET_SCRIPT_FILE_TMP=$TEMP_FOLDER/create_secret.sh
    > ${CREATE_SECRET_SCRIPT_FILE_TMP}
    > ${CREATE_SECRET_SCRIPT_FILE}
    files=($(find $SECRET_FILE_FOLDER -name '*.yaml'))
    for item in ${files[*]}
    do
        echo "echo \"****************************************************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"******************************* START **************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"[INFO] Applying YAML template file:$item\"">> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "${CLI_CMD} apply -f \"$item\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"******************************** END ***************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"****************************************************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "printf \"\\n\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
    done
    
    files=($(find $SECRET_FILE_FOLDER -name '*.sh'))
    for item in ${files[*]}
    do
        echo "echo \"****************************************************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"******************************* START **************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"[INFO] Executing shell script:$item\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "$item" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"******************************** END ***************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "echo \"****************************************************************************\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "printf \"\\n\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
        echo "" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
    done
    ${COPY_CMD} -rf ${CREATE_SECRET_SCRIPT_FILE_TMP} ${CREATE_SECRET_SCRIPT_FILE}
    chmod 755 $CREATE_SECRET_SCRIPT_FILE
}


function validate_secret_in_cluster(){
    INFO "Checking if the secrets required by BAI stand-alone are found in the cluster" 
    local files=()
    SECRET_CREATE_PASSED="true"
    files=($(find $SECRET_FILE_FOLDER -name '*.yaml'))
    for item in ${files[*]}
    do
        secret_name_tmp=`cat $item | ${YQ_CMD} r - metadata.name`
        if [ -z "$secret_name_tmp" ]; then
            error "secret name not found in YAML file: \"$item\"! Please check and fix it"
            exit 1
        else
            secret_name_tmp=$(sed -e 's/^"//' -e 's/"$//' <<<"$secret_name_tmp")
            # need to check ibm-zen-metastore-edb-cm/im-datastore-edb-cm for Zen/IM and ibm-bts-config-extension external postgresql db support
            if [[ $secret_name_tmp != "ibm-zen-metastore-edb-cm" && $secret_name_tmp != "im-datastore-edb-cm" && $secret_name_tmp != "ibm-bts-config-extension" ]]; then
                secret_exists=`${CLI_CMD} get secret $secret_name_tmp -n $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ "$secret_exists" -ne 2 ] ; then
                    error "Secret \"$secret_name_tmp\" not found in Kubernetes cluster! Please create it before deploying BAI Standalone"
                    SECRET_CREATE_PASSED="false"
                else
                    success "Secret \"$secret_name_tmp\" found in Kubernetes cluster, PASSED!"              
                fi
            else
                secret_exists=`${CLI_CMD} get configmap $secret_name_tmp -n $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ "$secret_exists" -ne 2 ] ; then
                    error "ConfigMap \"$secret_name_tmp\" not found in Kubernetes cluster! Please create it before deploying BAI Standalone"
                    SECRET_CREATE_PASSED="false"
                else
                    success "ConfigMap \"$secret_name_tmp\" found in Kubernetes cluster, PASSED!"              
                fi
            fi
        fi
    done
    
    files=($(find $SECRET_FILE_FOLDER -name '*.sh'))
    for item in ${files[*]}
    do
        if [[ "$machine" == "Mac" ]]; then
            secret_name_tmp=`grep ' create secret generic' $item | tail -1 | cut -d'"' -f2`

            # for DPE secret format specially
            if [ -z "$secret_name_tmp" ]; then
                secret_name_tmp=`grep ' create secret generic' $item | tail -1 | cut -d'"' -f2`
            fi
        else
            secret_name_tmp=`cat $item | grep -oP '(?<=generic ).*?(?= --from-file)'`

            # for DPE secret format specially
            if [ -z "$secret_name_tmp" ]; then
                secret_name_tmp=`cat $item | grep -oP '(?<=generic ).*?(?= \\\\)' | tail -1`
            fi

        fi
        if [ -z "$secret_name_tmp" ]; then
            error "Not found secret name in shell script file: \"$item\"! Please check and fix it"
            exit 1
        else
            secret_name_tmp=$(sed -e 's/^"//' -e 's/"$//' <<<"$secret_name_tmp")
            secret_exists=`${CLI_CMD} get secret $secret_name_tmp -n $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1
            if [ "$secret_exists" -ne 2 ] ; then
                error "Secret \"$secret_name_tmp\" not found in Kubernetes cluster! Please create it before deploying BAI Standalone"
                SECRET_CREATE_PASSED="false"
            else
                success "Secret \"$secret_name_tmp\" found in Kubernetes cluster, PASSED!"              
            fi
        fi
    done
    if [[ $SECRET_CREATE_PASSED == "false" ]]; then
        info "Please create all the secrets required ,exiting..."
        exit 1
    else
        INFO "All secrets created in Kubernetes cluster, PASSED!"
    fi
}

function validate_prerequisites(){
    # check FIPS enabled or disabled
    fips_flag="false"

    # Set default values if variables are not set DBACLD-170075 (Allow customers to customize the country and language being passed to the jar files being used for validation in cp4a-prerequisites.sh)
    BAI_AUTO_LANGUAGE=${BAI_AUTO_LANGUAGE:-"EN"}
    BAI_AUTO_REGION=${BAI_AUTO_REGION:-"US"} 

    # Validate that both values are exactly two characters long
    if [[ ${#BAI_AUTO_LANGUAGE} -ne 2 || ${#BAI_AUTO_REGION} -ne 2 ]]; then
        echo "Error: BAI_AUTO_LANGUAGE and BAI_AUTO_REGION must each be exactly 2 characters long."
        exit 1
    fi

    # validate the storage class
    INFO "Checking Medium/Fast/Block storage class required by BAI stand-alone" 

    tmp_storage_classname=$(prop_user_profile_property_file BAI_STANDALONE.MEDIUM_FILE_STORAGE_CLASSNAME)
    sample_pvc_name="bai-test-medium-pvc-$RANDOM"
    verify_storage_class_valid $tmp_storage_classname "ReadWriteMany" $sample_pvc_name

    tmp_storage_classname=$(prop_user_profile_property_file BAI_STANDALONE.FAST_FILE_STORAGE_CLASSNAME)
    sample_pvc_name="bai-test-fase-pvc-$RANDOM"
    verify_storage_class_valid $tmp_storage_classname "ReadWriteMany" $sample_pvc_name

    tmp_storage_classname=$(prop_user_profile_property_file BAI_STANDALONE.BLOCK_STORAGE_CLASS_NAME)
    sample_pvc_name="bai-test-block-pvc-$RANDOM"
    verify_storage_class_valid $tmp_storage_classname "ReadWriteOnce" $sample_pvc_name

    if [[ $verification_sc_passed == "No" ]]; then
        ${CLI_CMD} delete pvc -l bai=test-only >/dev/null 2>&1
        exit 0
    fi
    # Validate Secret for BAI stand-alone
    validate_secret_in_cluster

    # Validate LDAP connection for BAI stand-alone if LDAP option was selected
    # DBACLD-168779
    if [[ ! ("${#flink_job_cr_arr[@]}" -eq "1" && "${flink_job_cr_arr[@]}" =~ "workflow-process-service" && $LDAP_WFPS_AUTHORING == "No") && $SELECTED_LDAP == "Yes" ]]; then
        INFO "Checking the LDAP connection required by BAI stand-alone" 
        tmp_servername="$(prop_ldap_property_file LDAP_SERVER)"
        tmp_serverport="$(prop_ldap_property_file LDAP_PORT)"
        tmp_basdn="$(prop_ldap_property_file LDAP_BASE_DN)"
        tmp_ldapssl="$(prop_ldap_property_file LDAP_SSL_ENABLED)"
        tmp_user=$( ${CLI_CMD} get secret -l name=ldap-bind-secret -o yaml -n "$BAI_SERVICES_NS" | ${YQ_CMD} r - items.[0].data.ldapUsername | base64 --decode )
        ## <https://jsw.ibm.com/browse/DBACLD-172803> - We are now asking user to use {xor} for special characters in password, so we need to use decode_xor_password to get the password decoded before validation.
        bai_operator=$( ${CLI_CMD} get pods -l name=ibm-bai-insights-engine-operator --no-headers --ignore-not-found -n "$BAI_OPERATORS_NS" | awk '{print $1}' )
        tmp_userpwd=$( decode_xor_password "$( ${CLI_CMD} get secret -n "$BAI_SERVICES_NS" -l name=ldap-bind-secret -o yaml | ${YQ_CMD} r - items.[0].data.ldapPassword | base64 --decode )" "$BAI_OPERATORS_NS" "$bai_operator" | sed  's/\$/\\$/g' )

        tmp_servername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_servername")
        tmp_serverport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_serverport")
        tmp_basdn=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_basdn")
        tmp_ldapssl=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_ldapssl")
        tmp_ldapssl=$(echo $tmp_ldapssl | tr '[:upper:]' '[:lower:]')
        tmp_user=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_user")
        tmp_userpwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_userpwd")

        verify_ldap_connection "$tmp_servername" "$tmp_serverport" "$tmp_basdn" "$tmp_user" "$tmp_userpwd" "$tmp_ldapssl"
    fi

    # Check db connection for im/zen/bts external postgresql db
    local DB_JDBC_NAME=${JDBC_DRIVER_DIR}/postgresql
    local DB_CONNECTION_JAR_PATH=${CUR_DIR}/helper/verification/postgresql

    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        printf "\n"
        im_external_db_cert_folder="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        im_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$im_external_db_cert_folder")

        dbserver="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
        dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
        dbport="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_PORT)"
        dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
        dbname="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_NAME)"
        dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
        dbuser="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_USER)"
        dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
        dbuserpwd="changit" # client auth does not need dbuserpwd

        info "Checking connection for IM metastore external Postgres database \"${dbname}\" that belongs to database instance \"${dbserver}\"...."

        postgres_cafile="${im_external_db_cert_folder}/root.crt"
        postgres_clientkeyfile="${im_external_db_cert_folder}/client.key"
        postgres_clientcertfile="${im_external_db_cert_folder}/client.crt"

        rm -rf ${im_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
        openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${im_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null

        output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        retVal_verify_db_tmp=$?
        connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
        if [[ ! -z $connection_time ]]; then
            display_latency_warning $connection_time "Database"
        fi

        [[ retVal_verify_db_tmp -ne 0 ]] && \
        warning "Execute: $JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
        [[ retVal_verify_db_tmp -eq 0 ]] && \
        success "The DB connection check for \"$dbname\" on database server \"$dbserver\" PASSED!"
    fi

    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        printf "\n"
        zen_external_db_cert_folder="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        zen_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$zen_external_db_cert_folder")

        dbserver="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
        dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
        dbport="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_PORT)"
        dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
        dbname="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_NAME)"
        dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
        dbuser="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_USER)"
        dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
        dbuserpwd="changit" # client auth does not need dbuserpwd

        info "Checking connection for Zen metastore external Postgres database \"${dbname}\" that belongs to database instance \"${dbserver}\"...."

        postgres_cafile="${zen_external_db_cert_folder}/root.crt"
        postgres_clientkeyfile="${zen_external_db_cert_folder}/client.key"
        postgres_clientcertfile="${zen_external_db_cert_folder}/client.crt"

        rm -rf ${zen_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
        openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${zen_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null

        output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        retVal_verify_db_tmp=$?
        connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
        if [[ ! -z $connection_time ]]; then
            display_latency_warning $connection_time "Database"
        fi

        [[ retVal_verify_db_tmp -ne 0 ]] && \
        warning "Execute: $JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
        [[ retVal_verify_db_tmp -eq 0 ]] && \
        success "The DB connection check for \"$dbname\" on database server \"$dbserver\" PASSED!"
    fi

    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        printf "\n"
        bts_external_db_cert_folder="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        bts_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$bts_external_db_cert_folder")

        dbserver="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_HOSTNAME)"
        dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
        dbport="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_PORT)"
        dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
        dbname="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_NAME)"
        dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
        dbuser="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_USER_NAME)"
        dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
        dbuserpwd="changit" # client auth does not need dbuserpwd

        info "Checking connection for BTS metastore external Postgres database \"${dbname}\" that belongs to database instance \"${dbserver}\"...."

        postgres_cafile="${bts_external_db_cert_folder}/root.crt"
        postgres_clientkeyfile="${bts_external_db_cert_folder}/client.key"
        postgres_clientcertfile="${bts_external_db_cert_folder}/client.crt"

        rm -rf ${bts_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
        openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${bts_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null

        output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        retVal_verify_db_tmp=$?
        connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
        if [[ ! -z $connection_time ]]; then
            display_latency_warning $connection_time "Database"
        fi

        [[ retVal_verify_db_tmp -ne 0 ]] && \
        warning "Execute: $JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
        [[ retVal_verify_db_tmp -eq 0 ]] && \
        success "The DB connection check for \"$dbname\" on database server \"$dbserver\" PASSED!"
    fi

    info "If all prerequisites check have PASSED, you can run bai-deployment.sh script to deploy BAI stand-alone. Otherwise, please check the configuration again."
    info "After BAI stand-alone is deployed, please refer to the documentation for post-deployment steps."
}
# This function helps parse arguments that are passed to the script, checks and assigns runtime mode and target namespace variables based on the -m and -n parameters passed
function parse_arguments() {
    local args=("$@")
    local i=0
    
    while [ $i -lt ${#args[@]} ]; do
        local key="${args[$i]}"
        case $key in
        -m)
            ((i++))
            if [ $i -ge ${#args[@]} ] || [ -z "${args[$i]}" ]; then
                echo "Invalid option: -m requires an argument"
                exit 1
            fi
            RUNTIME_MODE="${args[$i]}"
            if [[ $RUNTIME_MODE == "property" || $RUNTIME_MODE == "generate" || $RUNTIME_MODE == "validate" ]]; then
                echo
            else
                msg "Use a valid value: -m [property] or [generate] or [validate]"
                exit 1
            fi
            ;;
        -n)
            ((i++))
            if [ $i -ge ${#args[@]} ] || [ -z "${args[$i]}" ]; then
                echo "Invalid option: -n requires an argument"
                exit 1
            fi
            TARGET_PROJECT_NAME="${args[$i]}"
            case "$TARGET_PROJECT_NAME" in
            "")
                echo -e "\x1B[1;31mEnter a valid namespace name, namespace name can not be blank\x1B[0m"
                exit 1
                ;;
            "openshift"*)
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
                exit 1
                ;;
            "kube"*)
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
                exit 1
                ;;
            *)
                # Check cluster login
                check_cluster_login
                # Check project name
                isProjExists=`${CLI_CMD} get namespace $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ $isProjExists -ne 2 ] ; then
                    echo -e "\x1B[1;31mInvalid project name \"$TARGET_PROJECT_NAME\", please set a existing project name.\x1B[0m"
                    exit 1
                fi
                echo -n
                ;;
            esac
            ;;
        -h|--help|\?)
            show_help
            exit 0
            ;;
        --java-path)
            ((i++))
            if [ $i -ge ${#args[@]} ] || [ -z "${args[$i]}" ]; then
                echo "Invalid option: --java-path requires an argument"
                exit 1
            fi
            CUSTOM_JAVA_PATH="${args[$i]}"
            # Verify the path exists
            if [ ! -d "$CUSTOM_JAVA_PATH" ]; then
                echo -e "\x1B[1;31mThe specified Java (JRE) path does not exist: ${CUSTOM_JAVA_PATH}\x1B[0m"
                exit 1
            fi
            ;;
        --java-path=*)
            CUSTOM_JAVA_PATH="${key#*=}"
            if [ -z "$CUSTOM_JAVA_PATH" ]; then
                echo "Invalid option: --java-path requires a value"
                exit 1
            fi
            # Verify the path exists
            if [ ! -d "$CUSTOM_JAVA_PATH" ]; then
                echo -e "\x1B[1;31mThe specified Java (JRE) path does not exist: ${CUSTOM_JAVA_PATH}\x1B[0m"
                exit 1
            fi
            ;;
        *)
            echo "Invalid option: $key"
            show_help
            exit 1
            ;;
        esac
        ((i++))
    done
}

################################################
#### Begin - Main step for install operator ####
################################################

parse_arguments "$@"
if [[ -z "$RUNTIME_MODE" ]]; then
    echo -e "\x1B[1;31mPlease input value for \"-m <MODE_TYPE>\" option.\n\x1B[0m"
    show_help
    exit 1
fi
if [[ -z "$TARGET_PROJECT_NAME" ]]; then
    echo -e "\x1B[1;31mPlease input value for \"-n <BAI_NAMESPACE>\" option.\n\x1B[0m"
    show_help
    exit 1
fi

# Log files to be generated in the folder specific to the project being used with the scripts
# For DBACLD-166508
save_log "bai-script-logs/project/$TARGET_PROJECT_NAME" "bai-prerequisites-log"
trap cleanup_log EXIT

info "The bai-prerequisite script is currently being executed in the ${RUNTIME_MODE} mode"
printf "\n"

# Import common utilities and environment variables
# Preserve OPTIONAL_PARAMETERS_LIST before sourcing common.sh to avoid resetting it
SAVED_OPTIONAL_PARAMETERS_LIST=("${OPTIONAL_PARAMETERS_LIST[@]}")
source ${CUR_DIR}/helper/common.sh $TARGET_PROJECT_NAME
# Restore OPTIONAL_PARAMETERS_LIST after sourcing common.sh
OPTIONAL_PARAMETERS_LIST=("${SAVED_OPTIONAL_PARAMETERS_LIST[@]}")

clear

if [[ $RUNTIME_MODE == "property" ]]; then
    # Check separation of duties
    check_bai_separate_operand $TARGET_PROJECT_NAME # Function Definition can be found in helper/upgrade/upgrade_check_status.sh

    prompt_license
    input_information
    create_property_file
    clean_up_temp_file
fi
if [[ $RUNTIME_MODE == "generate" ]]; then
    # Check separation of duties
    check_bai_separate_operand $TARGET_PROJECT_NAME # Function Definition can be found in helper/upgrade/upgrade_check_status.sh    

    # reload db type and OS number
    load_property_before_generate
    check_property_file
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        create_prerequisites
        clean_up_temp_file
        generate_create_secret_script
    else
        warning "No LDAP configuration was selected, so the secret YAML template will not be generated."
        sleep 2
    fi
fi

if [[ $RUNTIME_MODE == "validate" ]]; then
    echo  "*****************************************************"
    echo  "Validating the prerequisites before you install BAI stand-alone"
    echo  "*****************************************************"
    # Check separation of duties
    check_bai_separate_operand $TARGET_PROJECT_NAME # Function Definition can be found in helper/upgrade/upgrade_check_status.sh 

    validate_utility_tool_for_validation
    load_property_before_generate
    validate_prerequisites
fi
################################################
#### End - Main step for install operator ####
################################################
