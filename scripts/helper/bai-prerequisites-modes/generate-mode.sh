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


# This file is a helper script used to store all functions that are used by the bai-prerequistes.sh in the generate mode

#### Start - Functions being called by the check_property_file function ####

# Function that checks if there are any missing quotes in any property files after the user updates the property files
# For https://jsw.ibm.com/browse/DBACLD-161426
function check_missing_quotes(){
    missing_quotes=0
    property_files=("${USER_PROFILE_PROPERTY_FILE}" "${DB_SERVER_INFO_PROPERTY_FILE}" "${DB_NAME_USER_PROPERTY_FILE}" "${LDAP_PROPERTY_FILE}" "${EXTERNAL_LDAP_PROPERTY_FILE}")
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

#### END - Functions being called by the check_property_file function ####

# Function to check if there are valid properties entered
function check_property_file(){

    # Initialize OPTIONAL_PARAMETERS_LIST (it gets reset in common.sh)
    OPTIONAL_PARAMETERS_LIST=()

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
    check_required_values "<{xor}<Required>" "${USER_PROFILE_PROPERTY_FILE}"
    
    # Check for empty values in the user profile property file
    validate_property_file_required_fields "${USER_PROFILE_PROPERTY_FILE}"

    ### BEGIN LDAP Property file checks  ###
    # Conditionally mark LDAP SSL params optional BEFORE validating LDAP files
    # so the validator will skip them when SSL is disabled

    # First, remove any existing SSL parameters from the optional list to handle toggling
    OPTIONAL_PARAMETERS_LIST=($(printf '%s\n' "${OPTIONAL_PARAMETERS_LIST[@]}" | grep -v "^LDAP_SSL_SECRET_NAME$" | grep -v "^LDAP_SSL_CERT_FILE_FOLDER$"))

    if [[ $selected_ldap_flag == "Yes" ]]; then
        tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_ldap_property_file LDAP_SSL_ENABLED)")
        tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
        if [[ ${tmp_flag} =~ ^(no|n|false)$ ]]; then
            OPTIONAL_PARAMETERS_LIST+=("LDAP_SSL_SECRET_NAME")
            OPTIONAL_PARAMETERS_LIST+=("LDAP_SSL_CERT_FILE_FOLDER")
        fi
    fi

    # Persist optional list before any LDAP validations
    mark_optional
    
    if [[ $selected_ldap_flag == "Yes" ]]; then
        check_required_values "<Required>" "${LDAP_PROPERTY_FILE}"
        check_required_values "{Base64}<Required>" "${LDAP_PROPERTY_FILE}"
        ## -- https://jsw.ibm.com/browse/DBACLD-172803 - We are now asking user to use {xor} for special characters in password for some parameters, so we need to check if the "{xor}<Required>" is not filled out.
        check_required_values "{xor}<Required>" "${LDAP_PROPERTY_FILE}"

        # Check for empty values in the ldap property file
        validate_property_file_required_fields "${LDAP_PROPERTY_FILE}"
    fi

    if [[ "$empty_value_tag" == "1" ]]; then
        exit 1
    fi
    ### END LDAP Property file checks  ###

    ### BEGIN USER Property file checks ###

    # Check keystorePassword in ibm-fncm-secret and ibm-ban-secret must exceed 16 characters when fips enabled.
    # FIPS is always false (not supported)
    fips_flag="false"

    # Check the directory for certificate should be different for IM/Zen/BTS/cp4ba_tls_issuer
    # IM metastore external Postgres DB
    cert_dir_array=()
    #tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    #tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $EXTERNAL_POSTGRESDB_FOR_IM_FLAG == "true" || $EXTERNAL_POSTGRESDB_FOR_IM_FLAG == "yes" || $EXTERNAL_POSTGRESDB_FOR_IM_FLAG == "y" ]]; then
        im_external_db_cert_folder="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        im_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$im_external_db_cert_folder")
        cert_dir_array=( "${cert_dir_array[@]}" "${im_external_db_cert_folder}" )
    fi

    # Zen metastore external Postgres DB
    #tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    #tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG == "true" || $EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG == "yes" || $EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG == "y" ]]; then
        zen_external_db_cert_folder="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        zen_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$zen_external_db_cert_folder")
        cert_dir_array=( "${cert_dir_array[@]}" "${zen_external_db_cert_folder}" )
    fi

    # BTS metastore external Postgres DB
    #tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
    #tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS_FLAG == "true" || $EXTERNAL_POSTGRESDB_FOR_BTS_FLAG == "yes" || $EXTERNAL_POSTGRESDB_FOR_BTS_FLAG == "y" ]]; then
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

    ### END USER Property file checks ###
}

#### Start - Functions being called by the generate_secrets function ####


# Function Generate the LDAP bind secret and LDAP SSL secret if required
# Function called in the generate_secrets functions
function generate_ldap_secret_templates(){
    # Create LDAP bind secret
    create_ldap_secret_template
    #  replace ldap user
    tmp_dbuser="$(prop_ldap_property_file LDAP_BIND_DN)"
    ${SED_COMMAND} "s|\"<LDAP_BIND_DN>\"|\"$tmp_dbuser\"|g" ${LDAP_SECRET_FILE}

    # For https://jsw.ibm.com/browse/DBACLD-157020
    # Function that updates the secret template with the base64 password
    tmp_ldapuserpwd="$(prop_ldap_property_file LDAP_BIND_DN_PASSWORD)"
    update_secret_template_passwords $tmp_ldapuserpwd "ldapPassword" "$LDAP_SECRET_FILE"

    #if [[ "${tmp_ldapuserpwd:0:8}" == "{Base64}"  ]]; then
    #    temp_val=$(echo "$tmp_ldapuserpwd" | sed -e "s/^{Base64}//" | base64 --decode) 
    #    ${SED_COMMAND} "s|\"<LDAP_PASSWORD>\"|'$(printf '%q' $temp_val)'|g" ${LDAP_SECRET_FILE}
    #else
    #    ${SED_COMMAND} "s|\"<LDAP_PASSWORD>\"|\"$tmp_ldapuserpwd\"|g" ${LDAP_SECRET_FILE}
    #fi
    
    # IF LDAP SSL Enabled
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
}

# Function to generate the secrets and configamps required for external postgres enabled for IM
# This function is called by generate secrets
function generate_external_postgres_secrets_configmaps_for_im(){
    
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
}

# Function to generate the secrets and configamps required for external postgres enabled for ZEN
# This function is called by generate secrets
function generate_external_postgres_secrets_configmaps_for_zen(){
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
}

# Function to generate the secrets and configamps required for external postgres enabled for BTS
# This function is called by generate secrets
function generate_external_postgres_secrets_configmaps_for_bts(){
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
}

#### END - Functions being called by the generate_secrets function ####

# Generating the secret templates if required
function generate_secrets() {
    rm -rf $SECRET_FILE_FOLDER
    INFO "Generating YAML templates for secrets required by BAI stand-alone deployment based on property file"
    printf "\n"
    wait_msg "Creating YAML templates for secrets"

    # Create LDAP Secret templates if required
    if [[ $selected_ldap_flag == "Yes" ]]; then
        # Function that will generate the LDAP bind secret and the LDAP SSL secret if required
        generate_ldap_secret_templates
    fi

    # Create Secret/configMap for IM metastore external Postgres DB
    if [[ $EXTERNAL_POSTGRESDB_FOR_IM_FLAG == "true" ]]; then
        generate_external_postgres_secrets_configmaps_for_im
    fi

    # Create Secret/configMap for Zen metastore external Postgres DB
    if [[ $EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG == "true" ]]; then
        generate_external_postgres_secrets_configmaps_for_zen
    fi

    # Create Secret/configMap for BTS metastore external Postgres DB
    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS_FLAG == "true" ]]; then
        generate_external_postgres_secrets_configmaps_for_bts
    fi


    ### BEGIN - Section that prints the tips and next actions statements ###
    
    tips
    msgB "* Enter the <Required> values in the YAML templates for the secrets under $SECRET_FILE_FOLDER"

    msgB "* You can use this shell script to create the secret automatically: $CREATE_SECRET_SCRIPT_FILE"
    msgB "* Create the Kubernetes secrets manually based on your modified \"YAML template for secret\".\n* And then run the  \"bai-prerequisites.sh -m validate\" command to verify that the secrets are created correctly"

    ### END - Section that prints the tips and next actions statements ###
}


# Function to creates the script that can apply all secret templates in the cluster
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