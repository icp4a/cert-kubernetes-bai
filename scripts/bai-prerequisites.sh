#!/bin/bash
# set -x
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
    echo -e "\nUsage: bai-prerequisites.sh -m [modetype]\n"
    echo "Options:"
    echo "  -h  Display help"
    echo "  -m  The valid mode types are: [property], [generate], or [validate]"
    echo ""
    echo "  STEP1: Run the script in [property] mode. It creates property files (LDAP property file) with default values (BASE DN/BIND DN ...)."
    echo "  STEP2: Modify the LDAP/user property files with your values."
    echo "  STEP3: Run the script in [generate] mode. Generates the YAML templates for the secrets based on the values in the property files."
    echo "  STEP4: Create the databases and secrets by using the modified YAML templates for the secrets."
    echo "  STEP5: Run the script in [validate] mode. Checks the secrets are created before you install IBM Business Automation Insights."
}

function prompt_license(){
    # clear

    echo -e "\x1B[1;31mIMPORTANT: Review the IBM Business Automation Insights stand-alone license information here: \n\x1B[0m"
    echo -e "\x1B[1;31mhttps://www14.software.ibm.com/cgi-bin/weblap/lap.pl?li_formnum=L-PSZC-SHQFWS\n\x1B[0m"

    read -rsn1 -p"Press any key to continue";echo

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
            echo -e "Exiting...\n"
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
    which java &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e  "\x1B[1;31mUnable to locate java. You must install it to run this script.\x1B[0m" && \
        while true; do
            printf "\x1B[1mDo you want install the IBM JRE by the bai-prerequisites.sh script? (Yes/No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                install_ibm_jre
                break
                ;;
            "n"|"N"|"no"|"No"|"NO")
                info "IBM JRE or other JRE must be installed for the next validation"
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    else
        java -version &>/dev/null
        if [[ $? -ne 0 ]]; then
            echo -e  "\x1B[1;31mUnable to locate a Java Runtime. You must install JRE to run this script.\x1B[0m" && \
            while true; do
                printf "\x1B[1mDo you want install the IBM JRE by the bai-prerequisites.sh script? (Yes/No): \x1B[0m"
                read -rp "" ans
                case "$ans" in
                "y"|"Y"|"yes"|"Yes"|"YES")
                    install_ibm_jre
                    break
                    ;;
                "n"|"N"|"no"|"No"|"NO")
                    info "Must install the IBM JRE or other JRE to continue next validation"
                    exit 1
                    ;;
                *)
                    echo -e "Answer must be \"Yes\" or \"No\"\n"
                    ;;
                esac
            done    
        fi
    fi
    which keytool &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e  "\x1B[1;31mUnable to locate keytool. You must add it in \"\$PATH\" to run this script.\x1B[0m" && \
        exit 1
    else
        keytool -help &>/dev/null
        if [[ $? -ne 0 ]]; then
            echo -e  "\x1B[1;31mUnable to locate keytool. You must install the IBM JRE or other JRE and add keytool in \"\$PATH\" to run this script\x1B[0m" && \
            exit 1     
        fi
    fi

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
    # read -rsn1 -p"Press any key to continue (DEBUG MODEL)";echo
    # Generate list of the pattern which will be installed or To Be Uninstalled
    for i in ${!options[@]}; do
        [[ "${choices_pattern[i]}" ]] && { flink_job_arr=( "${flink_job_arr[@]}" "${options[i]}" ); flink_job_cr_arr=( "${flink_job_cr_arr[@]}" "${options_cr_val[i]}" ); msg=""; }
    done
    # echo -e "$msg"

    if [ "${#flink_job_arr[@]}" -eq "0" ]; then
        FLINK_JOB_SELECTED="None"
        warning "None components selected for flink job, continue... \n"
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

    # read -rsn1 -p"Press any key to continue (DEBUG MODEL)";echo
}

function check_property_file(){
    local empty_value_tag=0
    value_empty=`grep '="<Required>"' "${USER_PROFILE_PROPERTY_FILE}" | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Found invalid value(s) \"<Required>\" in property file \"${USER_PROFILE_PROPERTY_FILE}\", please input the correct value."
        empty_value_tag=1
    fi

    value_empty=`grep '="<Required>"' "${DB_SERVER_INFO_PROPERTY_FILE}" | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Found invalid value(s) \"<Required>\" in property file \"${DB_SERVER_INFO_PROPERTY_FILE}\", please input the correct value."
        empty_value_tag=1
    fi

    value_empty=`grep '^<DB_SERVER_NAME>.' "${DB_NAME_USER_PROPERTY_FILE}" | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Please change prefix \"<DB_SERVER_NAME>\" to assign database used by component to which database server or instance in property file \"${DB_NAME_USER_PROPERTY_FILE}\"."
        empty_value_tag=1
    fi

    # check DB_SERVER_LIST contains doc char
    tmp_dbservername=$(prop_db_server_property_file DB_SERVER_LIST)
    tmp_dbservername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbservername")
    value_empty=`echo "${tmp_dbservername}" | grep '\.' | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Found dot character(.) from the value of \"DB_SERVER_LIST\" parameter in property file \"${DB_SERVER_INFO_PROPERTY_FILE}\"."
        empty_value_tag=1
    fi

    # check ADP_PROJECT_DB_SERVER contain <DB_SERVER_NAME>
    if [[ " ${flink_job_cr_arr[@]}" =~ "document_processing" ]]; then
        tmp_dbserver="$(prop_db_name_user_property_file ADP_PROJECT_DB_SERVER)"
        tmp_dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbserver")
        value_empty=`echo $tmp_dbserver | grep '<DB_SERVER_NAME>' | wc -l`  >/dev/null 2>&1
        if [ $value_empty -ne 0 ] ; then
            error "Please change \"<DB_SERVER_NAME>\" for \"ADP_PROJECT_DB_SERVER\" parameter to assign database used by component to which database server or instance in property file \"${DB_NAME_USER_PROPERTY_FILE}\"."
            empty_value_tag=1
        fi
    fi

    value_empty=`grep '="<Required>"' "${DB_NAME_USER_PROPERTY_FILE}" | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Found invalid value(s) \"<Required>\" in property file \"${DB_NAME_USER_PROPERTY_FILE}\", please input the correct value."
        empty_value_tag=1
    fi

    value_empty=`grep -v '^# .*.CHOS_DB_USER_PASSWORD="<yourpassword>"' "${DB_NAME_USER_PROPERTY_FILE}" | grep '="<yourpassword>"' | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Found invalid value(s) \"<yourpassword>\" in property file \"${DB_NAME_USER_PROPERTY_FILE}\", please input the correct value."
        empty_value_tag=1
    fi

    value_empty=`grep -v '^# .*.CHOS_DB_USER_NAME="<youruser1>"' "${DB_NAME_USER_PROPERTY_FILE}" | grep '="<youruser1>"' | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Found invalid value(s) \"<youruser1>\" in property file \"${DB_NAME_USER_PROPERTY_FILE}\", please input the correct value."
        empty_value_tag=1
    fi

    value_empty=`grep '="<Required>"' "${LDAP_PROPERTY_FILE}" | wc -l`  >/dev/null 2>&1
    if [ $value_empty -ne 0 ] ; then
        error "Found invalid value(s) \"<Required>\" in property file \"${LDAP_PROPERTY_FILE}\", please input the correct value."
        empty_value_tag=1
    fi

    if [[ $SET_EXT_LDAP == "Yes" ]]; then
        value_empty=`grep '="<Required>"' "${EXTERNAL_LDAP_PROPERTY_FILE}" | wc -l`  >/dev/null 2>&1
        if [ $value_empty -ne 0 ] ; then
            error "Found invalid value(s) \"<Required>\" in property file \"${EXTERNAL_LDAP_PROPERTY_FILE}\", please input the correct value."
            empty_value_tag=1
        fi
    fi

    # check prefix in db property is correct element of DB_SERVER_LIST
    tmp_db_array=$(prop_db_server_property_file DB_SERVER_LIST)
    tmp_db_array=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_db_array")
    OIFS=$IFS
    IFS=',' read -ra db_server_array <<< "$tmp_db_array"
    IFS=$OIFS

    # check DB_NAME_USER_PROPERTY_FILE
    prefix_array=($(grep '=\"' ${DB_NAME_USER_PROPERTY_FILE} | cut -d'=' -f1 | cut -d'.' -f1 | grep -Ev 'ADP_PROJECT_DB_NAME|ADP_PROJECT_DB_SERVER|ADP_PROJECT_DB_USER_NAME|ADP_PROJECT_DB_USER_PASSWORD|ADP_PROJECT_ONTOLOGY'))
    for item in ${prefix_array[*]}
    do
        if [[ ! ( "${item}" == \#* ) ]]; then
            if [[ ! (" ${db_server_array[@]}" =~ "${item}") ]]; then
                error "The prefix \"$item\" is not in the definition DB_SERVER_LIST=\"${tmp_db_array}\", please check follow example to configure \"${DB_NAME_USER_PROPERTY_FILE}\" again."
                echo -e "***************** example *****************"
                echo -e "if DB_SERVER_LIST=\"DBSERVER1\""
                echo -e "You need to change"
                echo -e "<DB_SERVER_NAME>.GCD_DB_NAME=\"GCDDB\""
                echo -e "to"
                echo -e "DBSERVER1.GCD_DB_NAME=\"GCDDB\""
                echo -e "***************** example *****************"
                empty_value_tag=1
                break
            fi
        fi
    done

    # check DB_SERVER_INFO_PROPERTY_FILE
    prefix_array=($(grep '=\"' ${DB_SERVER_INFO_PROPERTY_FILE} | cut -d'=' -f1 | cut -d'.' -f1 | tail -n +2))
    for item in ${prefix_array[*]}
    do
        if [[ ! (" ${db_server_array[@]}" =~ "${item}") ]]; then
            error "The prefix \"$item\" is not in the definition DB_SERVER_LIST=\"${tmp_db_array}\", please check follow example to configure \"${DB_SERVER_INFO_PROPERTY_FILE}\" again."
            echo -e "********************* example *********************"
            echo -e "if DB_SERVER_LIST=\"DBSERVER1\""
            echo -e "You need to change"
            echo -e "<DB_SERVER_NAME>.DATABASE_SERVERNAME=\"samplehost\""
            echo -e "to"
            echo -e "DBSERVER1.DATABASE_SERVERNAME=\"samplehost\""
            echo -e "********************* example *********************"
            empty_value_tag=1
            break
        fi
    done

    if [[ "$empty_value_tag" == "1" ]]; then
        exit 1
    fi

    # Check the PostgreSQL DATABASE_SSL_ENABLE/POSTGRESQL_SSL_CLIENT_SERVER
    for item in ${db_server_array[*]}
    do
        db_ssl_flag="$(prop_db_server_property_file ${item}.DATABASE_SSL_ENABLE)"
        client_auth_flag="$(prop_db_server_property_file ${item}.POSTGRESQL_SSL_CLIENT_SERVER)"
        db_ssl_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$db_ssl_flag")
        client_auth_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$client_auth_flag")
        db_ssl_flag_tmp=$(echo $db_ssl_flag | tr '[:upper:]' '[:lower:]')
        client_auth_flag_tmp=$(echo $client_auth_flag | tr '[:upper:]' '[:lower:]')
        if [[ ($db_ssl_flag_tmp == "no" || $db_ssl_flag_tmp == "false" || $db_ssl_flag_tmp == "" || -z $db_ssl_flag_tmp) && ($client_auth_flag_tmp == "yes" || $client_auth_flag_tmp == "true") ]]; then
            error "The property \"${item}.DATABASE_SSL_ENABLE\" is \"$db_ssl_flag\", but the property \"${item}.POSTGRESQL_SSL_CLIENT_SERVER\" is \"$client_auth_flag\""
            echo -e "********************* example *********************"
            echo -e "if ${item}.DATABASE_SSL_ENABLE=\"False\""
            echo -e "You also need to change"
            echo -e "${item}.POSTGRESQL_SSL_CLIENT_SERVER=\"False\""
            echo -e "********************* example *********************"
            error_value_tag=1
        fi
    done

    # check BAN.LTPA_PASSWORD same as CONTENT.LTPA_PASSWORD
    if [[ " ${flink_job_cr_arr[@]}" =~ "workflow-runtime" || " ${flink_job_cr_arr[@]}" =~ "workflow-authoring" || " ${flink_job_cr_arr[@]}" =~ "content" || " ${flink_job_cr_arr[@]}" =~ "document_processing" || "${optional_component_cr_arr[@]}" =~ "ae_data_persistence" ]]; then
        content_tmp_ltpapwd="$(prop_user_profile_property_file CONTENT.LTPA_PASSWORD)"
        ban_tmp_ltpapwd="$(prop_user_profile_property_file BAN.LTPA_PASSWORD)"
        content_tmp_ltpapwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$content_tmp_ltpapwd")
        ban_tmp_ltpapwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$ban_tmp_ltpapwd")

        if [[ (! -z "$content_tmp_ltpapwd") && (! -z "$ban_tmp_ltpapwd") ]]; then
            if [[ "$ban_tmp_ltpapwd" != "$content_tmp_ltpapwd" ]]; then
                fail "The CONTENT.LTPA_PASSWORD: \"$content_tmp_ltpapwd\" is NOT equal to BAN.LTPA_PASSWORD: \"$ban_tmp_ltpapwd\"."
                echo "The value of CONTENT.LTPA_PASSWORD must be equal to the value of BAN.LTPA_PASSWORD."
                error_value_tag=1
            fi
        else
            if [[ -z "$content_tmp_ltpapwd" ]]; then
                fail "The CONTENT.LTPA_PASSWORD is empty, it is required one valid value."
                error_value_tag=1
            fi
            if [[ -z "$ban_tmp_ltpapwd" ]]; then
                fail "The BAN.LTPA_PASSWORD is empty, it is required one valid value."
                error_value_tag=1
            fi
        fi
    fi

    # Check keystorePassword in ibm-fncm-secret and ibm-ban-secret must exceed 16 characters when fips enabled.
    # FIPS is always false (not supported)
    fips_flag="false"

    if [[ " ${flink_job_cr_arr[@]}" =~ "workflow-runtime" || " ${flink_job_cr_arr[@]}" =~ "workflow-authoring" || " ${flink_job_cr_arr[@]}" =~ "workstreams" || " ${flink_job_cr_arr[@]}" =~ "content" || " ${flink_job_cr_arr[@]}" =~ "document_processing" || "${optional_component_cr_arr[@]}" =~ "ae_data_persistence" ]]; then
        if [[ (! -z $fips_flag) && $fips_flag == "true" ]]; then
            content_tmp_keystorepwd="$(prop_user_profile_property_file CONTENT.KEYSTORE_PASSWORD)"
            if [[ ! -z $content_tmp_keystorepwd ]]; then
                content_tmp_keystorepwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$content_tmp_keystorepwd")
                if [[ ${#content_tmp_keystorepwd} -lt 16 ]]; then
                    fail "CONTENT.KEYSTORE_PASSWORD must exceed 16 characters when fips enabled in BAI_user_profile.property."
                    error_value_tag=1
                fi
            fi
        fi
    fi

    if [[ " ${foundation_component_arr[@]}" =~ "BAN" ]]; then
        if [[ (! -z $fips_flag) && $fips_flag == "true" ]]; then
            ban_tmp_keystorepwd="$(prop_user_profile_property_file BAN.KEYSTORE_PASSWORD)"
            if [[ ! -z $ban_tmp_keystorepwd ]]; then
                ban_tmp_keystorepwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$ban_tmp_keystorepwd")
                if [[ ${#ban_tmp_keystorepwd} -lt 16 ]]; then
                    fail "BAN.KEYSTORE_PASSWORD must exceed 16 characters when fips enabled in BAI_user_profile.property."
                    error_value_tag=1
                fi
            fi
        fi
    fi

    if [[ " ${optional_component_cr_arr[@]}" =~ "iccsap" ]]; then
        if [[ (! -z $fips_flag) && $fips_flag == "true" ]]; then
            iccsap_tmp_keystorepwd="$(prop_user_profile_property_file ICCSAP.KEYSTORE_PASSWORD)"
            if [[ ! -z $iccsap_tmp_keystorepwd ]]; then
                iccsap_tmp_keystorepwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$iccsap_tmp_keystorepwd")
                if [[ ${#iccsap_tmp_keystorepwd} -lt 16 ]]; then
                    fail "ICCSAP.KEYSTORE_PASSWORD must exceed 16 characters when fips enabled in BAI_user_profile.property."
                    error_value_tag=1
                fi
            fi
        fi
    fi

    if [[ " ${optional_component_cr_arr[@]}" =~ "ier" ]]; then
        if [[ (! -z $fips_flag) && $fips_flag == "true" ]]; then
            ier_tmp_keystorepwd="$(prop_user_profile_property_file IER.KEYSTORE_PASSWORD)"
            if [[ ! -z $ier_tmp_keystorepwd ]]; then
                ier_tmp_keystorepwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$ier_tmp_keystorepwd")
                if [[ ${#ier_tmp_keystorepwd} -lt 16 ]]; then
                    fail "IER.KEYSTORE_PASSWORD must exceed 16 characters when fips enabled in BAI_user_profile.property."
                    error_value_tag=1
                fi
            fi
        fi
    fi

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

    if [[ "$error_value_tag" == "1" ]]; then
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

        #  replace <DatabaseUser>
        tmp_name="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_USER_NAME)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<USERNAME>|$tmp_name|g" ${BTS_SECRET_FILE}

        #  replace <DatabaseUser_password>
        tmp_name="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_USER_PASSWORD)"
        tmp_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_name")
        ${SED_COMMAND} "s|<PASSWORD>|$tmp_name|g" ${BTS_SECRET_FILE}

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

    fi


    tips
    msgB "* Enter the <Required> values in the YAML templates for the secrets under $SECRET_FILE_FOLDER"

    # LDAP: Show which certificate file should be copy into which folder 
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_ldap_property_file LDAP_SSL_ENABLED)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')

    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        tmp_folder="$(prop_ldap_property_file LDAP_SSL_CERT_FILE_FOLDER)"
        tmp_ldapserver="$(prop_ldap_property_file LDAP_SERVER)"
        msgB "* Get the \"ldap-cert.crt\" from the remote LDAP server \"$tmp_ldapserver\", and copy it into the folder \"$tmp_folder\" before you create the Kubernetes secret for the LDAP SSL"
    fi

    # show tips for IM metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        msgB "* You have enabled IM metastore external Postgres DB, please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from your local or remote database server \"$im_external_db_host_name\", and copy them into folder \"$im_external_db_cert_folder\" before you create the secret for PostgreSQL database SSL"
    fi

    # show tips for Zen metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        msgB "* You have enabled Zen metastore external Postgres DB, please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from your local or remote database server \"$zen_external_db_host_name\", and copy them into folder \"$zen_external_db_cert_folder\" before you create the secret for PostgreSQL database SSL"
    fi

    # show tips for BTS metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        msgB "* You have enabled BTS metastore external Postgres DB, please get \"<your-server-certification: root.crt>\" \"<your-client-certification: client.crt>\" \"<your-client-key: client.key>\" from your local or remote database server \"$im_external_db_host_name\", and copy them into folder \"$im_external_db_cert_folder\" before you create the secret for PostgreSQL database SSL"
    fi

    msgB "* You can use this shell script to create the secret automatically: $CREATE_SECRET_SCRIPT_FILE"
    msgB "* Create the Kubernetes secrets manually based on your modified \"YAML template for secret\".\n* And then run the  \"bai-prerequisites.sh -m validate\" command to verify that the databases and secrets are created correctly"
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
        else
            ${SED_COMMAND} "s|LDAP_TYPE=\"\"|LDAP_TYPE=\"Custom\"|g" ${LDAP_PROPERTY_FILE}
            for i in "${!CUSTOM_LDAP_PROPERTY[@]}"; do
                echo "${COMMENTS_CUSTOM_LDAP_PROPERTY[i]}" >> ${LDAP_PROPERTY_FILE}
                echo "${CUSTOM_LDAP_PROPERTY[i]}=\"\"" >> ${LDAP_PROPERTY_FILE}
                echo "" >> ${LDAP_PROPERTY_FILE}
            done
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
            ${SED_COMMAND} "s|LC_AD_GC_PORT=\"\"|LC_AD_GC_PORT=\"<Optional>\"|g" ${LDAP_PROPERTY_FILE}
        elif [[ $LDAP_TYPE == "TDS" ]]; then
            ${SED_COMMAND} "s|LDAP_USER_NAME_ATTRIBUTE=\"\"|LDAP_USER_NAME_ATTRIBUTE=\"*:uid\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_USER_DISPLAY_NAME_ATTR=\"\"|LDAP_USER_DISPLAY_NAME_ATTR=\"cn\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_NAME_ATTRIBUTE=\"\"|LDAP_GROUP_NAME_ATTRIBUTE=\"*:cn\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_DISPLAY_NAME_ATTR=\"\"|LDAP_GROUP_DISPLAY_NAME_ATTR=\"cn\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"\"|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"(\|(\&(objectclass=groupofnames)(member={0}))(\&(objectclass=groupofuniquenames)(uniquemember={0})))\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_MEMBER_ID_MAP=\"\"|LDAP_GROUP_MEMBER_ID_MAP=\"groupofnames:member\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LC_USER_FILTER=\"\"|LC_USER_FILTER=\"(\&(cn=%v)(objectclass=person))\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LC_GROUP_FILTER=\"\"|LC_GROUP_FILTER=\"(\&(cn=%v)(\|(objectclass=groupofnames)(objectclass=groupofuniquenames)(objectclass=groupofurls)))\"|g" ${LDAP_PROPERTY_FILE}
        else
            ${SED_COMMAND} "s|LDAP_USER_NAME_ATTRIBUTE=\"\"|LDAP_USER_NAME_ATTRIBUTE=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_USER_DISPLAY_NAME_ATTR=\"\"|LDAP_USER_DISPLAY_NAME_ATTR=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_NAME_ATTRIBUTE=\"\"|LDAP_GROUP_NAME_ATTRIBUTE=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_DISPLAY_NAME_ATTR=\"\"|LDAP_GROUP_DISPLAY_NAME_ATTR=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"\"|LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LDAP_GROUP_MEMBER_ID_MAP=\"\"|LDAP_GROUP_MEMBER_ID_MAP=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LC_USER_FILTER=\"\"|LC_USER_FILTER=\"(\&(objectClass=person)(cn=%v))\"|g" ${LDAP_PROPERTY_FILE}
            ${SED_COMMAND} "s|LC_GROUP_FILTER=\"\"|LC_GROUP_FILTER=\"(\&(objectClass=group)(cn=%v))\"|g" ${LDAP_PROPERTY_FILE}
        fi
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
        echo "## For BAI stand-alone, if you select LDAP, then provide one ldap user here for onborading ZEN." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI_STANDALONE.LDAP_USER_NAME_ONBORADING_ZEN=\"$LDAP_USER_NAME\"" >> ${USER_PROFILE_PROPERTY_FILE}
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

        echo "## The password of the database user." >> ${USER_PROFILE_PROPERTY_FILE}
        echo "BAI.BTS_EXTERNAL_POSTGRES_DATABASE_USER_PASSWORD=\"<Optional>\"" >> ${USER_PROFILE_PROPERTY_FILE}
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
    if [[ "${SELECTED_LDAP,,}" == "yes" ]]; then
        ${SED_COMMAND} "s|LDAP_BIND_DN_PASSWORD=\"\"|LDAP_BIND_DN_PASSWORD=\"{Base64}<Required>\"|g" ${LDAP_PROPERTY_FILE}
        ${SED_COMMAND} "s|=\"\"|=\"<Required>\"|g" ${LDAP_PROPERTY_FILE}
    fi

    INFO "Created all property files for BAI stand-alone"
    
    # Show some tips for property file
    tips
    echo -e  "Enter the <Required> values in the property files under $PROPERTY_FILE_FOLDER"
    msgRed   "The key name in the property file is created by the bai-prerequisites.sh and is NOT EDITABLE."
    msgRed   "The value in the property file must be within double quotes."
    msgRed   "The value for User/Password in [bai_user_profile.property] file should NOT include special characters: single quotation \"'\""
    
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        msgRed   "The value in [bai_LDAP.property] [bai_user_profile.property] file should NOT include special character '\"'"
        echo -e  "\x1b[32m* [bai_LDAP.property]:\x1B[0m"
        echo -e  "  - Properties for the LDAP server that is used by the BAI stand-alone deployment, such as LDAP_SERVER/LDAP_PORT/LDAP_BASE_DN/LDAP_BIND_DN/LDAP_BIND_DN_PASSWORD.\n"
    fi

    echo -e  "\x1b[32m* [bai_user_profile.property]:\x1B[0m"
    echo -e  "  - Properties for the global value used by the BAI stand-alone deployment, such as \"sc_deployment_license\".\n"
    echo -e  "  - Properties for the value used by each component of BAI stand-alone, such as \"sc_deployment_profile_size\"\n"
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
        printf "\x1B[1mplease enter the file storage classname for medium storage(RWX): \x1B[0m"
        read -rp "" sc_medium_file_storage_classname
        if [ -z "$sc_medium_file_storage_classname" ]; then
        echo -e "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done

    while [[ $sc_fast_file_storage_classname == "" ]] # While get fast storage clase name
    do
        printf "\x1B[1mplease enter the file storage classname for fast storage(RWX): \x1B[0m"
        read -rp "" sc_fast_file_storage_classname
        if [ -z "$sc_fast_file_storage_classname" ]; then
        echo -e "\x1B[1;31mEnter a valid file storage classname(RWX)\x1B[0m"
        fi
    done

    while [[ $block_storage_class_name == "" ]] # While get block storage clase name
    do
        printf "\x1B[1mplease enter the block storage classname for Zen(RWO): \x1B[0m"
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
        printf "\x1B[1mDo you want to use an external Postgres DB \x1B[0m${RED_TEXT}[YOU NEED TO CREATE THIS POSTGRESQL DB BY YOURSELF FIRST BEFORE YOU APPLY THE BAI CUSTOM RESOURCE]${RESET_TEXT} \x1B[1mas IM metastore DB for this BAI deployment?\x1B[0m ${YELLOW_TEXT}(Notes: IM service can use an external Postgres DB to store IM data. If you select \"Yes\", IM service uses an external Postgres DB as IM metastore DB. If you select \"No\", IM service uses an embedded cloud native postgresql DB as IM metastore DB.)${RESET_TEXT} (Yes/No, default: No):  "
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
        printf "\x1B[1mDo you want to use an external Postgres DB \x1B[0m${RED_TEXT}[YOU NEED TO CREATE THIS POSTGRESQL DB BY YOURSELF FIRST BEFORE YOU APPLY THE BAI CUSTOM RESOURCE]${RESET_TEXT}\x1B[1m as BTS metastore DB for this BAI deployment?\x1B[0m ${YELLOW_TEXT}(Notes: BTS service can use an external Postgres DB to store meta data. If you select \"Yes\", BTS service uses an external Postgres DB as BTS metastore DB. If you select \"No\", BTS service uses an embedded cloud native postgresql DB as BTS metastore DB )${RESET_TEXT} (Yes/No, default: No): "
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
        printf "\x1B[1mDo you want to use an external Postgres DB \x1B[0m${RED_TEXT}[YOU NEED TO CREATE THIS POSTGRESQL DB BY YOURSELF FIRST BEFORE APPLY BAI CUSTOM RESOURCE]${RESET_TEXT}\x1B[1m as BTS metastore DB for this BAI deployment?\x1B[0m ${YELLOW_TEXT}(Notes: BTS service can use an external Postgres DB to store meta data. If select \"Yes\", BTS service uses an external Postgres DB as BTS metastore DB. If select \"No\", BTS service uses an embedded cloud native postgresql DB as BTS metastore DB )${RESET_TEXT} (Yes/No, default: No): "
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
            isProjExists=`kubectl get project $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1

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
    all_fips_enabled_flag=$(kubectl get configmap bai-fips-status --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath={.data.all-fips-enabled})
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
        options=("Microsoft Active Directory" "IBM Tivoli Directory Server / Security Directory Server" "Custom")
        PS3='Enter a valid option [1 to 3]: '
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
                "Custom"*)
                    LDAP_TYPE="Custom"
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

    echo -e  "${YELLOW_TEXT}For BAI stand-alone, if you select LDAP, then provide one ldap user here for onborading ZEN.${RESET_TEXT}"    
    while [[ $LDAP_USER_NAME == "" ]] # While get medium storage clase name
    do
        printf "\x1B[1mplease enter one LDAP user for BAI stand-alone: \x1B[0m"
        read -rp "" LDAP_USER_NAME
        if [ -z "$LDAP_USER_NAME" ]; then
        echo -e "\x1B[1;31mEnter a valid LDAP user\x1B[0m"
        fi
    done
}

function select_iam_default_admin(){
    printf "\n"
    while true; do
        echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1;31mIf you are unable to use [cpadmin] as the default IAM admin user due to it being already used in your LDAP Directory, you need to change the Cloud Pak administrator username. See: \" https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.9?topic=configurations-changing-cluster-administrator-access-credentials#name\"\x1B[0m"
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
        read -rsn1 -p"Press any key to continue ...";echo        
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
        echo "kubectl apply -f \"$item\"" >> ${CREATE_SECRET_SCRIPT_FILE_TMP}
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
                secret_exists=`kubectl get secret $secret_name_tmp --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ "$secret_exists" -ne 2 ] ; then
                    error "Secret \"$secret_name_tmp\" not found in Kubernetes cluster! please create it before deploying BAI Standalone"
                    SECRET_CREATE_PASSED="false"
                else
                    success "Secret \"$secret_name_tmp\" found in Kubernetes cluster, PASSED!"              
                fi
            else
                secret_exists=`kubectl get configmap $secret_name_tmp --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ "$secret_exists" -ne 2 ] ; then
                    error "ConfigMap \"$secret_name_tmp\" not found in Kubernetes cluster! please create it before deploying BAI Standalone"
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
            secret_exists=`kubectl get secret $secret_name_tmp --ignore-not-found | wc -l`  >/dev/null 2>&1
            if [ "$secret_exists" -ne 2 ] ; then
                error "Secret \"$secret_name_tmp\" not found in Kubernetes cluster! please create it before deploying BAI Standalone"
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
        kubectl delete pvc -l bai=test-only >/dev/null 2>&1
        exit 0
    fi
    # Validate Secret for BAI stand-alone
    validate_secret_in_cluster

    # Validate LDAP connection for BAI stand-alone
    if [[ ! ("${#flink_job_cr_arr[@]}" -eq "1" && "${flink_job_cr_arr[@]}" =~ "workflow-process-service" && $LDAP_WFPS_AUTHORING == "No") ]]; then
        INFO "Checking the LDAP connection required by BAI stand-alone" 
        tmp_servername="$(prop_ldap_property_file LDAP_SERVER)"
        tmp_serverport="$(prop_ldap_property_file LDAP_PORT)"
        tmp_basdn="$(prop_ldap_property_file LDAP_BASE_DN)"
        tmp_ldapssl="$(prop_ldap_property_file LDAP_SSL_ENABLED)"
        tmp_user=`kubectl get secret -l name=ldap-bind-secret -o yaml | ${YQ_CMD} r - items.[0].data.ldapUsername | base64 --decode`
        tmp_userpwd=`kubectl get secret -l name=ldap-bind-secret -o yaml | ${YQ_CMD} r - items.[0].data.ldapPassword | base64 --decode`

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

        output=$(java -Dsemeru.fips=$fips_flag -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        retVal_verify_db_tmp=$?
        connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
        if [[ ! -z $connection_time ]]; then
            echo "Latency: $connection_time ms"
            # Check if elapsed time is greater than 10 ms using awk
            if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
            echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
            elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
            echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
            elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
            echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
            fi
        fi

        [[ retVal_verify_db_tmp -ne 0 ]] && \
        warning "Execute: java -Dsemeru.fips=$fips_flag -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check configuration again."
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

        output=$(java -Dsemeru.fips=$fips_flag -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        retVal_verify_db_tmp=$?
        connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
        if [[ ! -z $connection_time ]]; then
            echo "Latency: $connection_time ms"
            # Check if elapsed time is greater than 10 ms using awk
            if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
            echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
            elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
            echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
            elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
            echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
            fi
        fi

        [[ retVal_verify_db_tmp -ne 0 ]] && \
        warning "Execute: java -Dsemeru.fips=$fips_flag -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check configuration again."
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

        output=$(java -Dsemeru.fips=$fips_flag -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        retVal_verify_db_tmp=$?
        connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
        if [[ ! -z $connection_time ]]; then
            echo "Latency: $connection_time ms"
            # Check if elapsed time is greater than 10 ms using awk
            if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
            echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
            elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
            echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
            elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
            echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
            fi
        fi

        [[ retVal_verify_db_tmp -ne 0 ]] && \
        warning "Execute: java -Dsemeru.fips=$fips_flag -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check configuration again."
        [[ retVal_verify_db_tmp -eq 0 ]] && \
        success "The DB connection check for \"$dbname\" on database server \"$dbserver\" PASSED!"
    fi

    info "If all prerequisites check have PASSED, you can run bai-deployment.sh script to deploy BAI stand-alone. Otherwise, please check configuration again."
    info "After BAI stand-alone is deployed, please refer to documentation for post-deployment steps."
}
################################################
#### Begin - Main step for install operator ####
################################################
save_log "bai-script-logs" "bai-prerequisites-log"
trap cleanup_log EXIT
if [[ $1 == "" ]]
then
    show_help
    exit -1
else
    while getopts "h?i:p:n:t:a:m:" opt; do
        case "$opt" in
        h|\?)
            show_help
            exit 0
            ;;
        m)  RUNTIME_MODE=$OPTARG
            if [[ $RUNTIME_MODE == "property" || $RUNTIME_MODE == "generate" || $RUNTIME_MODE == "validate" ]]; then
                echo
            else
                msg "Use a valid value: -m [property] or [generate] or [validate]"
                exit -1
            fi
            ;;
        :)  echo "Invalid option: -$OPTARG requires an argument"
            show_help
            exit -1
            ;;
        esac
    done
fi

clear

if [[ $RUNTIME_MODE == "property" ]]; then
    prompt_license
    input_information
    create_property_file
    clean_up_temp_file
fi
if [[ $RUNTIME_MODE == "generate" ]]; then
    # reload db type and OS number
    load_property_before_generate
    if [[ $SELECTED_LDAP == "Yes" ]]; then
        create_prerequisites
        clean_up_temp_file
        generate_create_secret_script
    else
        warning "None LDAP selected, so without secret YAML template to be created"
        sleep 2
    fi
fi

if [[ $RUNTIME_MODE == "validate" ]]; then
    echo  "*****************************************************"
    echo  "Validating the prerequisites before you install BAI stand-alone"
    echo  "*****************************************************"
    validate_utility_tool_for_validation
    load_property_before_generate
    validate_prerequisites
fi
################################################
#### End - Main step for install operator ####
################################################
