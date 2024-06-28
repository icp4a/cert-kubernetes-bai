#!/bin/bash
# set -x
###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Import common utilities and environment variables
source ${CUR_DIR}/helper/common.sh

# Import variables for property file
source ${CUR_DIR}/helper/bai-property.sh

DOCKER_RES_SECRET_NAME="ibm-entitlement-key"
DOCKER_REG_USER=""
SCRIPT_MODE=$1

if [[ "$SCRIPT_MODE" == "baw-dev" || "$SCRIPT_MODE" == "dev" || "$SCRIPT_MODE" == "review" ]] # During dev, OLM uses stage image repo
then
    DOCKER_REG_SERVER="cp.stg.icr.io"
    if [[ -z $2 ]]; then
        IMAGE_TAG_DEV="${BAI_RELEASE_BASE}"
    else
        IMAGE_TAG_DEV=$2
    fi
    IMAGE_TAG_FINAL="${BAI_RELEASE_BASE}"
else
    DOCKER_REG_SERVER="cp.icr.io"
fi
DOCKER_REG_KEY=""
REGISTRY_IN_FILE="cp.icr.io"
# OPERATOR_IMAGE=${DOCKER_REG_SERVER}/cp/cp4a/icp4a-operator:21.0.2

old_db2="docker.io\/ibmcom"
old_db2_alpine="docker.io\/alpine"
old_ldap="docker.io\/osixia"
old_db2_etcd="quay.io\/coreos"
old_busybox="docker.io\/library"

TEMP_FOLDER=${CUR_DIR}/.tmp
BAK_FOLDER=${CUR_DIR}/.bak
FINAL_CR_FOLDER=${CUR_DIR}/generated-cr

DEPLOY_TYPE_IN_FILE_NAME="" # Default value is empty
OPERATOR_FILE=${PARENT_DIR}/descriptors/operator.yaml
OPERATOR_FILE_TMP=$TEMP_FOLDER/.operator_tmp.yaml
OPERATOR_FILE_BAK=$BAK_FOLDER/.operator.yaml

# PREREQUISITES_FOLDER=${CUR_DIR}/cp4ba-prerequisites
# PROPERTY_FILE_FOLDER=${PREREQUISITES_FOLDER}/propertyfile
# TEMPORARY_PROPERTY_FILE=${TEMP_FOLDER}/.TEMPORARY.property
# LDAP_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/cp4ba_LDAP.property
# EXTERNAL_LDAP_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/cp4ba_External_LDAP.property

# DB_NAME_USER_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/cp4ba_db_name_user.property
# DB_SERVER_INFO_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/cp4ba_db_server.property


# OPERATOR_PVC_FILE=${PARENT_DIR}/descriptors/operator-shared-pvc.yaml
# OPERATOR_PVC_FILE_TMP1=$TEMP_FOLDER/.operator-shared-pvc_tmp1.yaml
# OPERATOR_PVC_FILE_TMP=$TEMP_FOLDER/.operator-shared-pvc_tmp.yaml
# OPERATOR_PVC_FILE_BAK=$BAK_FOLDER/.operator-shared-pvc.yaml


BAI_PATTERN_FILE_TMP=$TEMP_FOLDER/.ibm_bai_cr_final_tmp.yaml
# BAI_PATTERN_FILE_BAK=$FINAL_CR_FOLDER/ibm_bai_cr_final.yaml
BAI_PATTERN_FILE_FINAL=$FINAL_CR_FOLDER/ibm_bai_cr_final.yaml
FNCM_SEPARATE_PATTERN_FILE_BAK=$FINAL_CR_FOLDER/ibm_content_cr_final.yaml
BAI_EXISTING_BAK=$TEMP_FOLDER/.ibm_bai_cr_final_existing_bak.yaml
BAI_EXISTING_TMP=$TEMP_FOLDER/.ibm_bai_cr_final_existing_tmp.yaml

JDBC_DRIVER_DIR=${CUR_DIR}/jdbc
SAP_LIB_DIR=${CUR_DIR}/saplibs
ACA_MODEL_FILES_DIR=../ACA/configuration-ha/
PLATFORM_SELECTED=""
PATTERN_SELECTED=""
COMPONENTS_SELECTED=""
OPT_COMPONENTS_CR_SELECTED=""
OPT_COMPONENTS_SELECTED=()
LDAP_TYPE=""
TARGET_PROJECT_NAME=""
CP4BA_JDBC_URL=""

FOUNDATION_CR_SELECTED=""
optional_component_arr=()
optional_component_cr_arr=()
foundation_component_arr=()

function prompt_license(){
    clear

    echo -e "\x1B[1;31mIMPORTANT: Review the IBM Business Automation Insights stand-alone license information here: \n\x1B[0m"
    echo -e "\x1B[1;31mhttps://www14.software.ibm.com/cgi-bin/weblap/lap.pl?li_formnum=L-PSZC-SHQFWS\n\x1B[0m"
    INSTALL_BAW_ONLY="No"


    read -rsn1 -p"Press any key to continue";echo

    printf "\n"
    while true; do
        printf "\x1B[1mDo you accept the IBM Business Automation Insights stand-alone license (Yes/No, default: No): \x1B[0m"

        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            echo -e "Starting to Install the IBM Business Automation Insights stand-alone Operator...\n"
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

function set_script_mode(){
    if [[ -f $TEMPORARY_PROPERTY_FILE && -f $LDAP_PROPERTY_FILE ]]; then
        DEPLOYMENT_WITH_PROPERTY="Yes"
    else
        DEPLOYMENT_WITH_PROPERTY="No"
    fi
}

function validate_kube_oc_cli(){
    if  [[ $PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "ROKS" ]]; then
        which oc &>/dev/null
        [[ $? -ne 0 ]] && \
        echo -e  "\x1B[1;31mUnable to locate an OpenShift CLI. You must install it to run this script.\x1B[0m" && \
        exit 1
    fi
    if  [[ $PLATFORM_SELECTED == "other" ]]; then
        which kubectl &>/dev/null
        [[ $? -ne 0 ]] && \
        echo -e  "\x1B[1;31mUnable to locate Kubernetes CLI, You must install it to run this script.\x1B[0m" && \
        exit 1
    fi
}

function prop_tmp_property_file() {
    grep "\b${1}\b" ${TEMPORARY_PROPERTY_FILE}|cut -d'=' -f2
}

function load_property_before_generate(){
    if [[ ! -f $TEMPORARY_PROPERTY_FILE || ! -f $USER_PROFILE_PROPERTY_FILE ]]; then
        fail "Not Found existing property file under \"$PROPERTY_FILE_FOLDER\", Please run \"cp4a-prerequisites.sh\" to complate prerequisites"
        exit 1
    fi

    # load pattern into pattern_cr_arr
    pattern_list="$(prop_tmp_property_file PATTERN_LIST)"
    pattern_name_list="$(prop_tmp_property_file PATTERN_NAME_LIST)"
    optional_component_list="$(prop_tmp_property_file OPTION_COMPONENT_LIST)"
    optional_component_name_list="$(prop_tmp_property_file OPTION_COMPONENT_NAME_LIST)"
    foundation_list="$(prop_tmp_property_file FOUNDATION_LIST)"

    OIFS=$IFS
    IFS=',' read -ra pattern_cr_arr <<< "$pattern_list"
    IFS=',' read -ra PATTERNS_CR_SELECTED <<< "$pattern_list"
    
    IFS=',' read -ra pattern_arr <<< "$pattern_name_list"
    IFS=',' read -ra optional_component_cr_arr <<< "$optional_component_list"
    IFS=',' read -ra optional_component_arr <<< "$optional_component_name_list"
    IFS=',' read -ra foundation_component_arr <<< "$foundation_list"    
    IFS=$OIFS

    # load db_name_full_array and db_user_full_array
    db_name_list="$(prop_tmp_property_file DB_NAME_LIST)"
    db_user_list="$(prop_tmp_property_file DB_USER_LIST)"
    db_user_pwd_list="$(prop_tmp_property_file DB_USER_PWD_LIST)"

    OIFS=$IFS
    IFS=',' read -ra db_name_full_array <<< "$db_name_list"
    IFS=',' read -ra db_user_full_array <<< "$db_user_list"
    IFS=',' read -ra db_user_pwd_full_array <<< "$db_user_pwd_list"
    IFS=$OIFS

    # load db ldap type
    LDAP_TYPE="$(prop_tmp_property_file LDAP_TYPE)"
    DB_TYPE="$(prop_tmp_property_file DB_TYPE)"

    # load CONTENT_OS_NUMBER
    content_os_number=$(prop_tmp_property_file CONTENT_OS_NUMBER)

    # load DB_SERVER_NUMBER
    db_server_number=$(prop_tmp_property_file DB_SERVER_NUMBER)

    # # load external ldap flag
    # SET_EXT_LDAP=$(prop_tmp_property_file EXTERNAL_LDAP_ENABLED)

    # load limited CPE storage support flag
    CPE_FULL_STORAGE=$(prop_tmp_property_file CPE_FULL_STORAGE_ENABLED)

    # load GPU enabled worker nodes flag
    ENABLE_GPU_ARIA=$(prop_tmp_property_file ENABLE_GPU_ARIA_ENABLED)
    nodelabel_key=$(prop_tmp_property_file NODE_LABEL_KEY)
    nodelabel_value=$(prop_tmp_property_file NODE_LABEL_VALUE)

    # load LDAP/DB required flag for wfps
    LDAP_WFPS_AUTHORING=$(prop_tmp_property_file LDAP_WFPS_AUTHORING_FLAG)
    EXTERNAL_DB_WFPS_AUTHORING=$(prop_tmp_property_file EXTERNAL_DB_WFPS_AUTHORING_FLAG)

    # load fips enabled flag
    FIPS_ENABLED="false"

    # load profile size  flag
    PROFILE_TYPE=$(prop_tmp_property_file PROFILE_SIZE_FLAG)   
}

function validate_docker_podman_cli(){
    if [[ $OCP_VERSION == "3.11" || "$machine" == "Mac" ]];then
        which podman &>/dev/null
        if [[ $? -ne 0 ]]; then
            PODMAN_FOUND="No"

            which docker &>/dev/null
            [[ $? -ne 0 ]] && \
                DOCKER_FOUND="No"
            if [[ $DOCKER_FOUND == "No" && $PODMAN_FOUND == "No" ]]; then
                echo -e "\x1B[1;31mUnable to locate docker and podman, please install either of them first.\x1B[0m" && \
                exit 1
            fi
        fi
    elif [[ $OCP_VERSION == "4.4OrLater" ]]
    then
        which podman &>/dev/null
        [[ $? -ne 0 ]] && \
            echo -e "\x1B[1;31mUnable to locate podman, please install it first.\x1B[0m" && \
            exit 1
    fi
}

function select_project() {
    while [[ $TARGET_PROJECT_NAME == "" ]]; 
    do
        # if [ -z "$CP4BA_AUTO_NAMESPACE" ]; then
        #     echo
        #     echo -e "\x1B[1mWhere do you want to deploy Cloud Pak for Business Automation?\x1B[0m"
        #     read -p "Enter the name for an existing project (namespace): " $TARGET_PROJECT_NAME
        # else
        #     if [[ "$CP4BA_AUTO_NAMESPACE" == openshift* ]]; then
        #         echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
        #         exit 1
        #     elif [[ "$CP4BA_AUTO_NAMESPACE" == kube* ]]; then
        #         echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
        #         exit 1
        #     fi
        #     TARGET_PROJECT_NAME=$CP4BA_AUTO_NAMESPACE
        # fi
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

function containsElement(){
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

function select_platform(){
    printf "\n"
    echo -e "\x1B[1mSelect the cloud platform to deploy: \x1B[0m"
    COLUMNS=12
    if [ -z "$existing_platform_type" ]; then
        if [[ "${SCRIPT_MODE}" == "OLM" ]]; then
            options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
            PS3='Enter a valid option [1 to 2]: '
        else
            # options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "Other ( Certified Kubernetes Cloud Platform / CNCF)")
            # PS3='Enter a valid option [1 to 3]: '
            options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
            PS3='Enter a valid option [1 to 2]: '
        fi

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
        echo -e "\x1B[1;31mExisting platform type found in CR: \"$existing_platform_type\"\x1B[0m"
        # echo -e "\x1B[1;31mDo not need to select again.\n\x1B[0m"
        read -rsn1 -p"Press any key to continue ...";echo
    fi

    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        CLI_CMD=oc
    elif [[ "$PLATFORM_SELECTED" == "other" ]]
    then
        CLI_CMD=kubectl
    fi

    validate_kube_oc_cli
}

function check_ocp_version(){
    if [[ ${PLATFORM_SELECTED} == "OCP" || ${PLATFORM_SELECTED} == "ROKS" ]];then
        temp_ver=`${CLI_CMD} version | grep v[1-9]\.[1-9][0-9] | tail -n1`
        if [[ $temp_ver == *"Kubernetes Version"* ]]; then
            currentver="${temp_ver:20:7}"
        else
            currentver="${temp_ver:11:7}"
        fi
        requiredver="v1.17.1"
        if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
            OCP_VERSION="4.4OrLater"
        else
            # OCP_VERSION="3.11"
            OCP_VERSION="4.4OrLater"
            echo -e "\x1B[1;31mIMPORTANT: The apiextensions.k8s.io/v1beta API has been deprecated from k8s 1.16+, OCp4.3 is using k8s 1.16.x. recommend you to upgrade your OCp to 4.4 or later\n\x1B[0m"
            read -rsn1 -p"Press any key to continue";echo
            # exit 0
        fi
    fi
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
        echo -e "\x1B[1mWhich component you want to enable the Flink job for: \x1B[0m"
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

function get_local_registry_password(){
    printf "\n"
    printf "\x1B[1mEnter the password for your docker registry: \x1B[0m"
    local_registry_password=""
    while [[ $local_registry_password == "" ]];
    do
       read -rsp "" local_registry_password
       if [ -z "$local_registry_password" ]; then
       echo -e "\x1B[1;31mEnter a valid password\x1B[0m"
       fi
    done
    export LOCAL_REGISTRY_PWD=${local_registry_password}
    printf "\n"
}

function get_local_registry_password_double(){
    pwdconfirmed=1
    pwd=""
    pwd2=""
        while [ $pwdconfirmed -ne 0 ] # While pwd is not yet received and confirmed (i.e. entered teh same time twice)
        do
                printf "\n"
                while [[ $pwd == '' ]] # While pwd is empty...
                do
                        printf "\x1B[1mEnter the password for your docker registry: \x1B[0m"
                        read -rsp " " pwd
                done

                printf "\n"
                while [[ $pwd2 == '' ]]  # While pwd is empty...
                do
                        printf "\x1B[1mEnter the password again: \x1B[0m"
                        read -rsp " " pwd2
                done

            if [ "$pwd" == "$pwd2" ]; then
                   pwdconfirmed=0
                else
                   printf "\n"
                   echo -e "\x1B[1;31mThe passwords do not match. Try again.\x1B[0m"
                   unset pwd
                   unset pwd2
                fi
        done

        printf "\n"

        export LOCAL_REGISTRY_PWD="${pwd}"
}



function get_entitlement_registry(){

    docker_image_exists() {
    local image_full_name="$1"; shift
    local wait_time="${1:-5}"
    local search_term='Pulling|Copying|is up to date|already exists|not found|unable to pull image|no pull access'
    if [[ $OCP_VERSION == "3.11" ]];then
        local result=$((timeout --preserve-status "$wait_time" docker 2>&1 pull "$image_full_name" &) | grep -v 'Pulling repository' | egrep -o "$search_term")

    elif [[ $OCP_VERSION == "4.4OrLater" ]]
    then
        local result=$((timeout --preserve-status "$wait_time" podman 2>&1 pull "$image_full_name" &) | grep -v 'Pulling repository' | egrep -o "$search_term")

    fi
    test "$result" || { echo "Timed out too soon. Try using a wait_time greater than $wait_time..."; return 1 ;}
    echo $result | grep -vq 'not found'
    }

    # For Entitlement Registry key
    entitlement_key=""
    printf "\n"
    printf "\n"
    printf "\x1B[1;31mFollow the instructions on how to get your Entitlement Key: \n\x1B[0m"
    printf "\x1B[1;31m https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$BAI_RELEASE_BASE?topic=deployment-getting-access-images-from-public-entitled-registry\n\x1B[0m"
    printf "\n"
    while true; do
        printf "\x1B[1mDo you have a Cloud Pak for Business Automation Entitlement Registry key (Yes/No, default: No): \x1B[0m"
        read -rp "" ans

        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            use_entitlement="yes"
            if [[ "$SCRIPT_MODE" == "dev" || "$SCRIPT_MODE" == "review" || "$SCRIPT_MODE" == "OLM" ]]
            then
                DOCKER_REG_SERVER="cp.stg.icr.io"
            else
                DOCKER_REG_SERVER="cp.icr.io"
            fi
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            use_entitlement="no"
            DOCKER_REG_KEY="None"
            if [[ "$PLATFORM_SELECTED" == "ROKS" || "$PLATFORM_SELECTED" == "OCP" ]]; then
                printf "\n"
                printf "\x1B[1;31m\"${PLATFORM_SELECTED}\" only supports the Entitlement Registry, exiting...\n\x1B[0m"
                exit 1
            else
                break
            fi
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

function create_secret_entitlement_registry(){
    printf "\x1B[1mCreating docker-registry secret for Entitlement Registry key...\n\x1B[0m"
# Create docker-registry secret for Entitlement Registry Key
    ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME" >/dev/null 2>&1
    CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$DOCKER_REG_SERVER --docker-username=$DOCKER_REG_USER --docker-password=$DOCKER_REG_KEY --docker-email=ecmtest@ibm.com"
    if $CREATE_SECRET_CMD ; then
        echo -e "\x1B[1mDone\x1B[0m"
    else
        echo -e "\x1B[1mFailed\x1B[0m"
    fi
}

function get_local_registry_server(){
    # For internal/external Registry Server
    printf "\n"
    if [[ "${REGISTRY_TYPE}" == "internal" && ("${OCP_VERSION}" == "4.4OrLater") ]];then
        #This is required for docker/podman login validation.
        printf "\x1B[1mEnter the public image registry or route (e.g., default-route-openshift-image-registry.apps.<hostname>). \n\x1B[0m"
        printf "\x1B[1mThis is required for docker/podman login validation: \x1B[0m"
        local_public_registry_server=""
        while [[ $local_public_registry_server == "" ]]
        do
            read -rp "" local_public_registry_server
            if [ -z "$local_public_registry_server" ]; then
            echo -e "\x1B[1;31mEnter a valid service name or the URL for the docker registry.\x1B[0m"
            fi
        done
    fi

    if [[ "${OCP_VERSION}" == "3.11" && "${REGISTRY_TYPE}" == "internal" ]];then
        printf "\x1B[1mEnter the OCP docker registry service name, for example: docker-registry.default.svc:5000/<project-name>: \x1B[0m"
    elif [[ "${REGISTRY_TYPE}" == "internal" && "${OCP_VERSION}" == "4.4OrLater" ]]
    then
        printf "\n"
        printf "\x1B[1mEnter the local image registry (e.g., image-registry.openshift-image-registry.svc:5000/<project>)\n\x1B[0m"
        printf "\x1B[1mThis is required to pull container images and Kubernetes secret creation: \x1B[0m"
        builtin_dockercfg_secrect_name=$(${CLI_CMD} get secret | grep default-dockercfg | awk '{print $1}')
        if [ -z "$builtin_dockercfg_secrect_name" ]; then
            DOCKER_RES_SECRET_NAME="ibm-entitlement-key"
        else
            DOCKER_RES_SECRET_NAME=$builtin_dockercfg_secrect_name
        fi
    elif [[ "${REGISTRY_TYPE}" == "external" || $PLATFORM_SELECTED == "other" ]]
    then
        printf "\x1B[1mEnter the URL to the docker registry, for example: abc.xyz.com: \x1B[0m"
    fi
    local_registry_server=""
    while [[ $local_registry_server == "" ]]
    do
        read -rp "" local_registry_server
        if [ -z "$local_registry_server" ]; then
        echo -e "\x1B[1;31mEnter a valid service name or the URL for the docker registry.\x1B[0m"
        fi
    done
    LOCAL_REGISTRY_SERVER=${local_registry_server}
    # convert docker-registry.default.svc:5000/project-name
    # to docker-registry.default.svc:5000\/project-name
    OIFS=$IFS
    IFS='/' read -r -a docker_reg_url_array <<< "$local_registry_server"
    delim=""
    joined=""
    for item in "${docker_reg_url_array[@]}"; do
            joined="$joined$delim$item"
            delim="\/"
    done
    IFS=$OIFS
    CONVERT_LOCAL_REGISTRY_SERVER=${joined}
}

function get_local_registry_user(){
    # For Local Registry User
    printf "\n"
    printf "\x1B[1mEnter the user name for your docker registry: \x1B[0m"
    local_registry_user=""
    while [[ $local_registry_user == "" ]]
    do
       read -rp "" local_registry_user
       if [ -z "$local_registry_user" ]; then
       echo -e "\x1B[1;31mEnter a valid user name.\x1B[0m"
       fi
    done
    export LOCAL_REGISTRY_USER=${local_registry_user}
}

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
    # fi
    # STORAGE_CLASS_NAME=${storage_class_name}
    # SLOW_STORAGE_CLASS_NAME=${sc_slow_file_storage_classname}
    MEDIUM_STORAGE_CLASS_NAME=${sc_medium_file_storage_classname}
    FAST_STORAGE_CLASS_NAME=${sc_fast_file_storage_classname}
    BLOCK_STORAGE_CLASS_NAME=${block_storage_class_name}
}

function create_secret_local_registry(){
    echo -e "\x1B[1mCreating the secret based on the local docker registry information...\x1B[0m"
    # Create docker-registry secret for local Registry Key
    # echo -e "Create docker-registry secret for Local Registry...\n"
    if [[ $LOCAL_REGISTRY_SERVER == docker-registry* || $LOCAL_REGISTRY_SERVER == image-registry.openshift-image-registry* ]] ;
    then
        builtin_dockercfg_secrect_name=$(${CLI_CMD} get secret | grep default-dockercfg | awk '{print $1}')
        DOCKER_RES_SECRET_NAME=$builtin_dockercfg_secrect_name
        # CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$LOCAL_REGISTRY_SERVER --docker-username=$LOCAL_REGISTRY_USER --docker-password=$(${CLI_CMD} whoami -t) --docker-email=ecmtest@ibm.com"
    else
        ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME" >/dev/null 2>&1
        CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$LOCAL_REGISTRY_SERVER --docker-username=$LOCAL_REGISTRY_USER --docker-password=$LOCAL_REGISTRY_PWD --docker-email=ecmtest@ibm.com"
        if $CREATE_SECRET_CMD ; then
            echo -e "\x1B[1mDone\x1B[0m"
        else
            echo -e "\x1B[1;31mFailed\x1B[0m"
        fi
    fi
}

function verify_local_registry_password(){
    # require to preload image for CP4A image and ldap/db2 image for demo
    printf "\n"
    while true; do
        printf "\x1B[1mHave you pushed the images to the local registry using 'loadimages.sh' (CP4A images) (Yes/No)? \x1B[0m"
        # printf "\x1B[1mand 'loadPrereqImages.sh' (Db2 and OpenLDAP for demo) scripts (Yes/No)? \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            PRE_LOADED_IMAGE="Yes"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")
            echo -e "\x1B[1;31mPlease pull the images to the local images to proceed.\n\x1B[0m"
            exit 1
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done

    # Select which type of image registry to use.
    if [[ "${PLATFORM_SELECTED}" == "OCP" ]]; then
        printf "\n"
        echo -e "\x1B[1mSelect the type of image registry to use: \x1B[0m"
        COLUMNS=12
        options=("Other ( External image registry: abc.xyz.com )")

        PS3='Enter a valid option [1 to 1]: '
        select opt in "${options[@]}"
        do
            case $opt in
                "Openshift Container Platform (OCP) - Internal image registry")
                    REGISTRY_TYPE="internal"
                    break
                    ;;
                "Other ( External image registry: abc.xyz.com )")
                    REGISTRY_TYPE="external"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    else
        REGISTRY_TYPE="external"
    fi
    get_local_registry_server
}
function select_installation_type(){
    COLUMNS=12
    echo -e "\x1B[1mIs this a new installation or an existing installation?\x1B[0m"
    options=("New" "Existing")
    PS3='Enter a valid option [1 to 2]: '
    select opt in "${options[@]}"
    do
        case $opt in
            "New")
                INSTALLATION_TYPE="new"
                break
                ;;
            "Existing")
                INSTALLATION_TYPE="existing"
                mkdir -p $TEMP_FOLDER >/dev/null 2>&1
                mkdir -p $BAK_FOLDER >/dev/null 2>&1
                mkdir -p $FINAL_CR_FOLDER >/dev/null 2>&1
                get_existing_pattern_name
                break
                ;;
            *) echo "invalid option $REPLY";;
        esac
    done
    if [[ "${INSTALLATION_TYPE}" == "new" ]]; then
        clean_up_temp_file
        rm -rf $BAK_FOLDER >/dev/null 2>&1
        rm -rf $FINAL_CR_FOLDER >/dev/null 2>&1

        mkdir -p $TEMP_FOLDER >/dev/null 2>&1
        mkdir -p $BAK_FOLDER >/dev/null 2>&1
        mkdir -p $FINAL_CR_FOLDER >/dev/null 2>&1
    fi
}

function select_iam_default_admin(){
    printf "\n"
    while true; do
        echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1;31mIf you are unable to use [cpadmin] as the default IAM admin user due to it having the same user name in your LDAP Directory, you need to change the Cloud Pak administrator username. See: \" https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=configurations-changing-cluster-administrator-access-credentials#name\"\x1B[0m"
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

function select_ocp_olm(){
    printf "\n"
    while true; do
        printf "\x1B[1mAre you using the OCP Catalog (OLM) to perform this install? (Yes/No, default: No) \x1B[0m"

        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            SCRIPT_MODE="OLM"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            break
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}


function select_deployment_type(){
    printf "\n"
    echo -e "\x1B[1mWhat type of deployment is being performed?\x1B[0m"
    COLUMNS=12
    options_var=("Production")
    for i in ${!options_var[@]}; do
        if [[ "${options_var[i]}" == "Production" ]]; then
            printf "%1d) %s \x1B[1m%s\x1B[0m\n" $((i+1)) "${options_var[i]}"  "(Selected)"
        else
            printf "%1d) %s\n" $((i+1)) "${options_var[i]}"
        fi
    done
    echo -e "${YELLOW_TEXT}BAI Stand-alone only supports production deployment${RESET_TEXT}"
    read -rsn1 -p"Press any key to continue ...";echo
}

function select_upgrade_mode(){
    printf "\n"
    COLUMNS=12
    echo -e "\x1B[1mWhich migration mode for the IBM Foundational Services you want to select? \x1B[0m"
    options=("Shared to Dedicated (Incoming)" "Shared to Shared")
    PS3='Enter a valid option [1 to 2]: '
    select opt in "${options[@]}"
    do
        case $opt in
            "Shared to Dedicated"*)
                UPGRADE_MODE="shared2dedicated"
                warning "Implementing upgrade from shared to dedicated"
                exit 1
                ;;
            "Shared to Shared")
                UPGRADE_MODE="shared2shared"
                break
                ;;
            *) echo "invalid option $REPLY";;
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

function select_ldap_type(){
    printf "\n"
    while true; do
        printf "\x1B[1mDo you want to configure one LDAP for this IBM Business Automation Insights stand-alone deployment? (Yes/No, default: Yes): \x1B[0m"
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
        echo -e "\x1B[1mWhat is the LDAP type that is used for this deployment? \x1B[0m"
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

function set_ldap_type_foundation(){
    if [[ $DEPLOYMENT_TYPE == "production" ]] ;
    then
        # ${COPY_CMD} -rf ${BAI_PATTERN_FILE_BAK} ${BAI_PATTERN_FILE_TMP}

        if [[ "$LDAP_TYPE" == "AD" ]]; then
            content_start="$(grep -n "ad:" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
        elif [[ $LDAP_TYPE == "TDS" ]]; then
            content_start="$(grep -n "tds:" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
        else
            content_start="$(grep -n "custom:" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
        fi
        content_stop="$(tail -n +$content_start < ${BAI_PATTERN_FILE_TMP} | grep -n "lc_group_filter:" | head -n1 | cut -d: -f1)"
        content_stop=$(( $content_stop + $content_start - 1))
        vi ${BAI_PATTERN_FILE_TMP} -c ':'"${content_start}"','"${content_stop}"'s/    # /    ' -c ':wq' >/dev/null 2>&1

        # ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_BAK}
    fi
}

function set_ldap_type_content_pattern(){
    if [[ $DEPLOYMENT_TYPE == "production" ]] ;
    then
        ${COPY_CMD} -rf ${BAI_PATTERN_FILE_BAK} ${BAI_PATTERN_FILE_TMP}

        if [[ "$LDAP_TYPE" == "AD" ]]; then
            content_start="$(grep -n "## The User script will uncomment" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
        else
            content_start="$(grep -n "## The User script will uncomment" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
        fi
        content_stop="$(tail -n +$content_start < ${BAI_PATTERN_FILE_TMP} | grep -n "lc_group_filter:" | head -n1 | cut -d: -f1)"
        content_stop=$(( $content_stop + $content_start + 2))
        vi ${BAI_PATTERN_FILE_TMP} -c ':'"${content_start}"','"${content_stop}"'d' -c ':wq' >/dev/null 2>&1

        ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_BAK}
    fi
}

function select_fips_enable(){
    select_project
    all_fips_enabled_flag=$(kubectl get configmap bai-fips-status --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath={.data.all-fips-enabled})
    if [ -z $all_fips_enabled_flag ]; then
        warning "Not found configmap \"bai-fips-status\" in project \"$TARGET_PROJECT_NAME\". setting shared_configuration.enable_fips as \"false\" by default in final custom resource file"
        sleep 3
        FIPS_ENABLED="false"
    elif [[ "$all_fips_enabled_flag" == "Yes" ]]; then
        printf "\n"
        while true; do
            printf "\x1B[1mYour OCP cluster has FIPS enabled, do you want to enable FIPS with this BAI stand-alone deployment？\x1B[0m (Yes/No, default: No): "
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                FIPS_ENABLED="true"
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

function clean_up_temp_file(){
    local files=()
    if [[ -d $TEMP_FOLDER ]]; then
        files=($(find $TEMP_FOLDER -name '*.yaml'))
        for item in ${files[*]}
        do
            rm -rf $item >/dev/null 2>&1
        done
        
        files=($(find $TEMP_FOLDER -name '*.swp'))
        for item in ${files[*]}
        do
            rm -rf $item >/dev/null 2>&1
        done
    fi
}

function input_information(){
    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" || $DEPLOYMENT_TYPE == "starter" ]]; then
        # select_installation_type
        INSTALLATION_TYPE="new"
    elif [[ $DEPLOYMENT_WITH_PROPERTY == "Yes" ]]; then
        INSTALLATION_TYPE="new"
    fi
    # clean_up_temp_file
    # rm -rf $BAK_FOLDER >/dev/null 2>&1
    # rm -rf $FINAL_CR_FOLDER >/dev/null 2>&1

    mkdir -p $TEMP_FOLDER >/dev/null 2>&1
    mkdir -p $BAK_FOLDER >/dev/null 2>&1
    mkdir -p $FINAL_CR_FOLDER >/dev/null 2>&1

    if [[ ${INSTALLATION_TYPE} == "existing" ]]; then
        # INSTALL_BAW_IAWS="No"
        prepare_pattern_file
        select_deployment_type
        if [[ $DEPLOYMENT_TYPE == "production" && (-z $PROFILE_TYPE) ]]; then
            select_profile_type
        fi
        select_platform
        if [[ ("$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS") && "$DEPLOYMENT_TYPE" == "production" ]]; then
            select_iam_default_admin
        fi
        check_ocp_version
        validate_docker_podman_cli
    elif [[ ${INSTALLATION_TYPE} == "new" ]]
    then
        # select_ocp_olm
        # select_deployment_type
        # BAI stand-alone only support Production
        DEPLOYMENT_TYPE="production"
        if [[ $DEPLOYMENT_WITH_PROPERTY == "Yes" && $DEPLOYMENT_TYPE == "production" ]]; then
            load_property_before_generate
            if [[ -f $USER_PROFILE_PROPERTY_FILE ]]; then
                PLATFORM_SELECTED=$(prop_user_profile_property_file BAI_STANDALONE.PLATFORM_TYPE)
                if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
                    CLI_CMD=oc
                elif [[ "$PLATFORM_SELECTED" == "other" ]]
                then
                    CLI_CMD=kubectl
                fi
                validate_kube_oc_cli

                LDAP_USER_NAME=$(prop_user_profile_property_file BAI_STANDALONE.LDAP_USER_NAME_ONBORADING_ZEN)
                NON_DEFAULT_IAM_ADMIN=$(prop_user_profile_property_file BAI_STANDALONE.IAM_ADMIN_USER_NAME)
                MEDIUM_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.MEDIUM_FILE_STORAGE_CLASSNAME)
                FAST_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.FAST_FILE_STORAGE_CLASSNAME)
                BLOCK_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.BLOCK_STORAGE_CLASS_NAME)

                select_project
                select_restricted_internet_access
                flink_job_cr_arr=()
                for i in $(cat $USER_PROFILE_PROPERTY_FILE | grep BAI_STANDALONE.FLINK_JOB_  | grep "True" | tr '[:upper:]' '[:lower:]' | sed 's/.*\.//; s/=.*//')
                do
                    # echo $i
                    flink_job_cr_arr+=("$i")
                done
                # echo "flink_job_cr_arr: ${flink_job_cr_arr[@]}"
            else 
                fail "Not Found existing property file under \"$PROPERTY_FILE_FOLDER\", Please run \"bai-prerequisites.sh\" to complate prerequisites"
                exit 1
            fi
            # show_summary
        fi
        if [[ $DEPLOYMENT_TYPE == "production" && (-z $PROFILE_TYPE) ]]; then
            select_platform
            select_ldap_type          

            if [[ -f $USER_PROFILE_PROPERTY_FILE ]]; then
                MEDIUM_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.MEDIUM_FILE_STORAGE_CLASSNAME)
                FAST_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.FAST_FILE_STORAGE_CLASSNAME)
                BLOCK_STORAGE_CLASS_NAME=$(prop_user_profile_property_file BAI_STANDALONE.BLOCK_STORAGE_CLASS_NAME)
            fi
            if [[ -z $MEDIUM_STORAGE_CLASS_NAME || -z $FAST_STORAGE_CLASS_NAME || -z $BLOCK_STORAGE_CLASS_NAME ]]; then
                get_storage_class_name
            fi

            select_profile_type
            select_iam_default_admin

            select_project
            select_restricted_internet_access
            select_flink_job
        fi
        check_ocp_version
        validate_docker_podman_cli
        prepare_pattern_file
    fi

    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.license.accept "true"
}

function sync_property_into_final_cr(){
    printf "\n"

    wait_msg "Applying value in property file into final CR"

    # Applying platform type in user profile property into final CR
    tmp_value="$(prop_user_profile_property_file BAI_STANDALONE.PLATFORM_TYPE)"
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_deployment_platform \"$tmp_value\"

    # Applying global value in user profile property into final CR
    tmp_value="$(prop_user_profile_property_file BAI_STANDALONE.BAI_LICENSE)"
    ${SED_COMMAND} "s|sc_deployment_license:.*|sc_deployment_license: \"$tmp_value\"|g" ${BAI_PATTERN_FILE_TMP}

    # Apply shared_configuration.enable_fips to always be false
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.enable_fips "false"

    # Set sc_restricted_internet_access
    restricted_flag="$(prop_user_profile_property_file BAI_STANDALONE.ENABLE_RESTRICTED_INTERNET_ACCESS)"
    restricted_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$restricted_flag")
    restricted_flag=$(echo $restricted_flag | tr '[:upper:]' '[:lower:]')
    if [[ ! -z $restricted_flag ]]; then
        if [[ $restricted_flag == "true" ]]; then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access "true"
        else
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access "false"
        fi
    else
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access "true"
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
    
    # Applying value in LDAP property file into final CR
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
    else
        for i in "${!CUSTOM_LDAP_CR_MAPPING[@]}"; do
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} "${CUSTOM_LDAP_CR_MAPPING[i]}" "\"$(prop_ldap_property_file ${CUSTOM_LDAP_PROPERTY[i]})\""
        done
    fi

    # set lc_bind_secret
    tmp_secret_name=`kubectl get secret -l name=ldap-bind-secret -o yaml | ${YQ_CMD} r - items.[0].metadata.name`
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration.lc_bind_secret "\"$tmp_secret_name\""

    # echo "DOCKER_REG_SERVER=$DOCKER_REG_SERVER, use_entitlement=$use_entitlement, CONVERT_LOCAL_REGISTRY_SERVER=$CONVERT_LOCAL_REGISTRY_SERVER, PLATFORM_SELECTED=$PLATFORM_SELECTED,"
    # Set bai_configuration.admin_user
    ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.admin_user "$LDAP_USER_NAME"

    # Set flink job for each components
    for each_flink_job in "${flink_job_cr_arr[@]}"
    do
        if [[ ${each_flink_job} == "flink_job_bpmn" ]]; then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.bpmn.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_bawadv" ]]
        then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.bawadv.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_icm" ]]
        then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.icm.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_odm" ]]
        then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.odm.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_content" ]]
        then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.content.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_ads" ]]
        then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.ads.install "\"true\""
        elif [[ ${each_flink_job} == "flink_job_navigator" ]]
        then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.navigator.install "\"true\""
        fi
    done

    ## Format the Final CR YAML file 
    ${YQ_CMD} d -i ${BAI_PATTERN_FILE_TMP} null
    ${SED_COMMAND} "s|'\"|\"|g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s|\"'|\"|g" ${BAI_PATTERN_FILE_TMP}
    # ${SED_COMMAND} "s|\"\"|\"|g" ${BAI_PATTERN_FILE_TMP}
    # Remove HADR if dose not input value
    ${SED_COMMAND} "s/: \"<Optional>\"/: \"\"/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"\"<Optional>\"\"/: \"\"/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: <Optional>/: \"\"/g" ${BAI_PATTERN_FILE_TMP}

    ${SED_COMMAND} "s/database_ip: \"<Required>\"/database_ip: \"\"/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/dc_hadr_standby_ip: \"<Required>\"/dc_hadr_standby_ip: \"\"/g" ${BAI_PATTERN_FILE_TMP}

    # convert ssl enable true or false to meet CSV
    ${SED_COMMAND} "s/: \"True\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"False\"/: false/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"true\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"false\"/: false/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"Yes\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"yes\"/: true/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"No\"/: false/g" ${BAI_PATTERN_FILE_TMP}
    ${SED_COMMAND} "s/: \"no\"/: false/g" ${BAI_PATTERN_FILE_TMP}


    # comment out sc_ingress_tls_secret_name if OCP platform
    if [[ $PLATFORM_SELECTED == "OCP" ]]; then
        ${SED_COMMAND} "s/sc_ingress_tls_secret_name: /# sc_ingress_tls_secret_name: /g" ${BAI_PATTERN_FILE_TMP}
    fi

    # ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_BAK}
    success "Applied value in property file into final CR under $FINAL_CR_FOLDER"
    msgB "Please confirm final custom resource under $FINAL_CR_FOLDER"
}

function apply_bai_final_cr(){

    # Keep existing value
    if [[ "${INSTALLATION_TYPE}" == "existing" ]]; then
        # read -rsn1 -p"Before Merge: Press any key to continue";echo
        ${YQ_CMD} d -i ${BAI_EXISTING_TMP} spec.shared_configuration.sc_deployment_patterns
        ${YQ_CMD} d -i ${BAI_EXISTING_TMP} spec.shared_configuration.sc_optional_components
        ${SED_COMMAND} '/tag: /d' ${BAI_EXISTING_TMP}
        ${SED_COMMAND} '/appVersion: /d' ${BAI_EXISTING_TMP}
        ${SED_COMMAND} '/release: /d' ${BAI_EXISTING_TMP}
        # ${YQ_CMD} m -a -i -M ${BAI_EXISTING_BAK} ${BAI_PATTERN_FILE_TMP}
        # ${COPY_CMD} -rf ${BAI_EXISTING_BAK} ${BAI_PATTERN_FILE_TMP}
        # ${YQ_CMD} m -a -i -M ${BAI_PATTERN_FILE_TMP} ${BAI_EXISTING_BAK}
        # read -rsn1 -p"After Merge: Press any key to continue";echo
    fi

    ${SED_COMMAND_FORMAT} ${BAI_PATTERN_FILE_TMP}

    if  [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then

        # Set sc_deployment_platform
        ${SED_COMMAND} "s|sc_deployment_platform: OCP|sc_deployment_platform: \"$PLATFORM_SELECTED\"|g" ${BAI_PATTERN_FILE_TMP}

        # Set sc_deployment_type
        ${SED_COMMAND} "s|sc_deployment_type:.*|sc_deployment_type: \"Production\"|g" ${BAI_PATTERN_FILE_TMP}

        # Set lc_selected_ldap_type
        if [[ $SELECTED_LDAP == "Yes" ]];then
            if [[ $LDAP_TYPE == "AD" ]];then
                # ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration.lc_selected_ldap_type "\"Microsoft Active Directory\""
                ${SED_COMMAND} "s|lc_selected_ldap_type:.*|lc_selected_ldap_type: \"Microsoft Active Directory\"|g" ${BAI_PATTERN_FILE_TMP}

            elif [[ $LDAP_TYPE == "TDS" ]]; then
                # ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration.lc_selected_ldap_type "IBM Security Directory Server"
                ${SED_COMMAND} "s|lc_selected_ldap_type:.*|lc_selected_ldap_type: \"IBM Security Directory Server\"|g" ${BAI_PATTERN_FILE_TMP}
            else
                ${SED_COMMAND} "s|lc_selected_ldap_type:.*|lc_selected_ldap_type: \"Custom\"|g" ${BAI_PATTERN_FILE_TMP}
            fi

            if [[ "$LDAP_TYPE" == "AD" ]]; then
                content_start="$(grep -n "# ad:" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
            elif [[ $LDAP_TYPE == "TDS" ]]; then
                content_start="$(grep -n "# tds:" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
            else
                content_start="$(grep -n "# custom:" ${BAI_PATTERN_FILE_TMP} | head -n 1 | cut -d: -f1)"
            fi
            content_stop="$(tail -n +$content_start < ${BAI_PATTERN_FILE_TMP} | grep -n "lc_group_filter:" | head -n1 | cut -d: -f1)"
            content_stop=$(( $content_stop + $content_start - 1))
            vi ${BAI_PATTERN_FILE_TMP} -c ':'"${content_start}"','"${content_stop}"'s/    # /    ' -c ':wq' >/dev/null 2>&1

            # Set bai_configuration.admin_user
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.admin_user "$LDAP_USER_NAME"
        fi

        # Set fips_enable
        if [[ $FIPS_ENABLED == "true" ]]; then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.enable_fips "true"
        else
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.enable_fips "false"
        fi

        # Set sc_restricted_internet_access
        if [[ $RESTRICTED_INTERNET_ACCESS == "true" ]]; then
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access "true"
        else
            ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_egress_configuration.sc_restricted_internet_access "false"
        fi

        # Set sc_dynamic_storage_classname
        if [[ "$PLATFORM_SELECTED" == "ROKS" ]]; then
            ${SED_COMMAND} "s|sc_dynamic_storage_classname:.*|sc_dynamic_storage_classname: \"${FAST_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
        else
            ${SED_COMMAND} "s|sc_dynamic_storage_classname:.*|sc_dynamic_storage_classname: \"${STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
        fi
        ${SED_COMMAND} "s|sc_medium_file_storage_classname:.*|sc_medium_file_storage_classname: \"${MEDIUM_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
        ${SED_COMMAND} "s|sc_fast_file_storage_classname:.*|sc_fast_file_storage_classname: \"${FAST_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
        ${SED_COMMAND} "s|sc_block_storage_classname:.*|sc_block_storage_classname: \"${BLOCK_STORAGE_CLASS_NAME}\"|g" ${BAI_PATTERN_FILE_TMP}
        # Set image_pull_secrets
        # ${SED_COMMAND} "s|image-pull-secret|$DOCKER_RES_SECRET_NAME|g" ${BAI_PATTERN_FILE_TMP}
        ${YQ_CMD} d -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.image_pull_secrets
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.image_pull_secrets.[0] "$DOCKER_RES_SECRET_NAME"


        # support profile size for production
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_deployment_profile_size "\"$PROFILE_TYPE\""


        # set the sc_iam.default_admin_username
        ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.shared_configuration.sc_iam.default_admin_username "\"$NON_DEFAULT_IAM_ADMIN\""

        # Set flink job for each components
        for each_flink_job in "${flink_job_cr_arr[@]}"
        do
            if [[ ${each_flink_job} == "flink_job_bpmn" ]]; then
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.bpmn.install "\"true\""
            elif [[ ${each_flink_job} == "flink_job_bawadv" ]]
            then
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.bawadv.install "\"true\""
            elif [[ ${each_flink_job} == "flink_job_icm" ]]
            then
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.icm.install "\"true\""
            elif [[ ${each_flink_job} == "flink_job_odm" ]]
            then
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.odm.install "\"true\""
            elif [[ ${each_flink_job} == "flink_job_content" ]]
            then
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.content.install "\"true\""
            elif [[ ${each_flink_job} == "flink_job_ads" ]]
            then
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.ads.install "\"true\""
            elif [[ ${each_flink_job} == "flink_job_navigator" ]]
            then
                ${YQ_CMD} w -i ${BAI_PATTERN_FILE_TMP} spec.bai_configuration.navigator.install "\"true\""
            fi
        done
    elif [[ $DEPLOYMENT_WITH_PROPERTY == "Yes" ]]; then
        # Apply value in property file into final cr
        sync_property_into_final_cr
    fi

    # echo "DOCKER_REG_SERVER=$DOCKER_REG_SERVER, use_entitlement=$use_entitlement, CONVERT_LOCAL_REGISTRY_SERVER=$CONVERT_LOCAL_REGISTRY_SERVER,"
    if [[ "$PLATFORM_SELECTED" == "ROKS" || "$PLATFORM_SELECTED" == "OCP" ]]; then
        use_entitlement="yes"
    fi

    # set sc_image_repository
    if [ "$use_entitlement" = "yes" ] ; then
        ${SED_COMMAND} "s|sc_image_repository:.*|sc_image_repository: ${DOCKER_REG_SERVER}|g" ${BAI_PATTERN_FILE_TMP}
    else
        ${SED_COMMAND} "s|sc_image_repository:.*|sc_image_repository: ${CONVERT_LOCAL_REGISTRY_SERVER}|g" ${BAI_PATTERN_FILE_TMP}
    fi

    # Replace image URL
    old_initcontainer="$REGISTRY_IN_FILE\/cp\/cp4a\/bai"

    if [ "$use_entitlement" = "yes" ] ; then
        ${SED_COMMAND} "s/$REGISTRY_IN_FILE/$DOCKER_REG_SERVER/g" ${BAI_PATTERN_FILE_TMP}
    else
        ${SED_COMMAND} "s/$old_initcontainer/$CONVERT_LOCAL_REGISTRY_SERVER/g" ${BAI_PATTERN_FILE_TMP}
    fi

    # Format value 
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

    # remove ldap_configuration when select LDAP is false for BAI stand-alone
    if [[ $SELECTED_LDAP == "No" ]]; then
        ${YQ_CMD} d -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration
    fi

    ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_BAK}

    ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_FINAL}

    echo -e "\x1B[1mThe custom resource file used is: \"${BAI_PATTERN_FILE_FINAL}\"\x1B[0m"
    printf "\n"
    echo -e "\x1B[1mTo monitor the deployment status, follow the Operator logs.\x1B[0m"
    echo -e "\x1B[1mFor details, refer to the troubleshooting section in Knowledge Center here: \x1B[0m"
    echo -e "\x1B[1m https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$BAI_RELEASE_BASE?topic=automation-troubleshooting\x1B[0m"
}

function show_summary(){
    printf "\n"
    echo -e "\x1B[1m*******************************************************\x1B[0m"
    echo -e "\x1B[1m                    Summary of input                   \x1B[0m"
    echo -e "\x1B[1m*******************************************************\x1B[0m"

    echo -e "${YELLOW_TEXT}1. Platform Type: ${RESET_TEXT}${PLATFORM_SELECTED}"

    if [[ $SELECTED_LDAP == "No" ]]; then
        echo -e "${YELLOW_TEXT}2. LDAP Type: ${RESET_TEXT}None"
    else
        echo -e "${YELLOW_TEXT}2. LDAP Type: ${RESET_TEXT}${LDAP_TYPE}"
        echo -e  "   * ${YELLOW_TEXT}LDAP User Name onboarding Zen:${RESET_TEXT} ${LDAP_USER_NAME}"
    fi

    echo -e "${YELLOW_TEXT}3. Profile Size: ${RESET_TEXT}${PROFILE_TYPE}"

    if [[ $USE_DEFAULT_IAM_ADMIN == "Yes" ]]; then
        echo -e "${YELLOW_TEXT}4. IAM default admin user name: ${RESET_TEXT}cpadmin"
    else
        echo -e "${YELLOW_TEXT}4. IAM default admin user name: ${RESET_TEXT}$NON_DEFAULT_IAM_ADMIN"
    fi


    echo -e "${YELLOW_TEXT}5. File storage classname(RWX):${RESET_TEXT}"
    echo -e  "   * ${YELLOW_TEXT}Medium:${RESET_TEXT} ${MEDIUM_STORAGE_CLASS_NAME}"
    echo -e  "   * ${YELLOW_TEXT}Fast:${RESET_TEXT} ${FAST_STORAGE_CLASS_NAME}"
    echo -e "${YELLOW_TEXT}6. Block storage classname(RWO): ${RESET_TEXT}${BLOCK_STORAGE_CLASS_NAME}"

    echo -e "${YELLOW_TEXT}7. Target project for this BAI stand-alone deployment: ${RESET_TEXT}${TARGET_PROJECT_NAME}"

    echo -e "${YELLOW_TEXT}8. Restrict network egress or not for this BAI stand-alone deployment: ${RESET_TEXT}${RESTRICTED_INTERNET_ACCESS}"

    echo -e "${YELLOW_TEXT}9. The Flink job for which components selected: ${RESET_TEXT}"
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

    echo -e "\x1B[1m*******************************************************\x1B[0m"
}

function prepare_pattern_file(){
    ${COPY_CMD} -rf "${OPERATOR_FILE}" "${OPERATOR_FILE_BAK}"
    # ${COPY_CMD} -rf "${OPERATOR_PVC_FILE}" "${OPERATOR_PVC_FILE_BAK}"

    DEPLOY_TYPE_IN_FILE_NAME="production"

    BAI_PATTERN_FILE=${PARENT_DIR}/descriptors/patterns/ibm_cp4a_cr_${DEPLOY_TYPE_IN_FILE_NAME}_bai.yaml
    BAI_PATTERN_FILE_TMP=$TEMP_FOLDER/.ibm_cp4a_cr_${DEPLOY_TYPE_IN_FILE_NAME}_bai_tmp.yaml
    BAI_PATTERN_FILE_BAK=$BAK_FOLDER/.ibm_cp4a_cr_${DEPLOY_TYPE_IN_FILE_NAME}_bai.yaml

    ${COPY_CMD} -rf "${BAI_PATTERN_FILE}" "${BAI_PATTERN_FILE_BAK}"
    ${COPY_CMD} -rf "${BAI_PATTERN_FILE_BAK}" "${BAI_PATTERN_FILE_TMP}"
}

function startup_operator(){
    # scale up BAI stand-alone operators
    local project_name=$1
    local run_mode=$2  # silent
    # info "Scaling up \"IBM Business Automation Insights stand-alone (CP4BA) multi-pattern\" operator"
    kubectl scale --replicas=1 deployment ibm-cp4a-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM Business Automation Insights stand-alone (CP4BA) multi-pattern\" operator"
    fi
    
    # info "Scaling up \"IBM BAI stand-alone FileNet Content Manager\" operator"
    kubectl scale --replicas=1 deployment ibm-content-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM BAI stand-alone FileNet Content Manager\" operator"
    fi

    # info "Scaling up \"IBM BAI stand-alone Foundation\" operator"
    kubectl scale --replicas=1 deployment icp4a-foundation-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM BAI stand-alone Foundation\" operator"
    fi

    # info "Scaling up \"IBM BAI stand-alone Automation Decision Service\" operator"
    kubectl scale --replicas=1 deployment ibm-ads-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM BAI stand-alone Automation Decision Service\" operator"
    fi

    # info "Scaling up \"IBM BAI stand-alone Workflow Process Service\" operator"
    kubectl scale --replicas=1 deployment ibm-cp4a-wfps-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM BAI stand-alone Workflow Process Service\" operator"
    fi

    # DPE only support x86 so check the target cluster arch type
    arch_type=$(kubectl get cm cluster-config-v1 -n kube-system -o yaml | grep -i architecture|tail -1| awk '{print $2}')
    if [[ "$arch_type" == "amd64" ]]; then
        # info "Scaling up \"IBM Document Processing Engine\" operator"
        kubectl scale --replicas=1 deployment ibm-dpe-operator -n $project_name >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            sleep 1
            if [[ -z "$run_mode" ]]; then
                echo "Done!"
            fi
        else
            fail "Failed to scale up \"IBM Document Processing Engine\" operator"
        fi
    fi
    # info "Scaling up \"IBM BAI stand-alone Insights Engine\" operator"
    kubectl scale --replicas=1 deployment ibm-insights-engine-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM BAI stand-alone Insights Engine\" operator"
    fi

    # info "Scaling up \"IBM Operational Decision Manager\" operator"
    kubectl scale --replicas=1 deployment ibm-odm-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM Operational Decision Manager\" operator"
    fi

    # info "Scaling up \"IBM BAI stand-alone Process Federation Server\" operator"
    kubectl scale --replicas=1 deployment ibm-pfs-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM BAI stand-alone Process Federation Server\" operator"
    fi
}

function shutdown_operator(){
    # scale down BAI stand-alone operators
    local project_name=$1
    info "Scaling down \"IBM Business Automation Insights stand-alone (CP4BA) multi-pattern\" operator"
    kubectl scale --replicas=0 deployment ibm-cp4a-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM BAI stand-alone FileNet Content Manager\" operator"
    kubectl scale --replicas=0 deployment ibm-content-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM BAI stand-alone Foundation\" operator"
    kubectl scale --replicas=0 deployment icp4a-foundation-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM BAI stand-alone Automation Decision Service\" operator"
    kubectl scale --replicas=0 deployment ibm-ads-operator-controller-manager -n $project_name >/dev/null 2>&1
    kubectl scale --replicas=0 deployment ibm-ads-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM BAI stand-alone Workflow Process Service\" operator"
    kubectl scale --replicas=0 deployment ibm-cp4a-wfps-operator-controller-manager -n $project_name >/dev/null 2>&1
    kubectl scale --replicas=0 deployment ibm-cp4a-wfps-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM Document Processing Engine\" operator"
    kubectl scale --replicas=0 deployment ibm-dpe-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM BAI stand-alone Insights Engine\" operator"
    kubectl scale --replicas=0 deployment ibm-insights-engine-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM Operational Decision Manager\" operator"
    kubectl scale --replicas=0 deployment ibm-odm-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"

    info "Scaling down \"IBM BAI stand-alone Process Federation Server\" operator"
    kubectl scale --replicas=0 deployment ibm-pfs-operator -n $project_name >/dev/null 2>&1
    echo "Done!"
}

function cncf_install(){
  sed -e '/dba_license/{n;s/value:.*/value: accept/;}' ${CUR_DIR}/../upgradeOperator.yaml > ${CUR_DIR}/../upgradeOperatorsav.yaml ;  mv ${CUR_DIR}/../upgradeOperatorsav.yaml ${CUR_DIR}/../upgradeOperator.yaml
  sed -e '/baw_license/{n;s/value:.*/value: accept/;}' ${CUR_DIR}/../upgradeOperator.yaml > ${CUR_DIR}/../upgradeOperatorsav.yaml ;  mv ${CUR_DIR}/../upgradeOperatorsav.yaml ${CUR_DIR}/../upgradeOperator.yaml
  sed -e '/fncm_license/{n;s/value:.*/value: accept/;}' ${CUR_DIR}/../upgradeOperator.yaml > ${CUR_DIR}/../upgradeOperatorsav.yaml ;  mv ${CUR_DIR}/../upgradeOperatorsav.yaml ${CUR_DIR}/../upgradeOperator.yaml
  sed -e '/ier_license/{n;s/value:.*/value: accept/;}' ${CUR_DIR}/../upgradeOperator.yaml > ${CUR_DIR}/../upgradeOperatorsav.yaml ;  mv ${CUR_DIR}/../upgradeOperatorsav.yaml ${CUR_DIR}/../upgradeOperator.yaml

  if [ ! -z ${IMAGEREGISTRY} ]; then
  # Change the location of the image
  echo "Using the operator image name: $IMAGEREGISTRY"
  sed -e "s|image: .*|image: \"$IMAGEREGISTRY\" |g" ${CUR_DIR}/../upgradeOperator.yaml > ${CUR_DIR}/../upgradeOperatorsav.yaml ;  mv ${CUR_DIR}/../upgradeOperatorsav.yaml ${CUR_DIR}/../upgradeOperator.yaml
  fi

  # Change the pullSecrets if needed
  if [ ! -z ${PULLSECRET} ]; then
      echo "Setting pullSecrets to $PULLSECRET"
      sed -e "s|ibm-entitlement-key|$PULLSECRET|g" ${CUR_DIR}/../upgradeOperator.yaml > ${CUR_DIR}/../upgradeOperatorsav.yaml ;  mv ${CUR_DIR}/../upgradeOperatorsav.yaml ${CUR_DIR}/../upgradeOperator.yaml
  else
      sed -e '/imagePullSecrets:/{N;d;}' ${CUR_DIR}/../upgradeOperator.yaml > ${CUR_DIR}/../upgradeOperatorsav.yaml ;  mv ${CUR_DIR}/../upgradeOperatorsav.yaml ${CUR_DIR}/../upgradeOperator.yaml
  fi
  kubectl apply -f ${CUR_DIR}/../descriptors/service_account.yaml --validate=false
  kubectl apply -f ${CUR_DIR}/../descriptors/role.yaml --validate=false
  kubectl apply -f ${CUR_DIR}/../descriptors/role_binding.yaml --validate=false
  kubectl apply -f ${CUR_DIR}/../upgradeOperator.yaml --validate=false
}

function show_help() {
    echo -e "\nUsage: bai-deployment.sh -m [modetype] -s [automatic or manual] -n <NAMESPACE>\n"
    echo "Options:"
    echo "  -h  Display the help"
    echo "  -m  The valid mode types are:[upgradeOperator], [upgradeOperatorStatus], [upgradeDeployment] and [upgradeDeploymentStatus]"
    echo "  -s  The value of the update approval strategy. The valid values are: [automatic] and [manual]."
    echo "  -n  The target namespace of the BAI stand-alone operator and deployment."
    echo "  -i  Optional: Operator image name, by default it is cp.icr.io/cp/cp4a/icp4a-operator:$BAI_RELEASE_BASE"
    echo "  -p  Optional: Pull secret to use to connect to the registry, by default it is ibm-entitlement-key"
    echo "  --enable-private-catalog Optional: Set this flag to let the script to switch CatalogSource from global to namespace scoped. Default is in openshift-marketplace namespace"
    echo "  ${YELLOW_TEXT}* Running the script to create a custom resource file for new BAI stand-alone deployment:${RESET_TEXT}"
    echo "      - STEP 1: Run the script without any parameter."
    echo "  ${YELLOW_TEXT}* Running the script to upgrade a BAI stand-alone deployment from 23.0.1.X to $BAI_RELEASE_BASE GA/$BAI_RELEASE_BASE.X. You must run the modes in the following order:${RESET_TEXT}"
    echo "      - STEP 1: Run the script in [upgradeOperator] mode to upgrade the BAI stand-alone operator"
    echo "      - STEP 2: Run the script in [upgradeOperatorStatus] mode to check that the upgrade of the BAI stand-alone operator and its dependencies is successful."
    echo "      - STEP 3: Run the script in [upgradeDeployment] mode to upgrade the BAI stand-alone deployment."
    echo "      - STEP 4: Run the script in [upgradeDeploymentStatus] mode to check that the upgrade of the BAI stand-alone deployment is successful."
    echo "  ${YELLOW_TEXT}* Running the script to upgrade a BAI stand-alone deployment from $BAI_RELEASE_BASE GA/$BAI_RELEASE_BASE.X to $BAI_RELEASE_BASE.X. You must run the modes in the following order:${RESET_TEXT}"
    echo "      - STEP 1: Run the script in [upgradeOperator] mode to upgrade the BAI stand-alone operator"
    echo "      - STEP 2: Run the script in [upgradeOperatorStatus] mode to check that the upgrade of the BAI stand-alone operator and its dependencies is successful."
    echo "      - STEP 3: Run the script in [upgradeDeploymentStatus] mode to check that the upgrade of the BAI stand-alone deployment is successful."

}

function parse_arguments() {
    # process options
    while [[ "$@" != "" ]]; do
        case "$1" in
        -m)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -m requires an argument"
                exit 1
            fi
            RUNTIME_MODE=$1
            if [[ $RUNTIME_MODE == "upgradeOperator" || $RUNTIME_MODE == "upgradeOperatorStatus" || $RUNTIME_MODE == "upgradeDeployment" || $RUNTIME_MODE == "upgradeDeploymentStatus" ]]; then
                echo -n
            else
                msg "Use a valid value: -m [upgradeOperator] or [upgradeOperatorStatus] or [upgradeDeployment] [upgradeDeploymentStatus]"
                exit -1
            fi
            ;;
        -s)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -s requires an argument"
                exit 1
            fi
            UPDATE_APPROVAL_STRATEGY=$1
            if [[ $UPDATE_APPROVAL_STRATEGY == "automatic" || $UPDATE_APPROVAL_STRATEGY == "manual" ]]; then
                echo -n
            else
                msg "Use a valid value: -s [automatic] or [manual]"
                exit -1
            fi
            ;;
        -n)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -n requires an argument"
                exit 1
            fi
            TARGET_PROJECT_NAME=$1
            case "$TARGET_PROJECT_NAME" in
            "")
                echo -e "\x1B[1;31mEnter a valid namespace name, namespace name can not be blank\x1B[0m"
                exit -1
                ;;
            "openshift"*)
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
                exit -1
                ;;
            "kube"*)
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
                exit -1
                ;;
            *)
                isProjExists=`kubectl get project $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ $isProjExists -ne 2 ] ; then
                    echo -e "\x1B[1;31mInvalid project name \"$TARGET_PROJECT_NAME\", please set a valid name...\x1B[0m"
                    exit 1
                fi
                echo -n
                ;;
            esac
            ;;
        -i)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -i requires an argument"
                exit 1
            fi
            IMAGEREGISTRY=$1
            ;;
        -p)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -p requires an argument"
                exit 1
            fi
            PULLSECRET=$1
            ;;
        -h | --help | \?)
            show_help
            exit 0
            ;;
        --enable-private-catalog)
            ENABLE_PRIVATE_CATALOG=1
            ;;
        *) 
            echo "Invalid option"
            show_help
            exit 1
            ;;
        esac
        shift
    done
}
################################################
#### Begin - Main step for install operator ####
################################################
save_log "bai-script-logs" "bai-deployment-log"
trap cleanup_log EXIT
if [[ $1 == "" || $1 == "dev" || $1 == "review" ]]
then
    prompt_license

    set_script_mode

    input_information

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
                    echo -e "\x1B[1mCreating the Custom Resource of the IBM Business Automation Insights stand-alone Operator...\x1B[0m"
                fi
            fi
            printf "\n"
            if [[ "${INSTALLATION_TYPE}"  == "new" ]]; then
                if [[ "$SCRIPT_MODE" == "review" ]]; then
                    echo -e "\x1B[1mReview mode running, just generate final CR, will not deploy operator\x1B[0m"
                    # read -rsn1 -p"Press any key to continue";echo
                elif [[ "$SCRIPT_MODE" == "OLM" ]]
                then
                    echo -e "\x1B[1mA custom resource file to apply in the OCP Catalog is being generated.\x1B[0m"
                    # read -rsn1 -p"Press any key to continue";echo
                else
                    if [ "$use_entitlement" = "no" ] ; then
                        isReady=$(${CLI_CMD} get secret | grep ibm-entitlement-key)
                        if [[ -z $isReady ]]; then
                            echo "NOT found secret \"ibm-entitlement-key\", exiting..."
                            exit 1
                        else
                            echo "Found secret \"ibm-entitlement-key\", continue...."
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

                printf "\x1B[1mEnter the number from 1 to 10 that you want to change: \x1B[0m"

                read -rp "" ans
                case "$ans" in
                "1")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_platform
                    else
                        info "Please run bai-prerequisites.sh to modify platform type"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "2")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_ldap_type
                    else
                        info "Please run bai-prerequisites.sh to modify LDAP type"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "3")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_profile_type
                    else
                        info "Please run bai-prerequisites.sh to modify profile size"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "4")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_iam_default_admin
                    else
                        info "Please run bai-prerequisites.sh to modify IAM default admin"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "5"|"6")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        get_storage_class_name
                    else
                        info "Please run bai-prerequisites.sh to modify storage class"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "7")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        TARGET_PROJECT_NAME=""
                        select_project
                    else
                        info "Please run bai-prerequisites.sh to modify target project"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "8")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_restricted_internet_access
                    else
                        info "Please run bai-prerequisites.sh to modify storage class"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "9")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_flink_job
                    else
                        info "Please run bai-prerequisites.sh to modify the flink job for which component(s)"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                *)
                    echo -e "\x1B[1mEnter a valid number [1 to 5] \x1B[0m"
                    ;;
                esac
            done
            show_summary
            ;;
        esac
    done
else
    # Import upgrade prerequisite.sh script
    # source ${CUR_DIR}/helper/upgrade/prerequisite.sh
    ENABLE_PRIVATE_CATALOG=0
    parse_arguments "$@"
    if [[ -z "$RUNTIME_MODE" ]]; then
        echo -e "\x1B[1;31mPlease input value for \"-m <MODE_NAME>\" option.\n\x1B[0m"
        exit 1
    fi
    if [[ -z "$TARGET_PROJECT_NAME" ]]; then
        echo -e "\x1B[1;31mPlease input value for \"-n <NAME_SPACE>\" option.\n\x1B[0m"
        exit 1
    fi
fi

# Import upgrade upgrade_check_version.sh script
source ${CUR_DIR}/helper/upgrade/upgrade_check_status.sh

if [ "$RUNTIME_MODE" == "upgradeOperator" ]; then
    info "Starting to upgrade BAI stand-alone operators and IBM foundation services"
    # check current cp4ba/content operator version
    check_cp4ba_operator_version $TARGET_PROJECT_NAME
    check_content_operator_version $TARGET_PROJECT_NAME
    if [[ "$cp4a_operator_csv_version" == "22.2."* ]]; then
        fail "Found BAI stand-alone Operator is version \"$cp4a_operator_csv_version\", please upgrade to v23.0.x firstly."
        exit 1
    fi
    if [[ "$cp4a_content_operator_csv_version" == "22.2."* ]]; then
        fail "Found BAI stand-alone Content Operator is version \"$cp4a_content_operator_csv_version\", please upgrade to v23.0.x firstly."
        exit 1
    fi 
    if [[ "$cp4a_operator_csv_version" == "${BAI_CSV_VERSION//v/}" && "$cp4a_content_operator_csv_version" == "${BAI_CSV_VERSION//v/}"  ]]; then
        warning "The BAI stand-alone operator already is $BAI_CSV_VERSION."
        printf "\n"
        while true; do
            printf "\x1B[1mDo you want to continue run upgrade? (Yes/No, default: No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                break
                ;;
            "n"|"N"|"no"|"No"|"NO"|"")
                echo "Exiting..."
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    fi
    UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/cp4ba-upgrade/project/$TARGET_PROJECT_NAME
    UPGRADE_DEPLOYMENT_PROPERTY_FILE=${UPGRADE_DEPLOYMENT_FOLDER}/cp4ba_upgrade.property

    UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
    UPGRADE_DEPLOYMENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR}/backup
    UPGRADE_DEPLOYMENT_CONTENT_CR=${UPGRADE_DEPLOYMENT_CR}/content.yaml
    UPGRADE_DEPLOYMENT_CONTENT_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.content_tmp.yaml
    UPGRADE_DEPLOYMENT_CONTENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/content_cr_backup.yaml

    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR=${UPGRADE_DEPLOYMENT_CR}/icp4acluster.yaml
    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.icp4acluster_tmp.yaml
    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/icp4acluster_cr_backup.yaml

    UPGRADE_DEPLOYMENT_BAI_TMP=${UPGRADE_DEPLOYMENT_CR}/.bai_tmp.yaml

    PLATFORM_SELECTED=$(eval echo $(kubectl get icp4acluster $(kubectl get icp4acluster --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME | grep NAME -v | awk '{print $1}') --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o yaml | grep sc_deployment_platform | tail -1 | cut -d ':' -f 2))
    if [[ -z $PLATFORM_SELECTED ]]; then
        PLATFORM_SELECTED=$(eval echo $(kubectl get content $(kubectl get content --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME | grep NAME -v | awk '{print $1}') --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o yaml | grep sc_deployment_platform | tail -1 | cut -d ':' -f 2))
        if [[ -z $PLATFORM_SELECTED ]]; then
            fail "Not found any custom resource for BAI stand-alone under project \"$TARGET_PROJECT_NAME\", exiting"
            exit 1
        fi
    fi

    # Checking CSV for cp4ba-operator/content-operator/bai-operator to decide whether to do BAI save point during IFIX to IFIX upgrade
    sub_inst_list=$(kubectl get subscriptions.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-cp4a-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
    if [[ -z $sub_inst_list ]]; then
        info "Not found any existing BAI stand-alone subscriptions, continue ..."
        # exit 1
    fi
    sub_array=($sub_inst_list)
    target_csv_version=${BAI_CSV_VERSION//v/}
    for i in ${!sub_array[@]}; do
        if [[ ! -z "${sub_array[i]}" ]]; then
            if [[ ${sub_array[i]} = ibm-cp4a-operator* || ${sub_array[i]} = ibm-content-operator* || ${sub_array[i]} = ibm-insights-engine-operator* ]]; then
                current_version=$(kubectl get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                installed_version=$(kubectl get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                if [[ -z $current_version || -z $installed_version ]]; then
                    error "fail to get installed or current CSV, abort the upgrade procedure. Please check ${sub_array[i]} subscription status."
                    exit 1
                fi
                case "${sub_array[i]}" in
                "ibm-cp4a-operator"*)
                    prefix_sub="ibm-cp4a-operator.v"
                    ;;
                "ibm-content-operator"*)
                    prefix_sub="ibm-content-operator.v"
                    ;;
                "ibm-insights-engine-operator"*)
                    prefix_sub="ibm-insights-engine-operator.v"
                    ;;
                esac
                current_version=${current_version#"$prefix_sub"}
                installed_version=${installed_version#"$prefix_sub"}
                if [[ $current_version != $installed_version || $current_version != $target_csv_version || $installed_version != $target_csv_version ]]; then
                    RUN_BAI_SAVEPOINT="Yes"
                fi
            fi
        else
            fail "No found subsciption '${sub_array[i]}'! exiting now..."
            exit 1
        fi
    done

    if [[ $RUN_BAI_SAVEPOINT == "Yes" ]]; then
        # Retrieve existing Content CR for Create BAI save points
        info "Create the BAI savepoints for recovery path before upgrade CP4BA"
        mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
        mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
        content_cr_name=$(kubectl get content -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')
        if [ ! -z $content_cr_name ]; then
            info "Retrieving existing BAI stand-alone Content (Kind: content.icp4a.ibm.com) Custom Resource"
            cr_type="content"
            cr_metaname=$(kubectl get content $content_cr_name -n $TARGET_PROJECT_NAME -o yaml | ${YQ_CMD} r - metadata.name)
            owner_ref=$(kubectl get content $content_cr_name -n $TARGET_PROJECT_NAME -o yaml | ${YQ_CMD} r - metadata.ownerReferences.[0].kind)
            if [[ ${owner_ref} == "ICP4ACluster" ]]; then
                echo
            else
                kubectl get $cr_type $content_cr_name -n $TARGET_PROJECT_NAME -o yaml > ${UPGRADE_DEPLOYMENT_CONTENT_CR_TMP}
                
                # Backup existing content CR
                mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK} >/dev/null 2>&1
                ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_CONTENT_CR_TMP} ${UPGRADE_DEPLOYMENT_CONTENT_CR_BAK}

                # Create BAI save points
                mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
                bai_flag=`cat $UPGRADE_DEPLOYMENT_CONTENT_CR_TMP | ${YQ_CMD} r - spec.content_optional_components.bai`
                if [[ $bai_flag == "True" || $bai_flag == "true" ]]; then
                    # Check the jq install on MacOS
                    if [[ "$machine" == "Mac" ]]; then
                        which jq &>/dev/null
                        [[ $? -ne 0 ]] && \
                        echo -e  "\x1B[1;31mUnable to locate an jq CLI. You must install it to run this script on MacOS.\x1B[0m" && \
                        exit 1                        
                    fi
                    rm -rf ${TEMP_FOLDER}/bai.json >/dev/null 2>&1
                    touch ${UPGRADE_DEPLOYMENT_BAI_TMP} >/dev/null 2>&1
                    info "Create the BAI savepoints for recovery path when merge custom resource"
                    # INSIGHTS_ENGINE_CR="iaf-insights-engine"
                    INSIGHTS_ENGINE_CR=$(kubectl get insightsengines --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o name)
                    if [[ -z $INSIGHTS_ENGINE_CR ]]; then
                        error "Not found insightsengines custom resource instance under project \"${TARGET_PROJECT_NAME}\"."
                        exit 1
                    fi
                    MANAGEMENT_URL=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].uri}')
                    MANAGEMENT_AUTH_SECRET=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].authentication.secret.secretName}')
                    MANAGEMENT_USERNAME=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.data.username}' | base64 -d)
                    MANAGEMENT_PASSWORD=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.data.password}' | base64 -d)
                    if [[ -z "$MANAGEMENT_URL" || -z "$MANAGEMENT_AUTH_SECRET" || -z "$MANAGEMENT_USERNAME" || -z "$MANAGEMENT_PASSWORD" ]]; then
                        error "Can not create the BAI savepoints for recovery path."
                        # exit 1
                    else
                        curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} "${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints" -o ${TEMP_FOLDER}/bai.json >/dev/null 2>&1
                        
                        json_file_content="[]"
                        if [ "$json_file_content" == "$(cat ${TEMP_FOLDER}/bai.json)" ] ;then
                            fail "None return in \"${TEMP_FOLDER}/bai.json\" when request BAI savepoint through REST API: curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} \"${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints\" "
                            warning "Please fetch BAI savepoints for recovery path using above REST API manually, and then put JSON file (bai.json) under the directory \"${TEMP_FOLDER}/\""
                            read -rsn1 -p"Press any key to continue";echo
                        fi                        
                        
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-event-forwarder)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-event-forwarder |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.event-forwarder.recovery_path ${tmp_recovery_path}
                            success "Create savepoint for Event-forwarder: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.event-forwarder.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-content)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-content |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.content.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for Content: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.content.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-icm)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-icm |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.icm.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for ICM: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.icm.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-odm)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-odm |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.odm.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for ODM: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.odm.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bawadv)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bawadv |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bawadv.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for BAW ADV: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bawadv.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bpmn)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bpmn |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bpmn.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for BPMN: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bpmn.recovery_path."
                        fi
                    fi
                fi
            fi
        fi

        # Retrieve existing ICP4ACluster CR for Create BAI save points
        icp4acluster_cr_name=$(kubectl get icp4acluster -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')
        if [ ! -z $icp4acluster_cr_name ]; then
            info "Retrieving existing BAI stand-alone ICP4ACluster (Kind: icp4acluster.icp4a.ibm.com) Custom Resource"
            cr_type="icp4acluster"
            cr_metaname=$(kubectl get icp4acluster $icp4acluster_cr_name -n $TARGET_PROJECT_NAME -o yaml | ${YQ_CMD} r - metadata.name)
            kubectl get $cr_type $icp4acluster_cr_name -n $TARGET_PROJECT_NAME -o yaml > ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP}
            
            # Backup existing icp4acluster CR
            mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
            ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP} ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK}

            # Get EXISTING_PATTERN_ARR/EXISTING_OPT_COMPONENT_ARR
            existing_pattern_list=""
            existing_opt_component_list=""
            
            EXISTING_PATTERN_ARR=()
            EXISTING_OPT_COMPONENT_ARR=()
            existing_pattern_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
            existing_opt_component_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`

            OIFS=$IFS
            IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
            IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
            IFS=$OIFS

            # Create BAI save points
            mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
            if [[ (" ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "bai") ]]; then
                # Check the jq install on MacOS
                if [[ "$machine" == "Mac" ]]; then
                    which jq &>/dev/null
                    [[ $? -ne 0 ]] && \
                    echo -e  "\x1B[1;31mUnable to locate an jq CLI. You must install it to run this script on MacOS.\x1B[0m" && \
                    exit 1                        
                fi
                info "Create the BAI savepoints for recovery path when merge custom resource"
                rm -rf ${TEMP_FOLDER}/bai.json >/dev/null 2>&1
                touch ${UPGRADE_DEPLOYMENT_BAI_TMP} >/dev/null 2>&1
                # INSIGHTS_ENGINE_CR="iaf-insights-engine"
                INSIGHTS_ENGINE_CR=$(kubectl get insightsengines --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o name)
                if [[ -z $INSIGHTS_ENGINE_CR ]]; then
                    error "Not found insightsengines custom resource instance under project \"${TARGET_PROJECT_NAME}\"."
                    exit 1
                fi
                MANAGEMENT_URL=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].uri}')
                MANAGEMENT_AUTH_SECRET=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].authentication.secret.secretName}')
                MANAGEMENT_USERNAME=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.data.username}' | base64 -d)
                MANAGEMENT_PASSWORD=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.data.password}' | base64 -d)
                if [[ -z "$MANAGEMENT_URL" || -z "$MANAGEMENT_AUTH_SECRET" || -z "$MANAGEMENT_USERNAME" || -z "$MANAGEMENT_PASSWORD" ]]; then
                    error "Can not create the BAI savepoints for recovery path."
                    # exit 1
                else
                    curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} "${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints" -o ${TEMP_FOLDER}/bai.json >/dev/null 2>&1

                    json_file_content="[]"
                    if [ "$json_file_content" == "$(cat ${TEMP_FOLDER}/bai.json)" ] ;then
                        fail "None return in \"${TEMP_FOLDER}/bai.json\" when request BAI savepoint through REST API: curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} \"${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints\" "
                        warning "Please fetch BAI savepoints for recovery path using above REST API manually, and then put JSON file (bai.json) under the directory \"${TEMP_FOLDER}/\""
                        read -rsn1 -p"Press any key to continue";echo
                    fi 

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-event-forwarder)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-event-forwarder |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.event-forwarder.recovery_path ${tmp_recovery_path}
                        success "Create savepoint for Event-forwarder: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.event-forwarder.recovery_path."
                    fi
                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-content)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-content |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.content.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for Content: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.content.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-icm)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-icm |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.icm.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for ICM: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.icm.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-odm)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-odm |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.odm.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for ODM: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.odm.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bawadv)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bawadv |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bawadv.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for BAW ADV: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bawadv.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bpmn)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bpmn |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bpmn.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for BPMN: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bpmn.recovery_path."
                    fi
                fi
            fi
        fi
    fi


    if [[ "$PLATFORM_SELECTED" == "others" ]]; then
        [ -f ${UPGRADE_DEPLOYMENT_FOLDER}/upgradeOperator.yaml ] && rm ${UPGRADE_DEPLOYMENT_FOLDER}/upgradeOperator.yaml
        cp ${CUR_DIR}/../descriptors/operator.yaml ${UPGRADE_DEPLOYMENT_FOLDER}/upgradeOperator.yaml
        cncf_install
    else
        # checking existing catalog type
        if kubectl get catalogsource -n openshift-marketplace | grep ibm-cp4a-operator-catalog >/dev/null 2>&1; then
            CATALOG_FOUND="Yes"
            PINNED="Yes"
        elif kubectl get catalogsource -n openshift-marketplace | grep ibm-operator-catalog >/dev/null 2>&1; then
            CATALOG_FOUND="Yes"
            PINNED="No"
        else
            CATALOG_FOUND="No"
            PINNED="Yes" # Fresh install use pinned catalog source
        fi

        #  Switch BAI stand-alone Operator to private catalog source
        if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
            
            sub_inst_list=$(kubectl get subscriptions.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-cp4a-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
            if [[ -z $sub_inst_list ]]; then
                info "Not found any existing BAI stand-alone subscriptions, continue ..."
                # exit 1
            fi

            sub_array=($sub_inst_list)
            for i in ${!sub_array[@]}; do
                if [[ ! -z "${sub_array[i]}" ]]; then
                    if [[ ${sub_array[i]} = ibm-cp4a-operator* || ${sub_array[i]} = ibm-cp4a-wfps-operator* || ${sub_array[i]} = ibm-content-operator* || ${sub_array[i]} = icp4a-foundation-operator* || ${sub_array[i]} = ibm-pfs-operator* || ${sub_array[i]} = ibm-ads-operator* || ${sub_array[i]} = ibm-dpe-operator* || ${sub_array[i]} = ibm-odm-operator* || ${sub_array[i]} = ibm-insights-engine-operator* ]]; then
                        kubectl patch subscriptions.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -p '{"spec":{"sourceNamespace":"'"$TARGET_PROJECT_NAME"'"}}' --type=merge >/dev/null 2>&1
                        if [ $? -eq 0 ]
                        then
                            sleep 1
                            success "Switched the CatalogSource of subsciption '${sub_array[i]}' to project \"$TARGET_PROJECT_NAME\"!"
                            printf "\n"
                        else
                            fail "Failed to switch the CatalogSource of subsciption '${sub_array[i]}' to project \"$TARGET_PROJECT_NAME\"!"
                        fi
                    fi
                else
                    fail "No found subsciption '${sub_array[i]}' under project \"$TARGET_PROJECT_NAME\"! exiting now..."
                    exit 1
                fi
            done
        fi

        #  Patch BAI stand-alone channel to v23.1, wait for all the operators are upgraded before applying operandRequest.
        sub_inst_list=$(kubectl get subscriptions.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-cp4a-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
        if [[ -z $sub_inst_list ]]; then
            info "Not found any existing BAI stand-alone subscriptions, continue ..."
            # exit 1
        fi

        sub_array=($sub_inst_list)
        for i in ${!sub_array[@]}; do
            if [[ ! -z "${sub_array[i]}" ]]; then
                if [[ ${sub_array[i]} = ibm-cp4a-operator* || ${sub_array[i]} = ibm-cp4a-wfps-operator* || ${sub_array[i]} = ibm-content-operator* || ${sub_array[i]} = icp4a-foundation-operator* || ${sub_array[i]} = ibm-pfs-operator* || ${sub_array[i]} = ibm-ads-operator* || ${sub_array[i]} = ibm-dpe-operator* || ${sub_array[i]} = ibm-odm-operator* || ${sub_array[i]} = ibm-insights-engine-operator* ]]; then
                    kubectl patch subscriptions.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -p '{"spec":{"channel":"v23.2"}}' --type=merge >/dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        info "Updated the channel of subsciption '${sub_array[i]}' to 23.2!"
                        printf "\n"
                    else
                        fail "Failed to update the channel of subsciption '${sub_array[i]}' to 23.2! exiting now..."
                        exit 1
                    fi
                fi
            else
                fail "No found subsciption '${sub_array[i]}'! exiting now..."
                exit 1
            fi
        done

        success "Completed to switch the channel of subsciption for BAI stand-alone operators"

        if [[ $CATALOG_FOUND == "Yes" && $PINNED == "Yes" ]]; then
            # switch catalog from "global" to "namespace" catalog
            if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
                TEMP_PROJECT_NAME=${TARGET_PROJECT_NAME}
                OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
                OLM_CATALOG_TMP=${TEMP_FOLDER}/.catalog_source.yaml

                sed "s/REPLACE_CATALOG_SOURCE_NAMESPACE/$CATALOG_NAMESPACE/g" ${OLM_CATALOG} > ${OLM_CATALOG_TMP}
                # replace all other catalogs with <CP4BA NS> namespaces 
                ${SED_COMMAND} "s|namespace: .*|namespace: $TARGET_PROJECT_NAME|g" ${OLM_CATALOG_TMP}
                # keep openshift-marketplace for ibm-cert-manager-catalog with ibm-cert-manager
                ${SED_COMMAND} "/name: ibm-cert-manager-catalog/{n;s/namespace: .*/namespace: openshift-marketplace/;}" ${OLM_CATALOG_TMP}
                # keep openshift-marketplace for ibm-licensing-catalog with ibm-licensing
                ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: openshift-marketplace/;}" ${OLM_CATALOG_TMP}

                kubectl apply -f $OLM_CATALOG_TMP
                if [ $? -eq 0 ]; then
                    echo "IBM Operator Catalog source updated!"
                else
                    echo "Generic Operator catalog source update failed"
                    exit 1
                fi
            else
                TEMP_PROJECT_NAME="openshift-marketplace"
                info "Apply latest BAI stand-alone catalog source ..."
                OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
                kubectl apply -f $OLM_CATALOG >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                    echo "IBM Cloud Pak® for Business Automation Operator catalog source update failed"
                    exit 1
                fi
                echo "Done!"  
            fi     

            # Checking ibm-cp4a-operator catalog soure pod
            info "Checking BAI stand-alone operator catalog pod ready or not under project \"$TEMP_PROJECT_NAME\""
            maxRetry=10
            for ((retry=0;retry<=${maxRetry};retry++)); do
                cp4a_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-cp4a-operator-catalog -n $TEMP_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                fncm_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-fncm-operator-catalog -n $TEMP_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                postgresql_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=cloud-native-postgresql-catalog -n $TEMP_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                cs_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=$CS_CATALOG_VERSION -n $TEMP_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                cert_mgr_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-cert-manager-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                license_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-licensing-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')

                if [[ ( -z $cert_mgr_catalog_pod_name) || ( -z $license_catalog_pod_name) || ( -z $cs_catalog_pod_name) || ( -z $cp4a_catalog_pod_name) || (-z $fncm_catalog_pod_name) || (-z $postgresql_catalog_pod_name) ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        printf "\n"
                        if [[ -z $cp4a_catalog_pod_name ]]; then
                            warning "Timeout Waiting for ibm-cp4a-operator-catalog catalog pod ready under project \"$TEMP_PROJECT_NAME\""
                        elif [[ -z $fncm_catalog_pod_name ]]; then
                            warning "Timeout Waiting for ibm-fncm-operator-catalog catalog pod ready under project \"$TEMP_PROJECT_NAME\""
                        elif [[ -z $postgresql_catalog_pod_name ]]; then
                            warning "Timeout Waiting for cloud-native-postgresql-catalog catalog pod ready under project \"$TEMP_PROJECT_NAME\""
                        elif [[ -z $cs_catalog_pod_name ]]; then
                            warning "Timeout Waiting for $CS_CATALOG_VERSION catalog pod ready under project \"$TEMP_PROJECT_NAME\""
                        elif [[ -z $cert_mgr_catalog_pod_name ]]; then
                            warning "Timeout Waiting for ibm-cert-manager-catalog catalog pod ready under project \"openshift-marketplace\""
                        elif [[ -z $license_catalog_pod_name ]]; then
                            warning "Timeout Waiting for ibm-licensing-catalog catalog pod ready under project \"openshift-marketplace\""
                        fi
                        exit 1
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi
                else
                    success "CP4BA operator catalog pod ready under project \"$TEMP_PROJECT_NAME\"!"
                    break
                fi
            done
        else
            fail "Not found IBM Cloud Pak® for Business Automation catalog source!"
            exit 1
        fi

        # check_cp4ba_operator_version $TARGET_PROJECT_NAME
        # check_content_operator_version $TARGET_PROJECT_NAME
        if [ -z "$UPDATE_APPROVAL_STRATEGY" ]; then
            info "The default value is [automatic] for \"-s <UPDATE_APPROVAL_STRATEGY>\" option. "
            # info "run script with -h option for help. "
            # read -rsn1 -p"Press any key to continue or CTRL+C to break";echo
            UPDATE_APPROVAL_STRATEGY="automatic"
        fi

        # Upgrade BAI stand-alone operator
        info "Starting to upgrade BAI stand-alone operator"


        # Check IAF operator already removed again before change channel of subscription
        mkdir -p $UPGRADE_DEPLOYMENT_IAF_LOG_FOLDER >/dev/null 2>&1
        info "Checking IBM Automation Foundation components under the project \"$TARGET_PROJECT_NAME\"."
        iaf_core_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-core-operator,app.kubernetes.io/instance=iaf-core-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        iaf_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-operator,app.kubernetes.io/instance=iaf-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')

        if [[ (! -z "$iaf_core_operator_pod_name") || (! -z "$iaf_operator_pod_name") ]]; then
        # remove IAF components from BAI stand-alone deployment
            info "Starting to remove IAF components from BAI stand-alone deployment under project \"$TARGET_PROJECT_NAME\""
            cp4ba_cr_name=$(kubectl get icp4acluster -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')

            if [[ -z $cp4ba_cr_name ]]; then
                cp4ba_cr_name=$(kubectl get content -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')
                cr_type="contents.icp4a.ibm.com"
            else
                cr_type="icp4aclusters.icp4a.ibm.com"
            fi

            if [[ -z $cp4ba_cr_name ]]; then
                fail "Not found any custom resource for BAI stand-alone deployment under project \"$TARGET_PROJECT_NAME\", exit..."
                exit 1
            else
                cp4ba_cr_metaname=$(kubectl get $cr_type $cp4ba_cr_name -n $TARGET_PROJECT_NAME -o yaml | ${YQ_CMD} r - metadata.name)
            fi
            cs_dedicated=$(kubectl get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_DEDICATED_NAME} | awk '{print $1}')

            cs_shared=$(kubectl get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_SHARED_NAME} | awk '{print $1}')

            if [[ "$cs_dedicated" != "" && "$cs_shared" == ""  ]] ; then
                control_namespace=$(kubectl get cm ${COMMON_SERVICES_CM_DEDICATED_NAME} --no-headers --ignore-not-found -n ${COMMON_SERVICES_CM_NAMESPACE}  -o jsonpath='{ .data.common-service-maps\.yaml }' | grep  'controlNamespace' | cut -d':' -f2)
                control_namespace=$(sed -e 's/^"//' -e 's/"$//' <<<"$control_namespace")
                control_namespace=$(sed "s/ //g" <<< $control_namespace)
            fi


            source ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $control_namespace "icp4ba" "none" >/dev/null 2>&1
            info "Checking if IAF components be removed from the project \"$TARGET_PROJECT_NAME\""
            maxRetry=10
            for ((retry=0;retry<=${maxRetry};retry++)); do
                iaf_core_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-core-operator,app.kubernetes.io/instance=iaf-core-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                iaf_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-operator,app.kubernetes.io/instance=iaf-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')

                # if [[ -z $isReadyWebhook || -z $isReadyCertmanager || -z $isReadyCainjector || -z $isReadyCertmanagerOperator ]]; then
                if [[ (! -z $iaf_core_operator_pod_name) || (! -z $iaf_operator_pod_name) ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        printf "\n"
                        warning "Timeout Waiting for IBM Automation Foundation be removed from the project \"$TARGET_PROJECT_NAME\""
                        echo -e "\x1B[1mPlease remove IAF manually with cmd: \"${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $control_namespace \"icp4ba\" \"none\"\"\x1B[0m"
                        exit 1
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi
                else
                    success "IBM Automation Foundation was removed successfully!"
                    break
                fi
            done
        else
            success "IBM Automation Foundation components already were removed from the project \"$TARGET_PROJECT_NAME\"!"
        fi

        # Do NOT need to upgrade CPFS 4.2 when upgrade from BAI stand-alone 23.0.1 IF004 to 23.0.2
        isReady=$(kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.phase}')
        if [[ -z $isReady || $isReady != "Succeeded" ]]; then
            # Upgrade IBM Cert Manager/Licensing to $CS_OPERATOR_VERSION for $BAI_RELEASE_BASE upgrade        
            info "Upgrading IBM Cert Manager/Licensing operators to $CERT_LICENSE_CHANNEL_VERSION."
            $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
            
            
            # Upgrade CPFS from 23.0.1.X to $CS_OPERATOR_VERSION for $BAI_RELEASE_BASE upgrade
            isReadyCommonService=$(kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.phase}')
            if [[ -z $isReadyCommonService ]]; then
                if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
                    info "Upgrading/Switching the catalog of IBM foundation services to $TARGET_PROJECT_NAME."
                    $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --operator-namespace $TARGET_PROJECT_NAME --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog --license-accept
                    success "Upgraded/Switched the catalog of IBM foundation services to $TARGET_PROJECT_NAME."
                else
                    info "Upgrading IBM foundation services to $CS_OPERATOR_VERSION."
                    $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --operator-namespace $TARGET_PROJECT_NAME --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -n openshift-marketplace --license-accept
                fi
            fi
        fi

        # Check IBM Cloud Pak foundational services Operator $CS_OPERATOR_VERSION
        maxRetry=10
        echo "****************************************************************************"
        info "Checking for IBM Cloud Pak foundational operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.phase}')
            # isReady=$(kubectl exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine $BAI_RELEASE_BASE")
            if [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout Waiting for IBM Cloud Pak foundational operator to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "oc describe pod $(oc get pod -n $TARGET_PROJECT_NAME|grep ibm-common-service-operator|awk '{print $1}') -n $TARGET_PROJECT_NAME"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                echo "oc describe rs $(oc get rs -n $TARGET_PROJECT_NAME|grep ibm-common-service-operator|awk '{print $1}') -n $TARGET_PROJECT_NAME"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                pod_name=$(kubectl get pod -l=name=ibm-common-service-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM Cloud Pak foundational Operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM Cloud Pak foundational Operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"

        # Checking BAI stand-alone operator CSV
        # change this value for $BAI_RELEASE_BASE-IFIX
        target_csv_version=${BAI_CSV_VERSION//v/}
        for i in ${!sub_array[@]}; do
            if [[ ! -z "${sub_array[i]}" ]]; then
                if [[ ${sub_array[i]} = ibm-cp4a-operator* || ${sub_array[i]} = ibm-cp4a-wfps-operator* || ${sub_array[i]} = ibm-content-operator* || ${sub_array[i]} = icp4a-foundation-operator* || ${sub_array[i]} = ibm-pfs-operator* || ${sub_array[i]} = ibm-ads-operator* || ${sub_array[i]} = ibm-dpe-operator* || ${sub_array[i]} = ibm-odm-operator* || ${sub_array[i]} = ibm-insights-engine-operator* ]]; then
                info "Checking the channel of subsciption '${sub_array[i]}'!"
                currentChannel=$(kubectl get subscriptions.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -o 'jsonpath={.spec.channel}') >/dev/null 2>&1
                    if [[ "$currentChannel" == "v23.2" ]]
                    then
                        success "The channel of subsciption '${sub_array[i]}' is $currentChannel!"
                        printf "\n"
                        maxRetry=20
                        info "Waiting for the \"${sub_array[i]}\" subscription be upgraded to the ClusterServiceVersions(CSV) \"v$target_csv_version\""
                        for ((retry=0;retry<=${maxRetry};retry++)); do
                            current_version=$(kubectl get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                            installed_version=$(kubectl get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                            if [[ -z $current_version || -z $installed_version ]]; then
                                error "fail to get installed or current CSV, abort the upgrade procedure. Please check ${sub_array[i]} subscription status."
                                exit 1
                            fi
                            case "${sub_array[i]}" in
                            "ibm-cp4a-operator"*)
                                prefix_sub="ibm-cp4a-operator.v"
                                ;;
                            "ibm-cp4a-wfps-operator"*)
                                prefix_sub="ibm-cp4a-wfps-operator.v"
                                ;;
                            "ibm-content-operator"*)
                                prefix_sub="ibm-content-operator.v"
                                ;;
                            "icp4a-foundation-operator"*)
                                prefix_sub="icp4a-foundation-operator.v"
                                ;;
                            "ibm-pfs-operator"*)
                                prefix_sub="ibm-pfs-operator.v"
                                ;;
                            "ibm-ads-operator"*)
                                prefix_sub="ibm-ads-operator.v"
                                ;;
                            "ibm-dpe-operator"*)
                                prefix_sub="ibm-dpe-operator.v"
                                ;;
                            "ibm-odm-operator"*)
                                prefix_sub="ibm-odm-operator.v"
                                ;;
                            "ibm-insights-engine-operator"*)
                                prefix_sub="ibm-insights-engine-operator.v"
                                ;;
                            esac

                            current_version=${current_version#"$prefix_sub"}
                            installed_version=${installed_version#"$prefix_sub"}
                            if [[ $current_version != $installed_version || $current_version != $target_csv_version || $installed_version != $target_csv_version ]]; then
                                approval_mode=$(kubectl get subscription.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath={.spec.installPlanApproval})
                                if [[ $approval_mode == "Manual" ]]; then
                                    error "${sub_array[i]} subscription is set to Manual Approval mode, please approve installPlan to upgrade."
                                    exit 1
                                fi
                                if [[ $retry -eq ${maxRetry} ]]; then
                                    warning "Timeout waiting for upgrading \"${sub_array[i]}\" subscription from ${installed_version} to ${target_csv_version} under project \"$TARGET_PROJECT_NAME\""     
                                    break
                                else
                                    sleep 10
                                    echo -n "..."
                                    continue
                                fi 
                            else
                                success "${installed_version} is now the latest available version in ${currentChannel} channel."
                                break
                            fi
                        done

                    else
                        fail "Failed to update the channel of subsciption '${sub_array[i]}' to 23.2! exiting now..."
                        exit 1
                    fi
                fi
            else
                fail "No found subsciption '${sub_array[i]}'! exiting now..."
                exit 1
            fi
        done
        success "Completed to check the channel of subsciption for BAI stand-alone operators"

        info "Shutdown BAI stand-alone Operators before upgrade BAI stand-alone capabilities."
        shutdown_operator $TARGET_PROJECT_NAME
    fi
fi

if [ "$RUNTIME_MODE" == "upgradeOperatorStatus" ]; then
    info "Checking BAI stand-alone operators upgrade done or not"
    check_operator_status $TARGET_PROJECT_NAME "full" "channel"

    if [[ " ${CHECK_CP4BA_OPERATOR_RESULT[@]} " =~ "FAIL" ]]; then
        fail "Failed to upgrade BAI stand-alone operators"
    else
        success "CP4BA operators upgraded successfully!"
        info "All BAI stand-alone operators are shutting down before upgrade Zen/IM/CP4BA capabilities!"
        shutdown_operator $TARGET_PROJECT_NAME
        printf "\n"
        echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}: "
        msg "${YELLOW_TEXT}* Run the script in [upgradeDeployment] mode to upgrade the BAI stand-alone deployment when upgrade BAI stand-alone from 23.0.1.X to $BAI_RELEASE_BASE.${RESET_TEXT}"
        msg "# ./bai-deployment.sh -m upgradeDeployment -n $TARGET_PROJECT_NAME"
        msg "${YELLOW_TEXT}* Run the script in [upgradeDeploymentStatus] mode directly when upgrade BAI stand-alone from $BAI_RELEASE_BASE IFix to IFix.${RESET_TEXT}"
        msg "# ./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME"
    fi
fi

if [ "$RUNTIME_MODE" == "upgradeDeployment" ]; then
    project_name=$TARGET_PROJECT_NAME
    content_cr_name=$(kubectl get content -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $content_cr_name ]; then
        # info "Retrieving existing BAI stand-alone Content (Kind: content.icp4a.ibm.com) Custom Resource"
        cr_type="content"
        cr_metaname=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
        owner_ref=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.ownerReferences.[0].kind)
        if [[ ${owner_ref} != "ICP4ACluster" ]]; then
            cr_verison=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - spec.appVersion)
            if [[ $cr_verison == "${BAI_RELEASE_BASE}" ]]; then
                warning "The release version of content custom resource \"$content_cr_name\" is already \"$cr_verison\". Exit..."
                printf "\n"
                while true; do
                    printf "\x1B[1mDo you want to continue run upgrade? (Yes/No, default: No): \x1B[0m"
                    read -rp "" ans
                    case "$ans" in
                    "y"|"Y"|"yes"|"Yes"|"YES")
                        break
                        ;;
                    "n"|"N"|"no"|"No"|"NO"|"")
                        echo "Exiting..."
                        exit 1
                        ;;
                    *)
                        echo -e "Answer must be \"Yes\" or \"No\"\n"
                        ;;
                    esac
                done
            fi
        fi
    fi

    icp4acluster_cr_name=$(kubectl get icp4acluster -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $icp4acluster_cr_name ]; then
        cr_verison=$(kubectl get icp4acluster $icp4acluster_cr_name -n $project_name -o yaml | ${YQ_CMD} r - spec.appVersion)
        if [[ $cr_verison == "${BAI_RELEASE_BASE}" ]]; then
            warning "The release version of icp4acluster custom resource \"$icp4acluster_cr_name\" is already \"$cr_verison\"."
            printf "\n"
            while true; do
                printf "\x1B[1mDo you want to continue run upgrade? (Yes/No, default: No): \x1B[0m"
                read -rp "" ans
                case "$ans" in
                "y"|"Y"|"yes"|"Yes"|"YES")
                    break
                    ;;
                "n"|"N"|"no"|"No"|"NO"|"")
                    echo "Exiting..."
                    exit 1
                    ;;
                *)
                    echo -e "Answer must be \"Yes\" or \"No\"\n"
                    ;;
                esac
            done
        fi
    fi

    # info "Starting to upgrade BAI stand-alone Deployment..."
    # info "Incomming..."
    source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $TARGET_PROJECT_NAME
    # trap 'startup_operator $TARGET_PROJECT_NAME' EXIT
    # info "Checking BAI stand-alone operator and dependencies ready or not"
    # check_operator_status $TARGET_PROJECT_NAME
    # if [[ " ${CHECK_CP4BA_OPERATOR_RESULT[@]} " =~ "FAIL" ]]; then
    #     fail "CP4BA or dependency operaotrs is NOT ready all!"
    #     exit 1
    # else
    #     info "The BAI stand-alone and dependency operaotrs is ready for upgrade BAI stand-alone deployment!"
    # fi
    create_upgrade_property
    cs_dedicated=$(kubectl get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_DEDICATED_NAME} | awk '{print $1}')

    cs_shared=$(kubectl get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_SHARED_NAME} | awk '{print $1}')

    # For shared to shared, the common-service-maps be created under kube-public also.
    # So the script need to check structure of common-service-maps to decide this is shared or dedicated
    if [[ "$cs_dedicated" != "" && "$cs_shared" == ""  ]]; then
        UPGRADE_MODE="dedicated2dedicated"
        ${SED_COMMAND} "s|CS_OPERATOR_NAMESPACE=\"\"|CS_OPERATOR_NAMESPACE=\"$TARGET_PROJECT_NAME\"|g" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}
        ${SED_COMMAND} "s|CS_SERVICES_NAMESPACE=\"\"|CS_SERVICES_NAMESPACE=\"$TARGET_PROJECT_NAME\"|g" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}
    elif [[ "$cs_dedicated" != "" && "$cs_shared" != "" ]]; then
        kubectl get cm ${COMMON_SERVICES_CM_DEDICATED_NAME} --no-headers --ignore-not-found -n ${COMMON_SERVICES_CM_NAMESPACE} -o jsonpath='{ .data.common-service-maps\.yaml }' > /tmp/common-service-maps.yaml
        common_service_namespace=`cat /tmp/common-service-maps.yaml | ${YQ_CMD} r - namespaceMapping.[0].map-to-common-service-namespace`
        common_service_flag=`cat /tmp/common-service-maps.yaml | ${YQ_CMD} r - namespaceMapping.[1].map-to-common-service-namespace`
        if [[ -z $common_service_flag && $common_service_namespace == "ibm-common-services" ]]; then
            UPGRADE_MODE="shared2shared"
            ${SED_COMMAND} "s|CS_OPERATOR_NAMESPACE=\"\"|CS_OPERATOR_NAMESPACE=\"ibm-common-services\"|g" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}
            ${SED_COMMAND} "s|CS_SERVICES_NAMESPACE=\"\"|CS_SERVICES_NAMESPACE=\"ibm-common-services\"|g" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}
        elif [[ $common_service_flag != ""  ]]; then
            UPGRADE_MODE="shared2dedicated"
            ${SED_COMMAND} "s|CS_OPERATOR_NAMESPACE=\"\"|CS_OPERATOR_NAMESPACE=\"<cs_operators_namespace>\"|g" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}
            ${SED_COMMAND} "s|CS_SERVICES_NAMESPACE=\"\"|CS_SERVICES_NAMESPACE=\"<cs_services_namespace>\"|g" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}
            info "The property file is generated for upgrade under \"${UPGRADE_DEPLOYMENT_PROPERTY_FILE}\", you must input value for <cs_operators_namespace>/<cs_services_namespace>."
            read -rsn1 -p"[Press any key to continue after finish modify property]";echo
        fi
    fi

    upgrade_deployment $TARGET_PROJECT_NAME

    echo "${YELLOW_TEXT}[TIPS]${RESET_TEXT}"
    echo "* When run the script in [upgradeDeploymentStatus] mode, the script will detect the Zen/IM ready or not."
    echo "* After the Zen/IM ready, the script will start up all BAI stand-alone operators autmatically."
    printf "\n"
    echo "If the script run in [upgradeDeploymentStatus] mode for checking the Zen/IM timeout, you could check status follow below command."
    msgB "How to check zenService version manually: "
    echo "  # kubectl get zenService $(kubectl get zenService --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME |awk '{print $1}') --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.currentVersion}'"
    printf "\n"
    msgB "How to check zenService status and progress manually: "
    echo "  # kubectl get zenService $(kubectl get zenService --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME |awk '{print $1}') --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.zenStatus}'"
    echo "  # kubectl get zenService $(kubectl get zenService --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME |awk '{print $1}') --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.Progress}'"
    if [[ " ${existing_opt_component_list[@]}" =~ "bai" || " ${bai_flag}" == "true" ]]; then
        printf "\n"
        echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1;31mAFTER UPGRADE THIS BAI stand-alone DEPLOYMENT SUCCESSFULLY, PLEASE REMOVE \"recovery_path\" FROM CUSTOM RESOURCE UNDER \"bai_configuration\" MANUALLY.\x1B[0m"
    fi
fi

# the $BAI_RELEASE_BASE script without option upgradePrereqs
if [ "$RUNTIME_MODE" == "upgradePrereqs" ]; then
    # double check whether executed the cp4a-pre-upgrade-and-post-upgrade-optional.sh

    project_name=$TARGET_PROJECT_NAME
    UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/cp4ba-upgrade/project/$project_name
    UPGRADE_DEPLOYMENT_PROPERTY_FILE=${UPGRADE_DEPLOYMENT_FOLDER}/cp4ba_upgrade.property

    UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
    UPGRADE_DEPLOYMENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR}/backup

    UPGRADE_DEPLOYMENT_IAF_LOG_FOLDER=${UPGRADE_DEPLOYMENT_FOLDER}/log
    UPGRADE_DEPLOYMENT_IAF_LOG=${UPGRADE_DEPLOYMENT_IAF_LOG_FOLDER}/remove_iaf.log

    UPGRADE_DEPLOYMENT_CONTENT_CR=${UPGRADE_DEPLOYMENT_CR}/content.yaml
    UPGRADE_DEPLOYMENT_CONTENT_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.content_tmp.yaml
    UPGRADE_DEPLOYMENT_CONTENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/content_cr_backup.yaml

    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR=${UPGRADE_DEPLOYMENT_CR}/icp4acluster.yaml
    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.icp4acluster_tmp.yaml
    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/icp4acluster_cr_backup.yaml

    UPGRADE_DEPLOYMENT_BAI_TMP=${UPGRADE_DEPLOYMENT_CR}/.bai_tmp.yaml

    mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
    mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK} >/dev/null 2>&1
    info "Starting to execute scripts for upgradePrereqs BAI stand-alone Deployment..."

    cs_dedicated=$(kubectl get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_DEDICATED_NAME} | awk '{print $1}')

    cs_shared=$(kubectl get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_SHARED_NAME} | awk '{print $1}')

    if [[ "$cs_dedicated" != "" || "$cs_shared" != ""  ]] ; then
        control_namespace=$(kubectl get cm ${COMMON_SERVICES_CM_DEDICATED_NAME} --no-headers --ignore-not-found -n ${COMMON_SERVICES_CM_NAMESPACE} -o jsonpath='{ .data.common-service-maps\.yaml }' | grep  'controlNamespace' | cut -d':' -f2 )
        control_namespace=$(sed -e 's/^"//' -e 's/"$//' <<<"$control_namespace")
        control_namespace=$(sed "s/ //g" <<< $control_namespace)
    fi

    if [[ "$cs_dedicated" != "" && "$cs_shared" == ""  ]]; then
        UPGRADE_MODE="dedicated2dedicated"
    elif [[ "$cs_dedicated" != "" && "$cs_shared" != "" && "$control_namespace" != "" ]]; then
        kubectl get cm ${COMMON_SERVICES_CM_DEDICATED_NAME} --no-headers --ignore-not-found -n ${COMMON_SERVICES_CM_NAMESPACE} -o jsonpath='{ .data.common-service-maps\.yaml }' > /tmp/common-service-maps.yaml
        common_service_namespace=`cat /tmp/common-service-maps.yaml | ${YQ_CMD} r - namespaceMapping.[0].map-to-common-service-namespace`
        common_service_flag=`cat /tmp/common-service-maps.yaml | ${YQ_CMD} r - namespaceMapping.[1].map-to-common-service-namespace`
        if [[ -z $common_service_flag && $common_service_namespace == "ibm-common-services" ]]; then
            UPGRADE_MODE="shared2shared"
        elif [[ $common_service_flag != ""  ]]; then
            UPGRADE_MODE="shared2dedicated"
        else
            UPGRADE_MODE="dedicated2dedicated"
        fi
    elif [[ "$cs_dedicated" == "" && "$cs_shared" != ""  ]]; then
        # Dedicde upgrade mode by customer
        select_upgrade_mode
    fi

    if [[ "$cs_dedicated" != "" && "$cs_shared" == "" ]] || [[ "$cs_dedicated" != "" && "$cs_shared" != "" ]] || [[ "$cs_dedicated" == "" && "$cs_shared" != "" ]]; then 
        # check current cp4ba/content operator version
        check_cp4ba_operator_version $TARGET_PROJECT_NAME
        check_content_operator_version $TARGET_PROJECT_NAME
        if [[ "$cp4a_operator_csv_version" == "${BAI_CSV_VERSION//v/}" && "$cp4a_content_operator_csv_version" == "${BAI_CSV_VERSION//v/}"  ]]; then
            warning "The BAI stand-alone operator already is $BAI_CSV_VERSION."
            printf "\n"
            while true; do
                printf "\x1B[1mDo you want to continue run upgrade? (Yes/No, default: No): \x1B[0m"
                read -rp "" ans
                case "$ans" in
                "y"|"Y"|"yes"|"Yes"|"YES")
                    break
                    ;;
                "n"|"N"|"no"|"No"|"NO"|"")
                    echo "Exiting..."
                    exit 1
                    ;;
                *)
                    echo -e "Answer must be \"Yes\" or \"No\"\n"
                    ;;
                esac
            done
        fi
        if [[ "$cp4a_operator_csv_version" == "22.0.2" || "$cp4a_content_operator_csv_version" == "22.0.2" || "$cp4a_operator_csv_version" == "23.0.1" || "$cp4a_content_operator_csv_version" == "23.0.1" ]]; then
            project_name=$TARGET_PROJECT_NAME
            # Retrieve existing Content CR
            content_cr_name=$(kubectl get content -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
            if [ ! -z $content_cr_name ]; then
                cr_metaname=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
                owner_ref=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.ownerReferences.[0].kind)
                if [[ ${owner_ref} != "ICP4ACluster" ]]; then
                    CONTENT_CR_EXIST="Yes"
                fi
            fi
            # Retrieve existing ICP4ACluster CR
            icp4acluster_cr_name=$(kubectl get icp4acluster -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
            existing_pattern_list=""
            existing_opt_component_list=""
            EXISTING_PATTERN_ARR=()
            EXISTING_OPT_COMPONENT_ARR=()
            if [ ! -z $icp4acluster_cr_name ]; then
                cr_metaname=$(kubectl get icp4acluster $icp4acluster_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
                kubectl get icp4acluster $icp4acluster_cr_name -n $project_name -o yaml > ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP}
                existing_pattern_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
                existing_opt_component_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`
                OIFS=$IFS
                IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
                IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
                IFS=$OIFS
            fi
            if [[ $CONTENT_CR_EXIST == "Yes" || (" ${EXISTING_PATTERN_ARR[@]} " =~ "content") || (" ${EXISTING_PATTERN_ARR[@]} " =~ "workflow") || (" ${EXISTING_PATTERN_ARR[@]} " =~ "document_processing") || (" ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "baw_authoring") || (" ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "ae_data_persistence") ]]; then
                while true; do
                    printf "\n"
                    printf "\x1B[1mDid you execute the script \"cp4a-pre-upgrade-and-post-upgrade-optional.sh pre-upgrade\" before run bai-deployment.sh -m [upgradePrereqs]? (Yes/No, default: Yes): \x1B[0m"
                    read -rp "" ans
                    case "$ans" in
                    "y"|"Y"|"yes"|"Yes"|"YES"|"")
                        if [[ $UPGRADE_MODE == "dedicated2dedicated" ]]; then
                            iam_provider=$(kubectl get route cp-console-iam-provider --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o 'jsonpath={.metadata.name}') >/dev/null 2>&1
                            iam_idmgmt=$(kubectl get route cp-console-iam-idmgmt --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o 'jsonpath={.metadata.name}') >/dev/null 2>&1
                            if [[ "${iam_provider}" == "cp-console-iam-provider" && "${iam_idmgmt}" == "cp-console-iam-idmgmt" ]]; then
                                success "Found cp-console-iam-provider/cp-console-iam-idmgmt routes under project \"$TARGET_PROJECT_NAME\"."
                                break
                            else
                                warning "Not found cp-console-iam-provider/cp-console-iam-idmgmt routes under project \"$TARGET_PROJECT_NAME\", you need to run \"cp4a-pre-upgrade-and-post-upgrade-optional.sh pre-upgrade\" firstly"
                            fi
                        elif [[ $UPGRADE_MODE == "shared2shared" ]]; then
                            iam_provider=$(kubectl get route cp-console-iam-provider --no-headers --ignore-not-found -n ibm-common-services -o 'jsonpath={.metadata.name}') >/dev/null 2>&1
                            iam_idmgmt=$(kubectl get route cp-console-iam-idmgmt --no-headers --ignore-not-found -n ibm-common-services -o 'jsonpath={.metadata.name}') >/dev/null 2>&1
                            if [[ "${iam_provider}" == "cp-console-iam-provider" && "${iam_idmgmt}" == "cp-console-iam-idmgmt" ]]; then
                                success "Found cp-console-iam-provider/cp-console-iam-idmgmt routes under project \"ibm-common-services\"."
                                break
                            else
                                warning "Not found cp-console-iam-provider/cp-console-iam-idmgmt routes under project \"ibm-common-services\", you need to run \"cp4a-pre-upgrade-and-post-upgrade-optional.sh pre-upgrade\" firstly"
                            fi
                        fi
                        ;;
                    "n"|"N"|"no"|"No"|"NO")
                        info "\x1B[1mYou need to execute the script \"cp4a-pre-upgrade-and-post-upgrade-optional.sh pre-upgrade\" before run bai-deployment.sh -m [upgradePrereqs].\x1B[0m"
                        echo "Exiting..."
                        exit 1
                        ;;
                    *)
                        echo -e "Answer must be \"Yes\" or \"No\"\n"
                        ;;
                    esac
                done
            fi
        fi

        info "Scale down the BAI stand-alone Operator and other operators in the project \"$TARGET_PROJECT_NAME\"."
        shutdown_operator $TARGET_PROJECT_NAME

        # Retrieve existing Content CR for Create BAI save points
        info "Create the BAI savepoints for recovery path before upgrade CP4BA"
        mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
        mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
        content_cr_name=$(kubectl get content -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
        if [ ! -z $content_cr_name ]; then
            info "Retrieving existing BAI stand-alone Content (Kind: content.icp4a.ibm.com) Custom Resource"
            cr_type="content"
            cr_metaname=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
            owner_ref=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.ownerReferences.[0].kind)
            if [[ ${owner_ref} == "ICP4ACluster" ]]; then
                echo
            else
                kubectl get $cr_type $content_cr_name -n $project_name -o yaml > ${UPGRADE_DEPLOYMENT_CONTENT_CR_TMP}
                
                # Backup existing content CR
                mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK} >/dev/null 2>&1
                ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_CONTENT_CR_TMP} ${UPGRADE_DEPLOYMENT_CONTENT_CR_BAK}

                # Create BAI save points
                mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
                bai_flag=`cat $UPGRADE_DEPLOYMENT_CONTENT_CR_TMP | ${YQ_CMD} r - spec.content_optional_components.bai`
                if [[ $bai_flag == "True" || $bai_flag == "true" ]]; then
                    # Check the jq install on MacOS
                    if [[ "$machine" == "Mac" ]]; then
                        which jq &>/dev/null
                        [[ $? -ne 0 ]] && \
                        echo -e  "\x1B[1;31mUnable to locate an jq CLI. You must install it to run this script on MacOS.\x1B[0m" && \
                        exit 1                        
                    fi
                    rm -rf ${TEMP_FOLDER}/bai.json >/dev/null 2>&1
                    touch ${UPGRADE_DEPLOYMENT_BAI_TMP} >/dev/null 2>&1
                    info "Create the BAI savepoints for recovery path when merge custom resource"
                    # INSIGHTS_ENGINE_CR="iaf-insights-engine"
                    INSIGHTS_ENGINE_CR=$(kubectl get insightsengines --no-headers --ignore-not-found -n ${project_name} -o name)
                    if [[ -z $INSIGHTS_ENGINE_CR ]]; then
                        error "Not found insightsengines custom resource instance under project \"${project_name}\"."
                        exit 1
                    fi
                    MANAGEMENT_URL=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].uri}')
                    MANAGEMENT_AUTH_SECRET=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].authentication.secret.secretName}')
                    MANAGEMENT_USERNAME=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.data.username}' | base64 -d)
                    MANAGEMENT_PASSWORD=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.data.password}' | base64 -d)
                    
                    if [[ -z "$MANAGEMENT_URL" || -z "$MANAGEMENT_AUTH_SECRET" || -z "$MANAGEMENT_USERNAME" || -z "$MANAGEMENT_PASSWORD" ]]; then
                        error "Can not create the BAI savepoints for recovery path."
                        # exit 1
                    else
                        curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} "${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints" -o ${TEMP_FOLDER}/bai.json >/dev/null 2>&1

                        json_file_content="[]"
                        if [ "$json_file_content" == "$(cat ${TEMP_FOLDER}/bai.json)" ] ;then
                            fail "None return in \"${TEMP_FOLDER}/bai.json\" when request BAI savepoint through REST API: curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} \"${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints\" "
                            warning "Please fetch BAI savepoints for recovery path using above REST API manually, and then put JSON file (bai.json) under the directory \"${TEMP_FOLDER}/\""
                            read -rsn1 -p"Press any key to continue";echo
                        fi

                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-event-forwarder)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-event-forwarder |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.event-forwarder.recovery_path ${tmp_recovery_path}
                            success "Create savepoint for Event-forwarder: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.event-forwarder.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-content)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-content |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.content.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for Content: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.content.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-icm)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-icm |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.icm.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for ICM: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.icm.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-odm)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-odm |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.odm.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for ODM: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.odm.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bawadv)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bawadv |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bawadv.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for BAW ADV: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bawadv.recovery_path."
                        fi
                        if [[ "$machine" == "Mac" ]]; then
                            tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bpmn)
                        else                        
                            tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bpmn |cut -d':' -f2)
                        fi
                        tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                        
                        if [ ! -z "$tmp_recovery_path" ]; then
                            ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bpmn.recovery_path ${tmp_recovery_path}
                            success "Create BAI savepoint for BPMN: \"$tmp_recovery_path\""
                            info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bpmn.recovery_path."
                        fi
                    fi
                fi
            fi
        fi

        # Retrieve existing ICP4ACluster CR for Create BAI save points
        icp4acluster_cr_name=$(kubectl get icp4acluster -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
        if [ ! -z $icp4acluster_cr_name ]; then
            info "Retrieving existing BAI stand-alone ICP4ACluster (Kind: icp4acluster.icp4a.ibm.com) Custom Resource"
            cr_type="icp4acluster"
            cr_metaname=$(kubectl get icp4acluster $icp4acluster_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
            kubectl get $cr_type $icp4acluster_cr_name -n $project_name -o yaml > ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP}
            
            # Backup existing icp4acluster CR
            mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
            ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP} ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK}

            # Get EXISTING_PATTERN_ARR/EXISTING_OPT_COMPONENT_ARR
            existing_pattern_list=""
            existing_opt_component_list=""
            
            EXISTING_PATTERN_ARR=()
            EXISTING_OPT_COMPONENT_ARR=()
            existing_pattern_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
            existing_opt_component_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`

            OIFS=$IFS
            IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
            IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
            IFS=$OIFS

            # Create BAI save points
            mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
            if [[ (" ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "bai") ]]; then
                # Check the jq install on MacOS
                if [[ "$machine" == "Mac" ]]; then
                    which jq &>/dev/null
                    [[ $? -ne 0 ]] && \
                    echo -e  "\x1B[1;31mUnable to locate an jq CLI. You must install it to run this script on MacOS.\x1B[0m" && \
                    exit 1                        
                fi
                info "Create the BAI savepoints for recovery path when merge custom resource"
                rm -rf ${TEMP_FOLDER}/bai.json >/dev/null 2>&1
                touch ${UPGRADE_DEPLOYMENT_BAI_TMP} >/dev/null 2>&1
                # INSIGHTS_ENGINE_CR="iaf-insights-engine"
                INSIGHTS_ENGINE_CR=$(kubectl get insightsengines --no-headers --ignore-not-found -n ${project_name} -o name)
                if [[ -z $INSIGHTS_ENGINE_CR ]]; then
                    error "Not found insightsengines custom resource instance under project \"${project_name}\"."
                    exit 1
                fi
                MANAGEMENT_URL=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].uri}')
                MANAGEMENT_AUTH_SECRET=$(kubectl get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].authentication.secret.secretName}')
                MANAGEMENT_USERNAME=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.data.username}' | base64 -d)
                MANAGEMENT_PASSWORD=$(kubectl get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${project_name} -o jsonpath='{.data.password}' | base64 -d)
                if [[ -z "$MANAGEMENT_URL" || -z "$MANAGEMENT_AUTH_SECRET" || -z "$MANAGEMENT_USERNAME" || -z "$MANAGEMENT_PASSWORD" ]]; then
                    error "Can not create the BAI savepoints for recovery path."
                    # exit 1
                else
                    curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} "${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints" -o ${TEMP_FOLDER}/bai.json >/dev/null 2>&1

                    json_file_content="[]"
                    if [ "$json_file_content" == "$(cat ${TEMP_FOLDER}/bai.json)" ] ;then
                        fail "None return in \"${TEMP_FOLDER}/bai.json\" when request BAI savepoint through REST API: curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} \"${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints\" "
                        warning "Please fetch BAI savepoints for recovery path using above REST API manually, and then put JSON file (bai.json) under the directory \"${TEMP_FOLDER}/\""
                        read -rsn1 -p"Press any key to continue";echo
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-event-forwarder)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-event-forwarder |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.event-forwarder.recovery_path ${tmp_recovery_path}
                        success "Create savepoint for Event-forwarder: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.event-forwarder.recovery_path."
                    fi
                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-content)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-content |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.content.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for Content: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.content.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-icm)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-icm |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.icm.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for ICM: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.icm.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-odm)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-odm |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.odm.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for ODM: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.odm.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bawadv)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bawadv |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bawadv.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for BAW ADV: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bawadv.recovery_path."
                    fi

                    if [[ "$machine" == "Mac" ]]; then
                        tmp_recovery_path=$(cat ${TEMP_FOLDER}/bai.json | jq '.[].location' | grep bai-bpmn)
                    else                        
                        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${TEMP_FOLDER}/bai.json | grep bai-bpmn |cut -d':' -f2)
                    fi
                    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                    if [ ! -z "$tmp_recovery_path" ]; then
                        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bpmn.recovery_path ${tmp_recovery_path}
                        success "Create BAI savepoint for BPMN: \"$tmp_recovery_path\""
                        info "When run \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.bpmn.recovery_path."
                    fi
                fi
            fi
        fi

        cp4ba_cr_name=$(kubectl get icp4acluster -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')

        if [[ -z $cp4ba_cr_name ]]; then
            cp4ba_cr_name=$(kubectl get content -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')
            cr_type="contents.icp4a.ibm.com"
        else
            cr_type="icp4aclusters.icp4a.ibm.com"
        fi

        if [[ -z $cp4ba_cr_name ]]; then
            fail "Not found any custom resource for BAI stand-alone deployment under project \"$TARGET_PROJECT_NAME\", exit..."
            exit 1
        else
            cp4ba_cr_metaname=$(kubectl get $cr_type $cp4ba_cr_name -n $TARGET_PROJECT_NAME -o yaml | ${YQ_CMD} r - metadata.name)
        fi
        # # Get the control namespace for IBM Cloud Pak foundational services
        # while [[ $cs_control_project_name == "" ]] # While get slow storage clase name
        # do
        #     printf "\n"
        #     printf "\x1B[1mWhich is the control namespace for IBM Cloud Pak foundational services? (default: cs-control)\x1B[0m\n"
        #     read -p "Enter the name project (namespace): " cs_control_project_name
        #     if [ -z "$cs_control_project_name" ]; then
        #        cs_control_project_name="cs-control"
        #     fi
        #     crossplane_flag=$(kubectl -n $cs_control_project_name get subs,csv -o name --ignore-not-found|grep ibm-namespace-scope-operator)
        #     if [[ -z "$crossplane_flag" ]]; then
        #         echo -e "\x1B[1;31mEnter a valid project (namespace)\x1B[0m"
        #         cs_control_project_name=""
        #     fi
        # done

        # # Patch OLM CSV to remove IAF
        # info "Patching the CSV of IBM Business Automation Insights stand-alone (CP4BA)"
        # mkdir -p ${UPGRADE_TEMP_FOLDER} >/dev/null 2>&1
        # CP4BA_CSV_FILE=${UPGRADE_TEMP_FOLDER}/.cp4ba_csv.yaml
        # cp4ba_csv_array=()

        # csv_name=$(kubectl get csv -o name -n $TARGET_PROJECT_NAME|grep ibm-cp4a-operator)
        # if [[ ! -z $csv_name ]]; then
        #     kubectl get $csv_name -o yaml > $CP4BA_CSV_FILE
        #     item=0
        #     while true; do
        #         required_name=`cat $CP4BA_CSV_FILE | ${YQ_CMD} r - spec.customresourcedefinitions.required.[${item}].name`
        #         if [[ -z "$required_name" ]]; then
        #             break
        #         else
        #             if [[ $required_name == "automationbases.base.automation.ibm.com" || $required_name == "insightsengines.insightsengine.automation.ibm.com" ]]; then
        #                 cp4ba_csv_array=( "${cp4ba_csv_array[@]}" "${item}" )
        #             fi
        #             ((item++))
        #         fi
        #     done
        #     if (( ${#cp4ba_csv_array[@]} == 2 ));then
        #         kubectl patch $csv_name -n $TARGET_PROJECT_NAME --type=json -p '[{"op":"remove","path": "/spec/customresourcedefinitions/required/3",},{"op":"remove","path": "/spec/customresourcedefinitions/required/2",}]'
        #     fi
        # else
        #     fail "Not found CSV for ibm-cp4a-operator, exit..."
        #     exit 1
        # fi

        # Import upgrade upgrade_check_version.sh script
        source ${CUR_DIR}/helper/upgrade/upgrade_check_status.sh

        # Apply new catalogsources which includes CS $CS_OPERATOR_VERSION and BAI stand-alone before Change the channel to v23.1 for all BAI stand-alone operators ONLY.
        if kubectl get catalogsource -n openshift-marketplace | grep ibm-operator-catalog; then
            CATALOG_FOUND="Yes"
            PINNED="No"
            online_source="ibm-bai-operator"
        elif kubectl get catalogsource -n openshift-marketplace | grep ibm-cp4a-operator-catalog; then
            CATALOG_FOUND="Yes"
            PINNED="Yes"
            online_source="ibm-bai-operator"
        else
            CATALOG_FOUND="No"
            PINNED="Yes"
        fi

        # If catalog is non-pinned, and then apply new catalog source
        if [[ $CATALOG_FOUND == "Yes" ]]; then
            if [[ $PINNED == "Yes" ]]; then
                info "Found IBM BAI stand-alone operator catalog source, updating it ..."
                OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
                kubectl apply -f $OLM_CATALOG >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    success "IBM BAI stand-alone Operator Catalog source Updated!"
                else
                    fail "IBM BAI stand-alone Operator catalog source update failed"
                    exit 1
                fi
            fi
        else
            fail "Not found any catalog for IBM Business Automation Insights stand-alone (CP4BA)"
            exit 1
        fi

        info "Waiting for BAI stand-alone Operator Catalog pod initialization"
        maxRetry=30
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(kubectl get pod -l=olm.catalogSource=ibm-cp4a-operator-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
            if [[ -z $isReady ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                echo "Timeout Waiting for  BAI stand-alone Operator Catalog pod to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd: \x1B[0m"
                echo "kubectl describe pod $(kubectl get pod -n openshift-marketplace|grep $online_source|awk '{print $1}') -n openshift-marketplace"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            else
                printf "\n"
                success "CP4BA Operator Catalog is updated"
                info "Pod: $isReady"
                break
            fi
        done

        if [[ $(kubectl get og -n "${TARGET_PROJECT_NAME}" -o=go-template --template='{{len .items}}' ) -gt 0 ]]; then
            echo "Found operator group"
            kubectl get og -n "${TARGET_PROJECT_NAME}"
        else
            sed "s/REPLACE_NAMESPACE/$TARGET_PROJECT_NAME/g" ${OLM_OPT_GROUP} > ${OLM_OPT_GROUP_TMP}
            kubectl apply -f ${OLM_OPT_GROUP_TMP} -n $NAMESPACE
            if [ $? -eq 0 ]
                then
                echo "CP4BA Operator Group Created!"
            else
                echo "CP4BA Operator Operator Group creation failed"
            fi
        fi

        # Patch BAI stand-alone channel to v23.1, wait for all the operators (except cp4ba) are upgraded before applying operandRequest.
        sub_inst_list=$(kubectl get subscriptions.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-cp4a-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
        if [[ -z $sub_inst_list ]]; then
            fail "Not found any existing BAI stand-alone subscriptions (version 23.1), exiting ..."
            exit 1
        fi
        sub_array=($sub_inst_list)
        for i in ${!sub_array[@]}; do
            if [[ ! -z "${sub_array[i]}" ]]; then
                if [[ ${sub_array[i]} = ibm-cp4a-operator* || ${sub_array[i]} = ibm-cp4a-wfps-operator* || ${sub_array[i]} = ibm-content-operator* || ${sub_array[i]} = icp4a-foundation-operator* || ${sub_array[i]} = ibm-pfs-operator* || ${sub_array[i]} = ibm-ads-operator* || ${sub_array[i]} = ibm-dpe-operator* || ${sub_array[i]} = ibm-odm-operator* || ${sub_array[i]} = ibm-insights-engine-operator* ]]; then
                    kubectl patch subscriptions.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -p '{"spec":{"channel":"v23.2"}}' --type=merge >/dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        info "Updated the channel of subsciption '${sub_array[i]}' to 23.2!"
                        printf "\n"
                    else
                        fail "Failed to update the channel of subsciption '${sub_array[i]}' to 23.2! exiting now..."
                        exit 1
                    fi
                fi
            else
                fail "No found subsciption '${sub_array[i]}'! exiting now..."
                exit 1
            fi
        done

        success "Completed to switch the channel of subsciption for BAI stand-alone operators"

        info "Checking BAI stand-alone operator upgrade done or not"
        check_operator_status $TARGET_PROJECT_NAME
        if [[ " ${CHECK_CP4BA_OPERATOR_RESULT[@]} " =~ "FAIL" ]]; then
            fail "Fail to upgrade BAI stand-alone operators!"
        else
            success "CP4BA operators upgraded successfully!"

            # Scale down BAI stand-alone Operators before remove IAF
            printf "\n"
            msgB "Scale down the BAI stand-alone Operator and other operators in the project \"$TARGET_PROJECT_NAME\"."
            shutdown_operator $TARGET_PROJECT_NAME
        fi

        # double check cp4a-operator channel 23.1
        maxRetry=10
        echo "****************************************************************************"
        info "Checking for IBM Business Automation Insights stand-alone (CP4BA) multi-pattern operator channel"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(kubectl get csv $(kubectl get csv --no-headers --ignore-not-found -n $project_name | grep ibm-cp4a-operator.v |awk '{print $1}') --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.metadata.annotations.operatorChannel}')
            # isReady=$(kubectl exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine $BAI_RELEASE_BASE")
            if [[ $isReady == "v22.2" || $isReady == "v23.1" ]]; then
                success "IBM Business Automation Insights stand-alone (CP4BA) multi-pattern Operator's channel is \"$isReady\"!"
                break
            elif [[ $isReady != "v22.2" && $isReady != "v23.1" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    printf "\n"
                    warning "Timeout Waiting for IBM Business Automation Insights stand-alone (CP4BA) multi-pattern operator to start"
                    echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                    echo "oc describe pod $(oc get pod -n $TARGET_PROJECT_NAME|grep ibm-cp4a-operator|awk '{print $1}') -n $project_name"
                    printf "\n"
                    echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                    echo "oc describe rs $(oc get rs -n $TARGET_PROJECT_NAME|grep ibm-cp4a-operator|awk '{print $1}') -n $project_name"
                    printf "\n"
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        done
        echo "****************************************************************************"
        
        # if cp4a-operator pod still existing, try to kill it
        if [[ $isReady == "v22.2" ]]; then
            temp_ver="22.0.2"
        elif [[ $isReady == "v23.1" ]]; then
            temp_ver="23.0.1"
        elif [[ $isReady == "v23.2" ]]; then
            temp_ver=$BAI_RELEASE_BASE
        fi
        for ((retry=0;retry<=${maxRetry};retry++)); do
            pod_name=$(kubectl get pod -l=name=ibm-cp4a-operator,release=$temp_ver -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | awk '{print $1}')

            if [ -z $pod_name ]; then
                success "IBM Business Automation Insights stand-alone (CP4BA) multi-pattern Operator pod is shutdown successfully"
                break
            else
                error "IBM Business Automation Insights stand-alone (CP4BA) multi-pattern Operator is still running"
                info "Pod: $pod_name"
                
                # try to kill cp4a-operator pod
                info "Scaling down \"IBM Business Automation Insights stand-alone (CP4BA) multi-pattern\" operator"
                kubectl scale --replicas=0 deployment ibm-cp4a-operator -n $TARGET_PROJECT_NAME >/dev/null 2>&1
                sleep 1
                echo "Done!"
                kubectl delete pod $(kubectl get pod -l=name=ibm-cp4a-operator,release=$temp_ver -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name' --no-headers --ignore-not-found)  -n $TARGET_PROJECT_NAME --grace-period=0 --force >/dev/null 2>&1
                sleep 30
            fi
        done

        # info "Starting to remove IAF components from BAI stand-alone deployment under project \"$TARGET_PROJECT_NAME\"."
        mkdir -p $UPGRADE_DEPLOYMENT_IAF_LOG_FOLDER >/dev/null 2>&1
        # if [[ ! -z "$cp4ba_cr_metaname" ]]; then
        #     source ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $TARGET_PROJECT_NAME "icp4ba" "client" > $UPGRADE_DEPLOYMENT_IAF_LOG
        # fi
        # Validate if Cartridge , AutomationBase exists in this namespace
        # cp4ba_cartridge=$(kubectl get Cartridge.core.automation.ibm.com/icp4ba -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')
        
        # cp4ba_automationbase=$(kubectl get AutomationBase.base.automation.ibm.com/foundation-iaf -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}')
        # if [[ -z "$cp4ba_cartridge" && -z "$cp4ba_automationbase" ]]; then
        
        # Validate if iaf-core-operator , iaf-operator exists in this namespace
        iaf_core_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-core-operator,app.kubernetes.io/instance=iaf-core-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        iaf_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-operator,app.kubernetes.io/instance=iaf-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        # if [[ ( -z "$iaf_core_operator_pod_name") && ( -z "$iaf_operator_pod_name") ]]; then
        #     success "Not found IAF Core Operator/IAF Operator in the project \"$TARGET_PROJECT_NAME\""
        # else
        #     # remove IAF components from BAI stand-alone deployment 
        #     if [[ ! -z "$cp4ba_cr_metaname" ]]; then
        #         # # dry run to record the cmd: remove IAF components from BAI stand-alone deployment
        #         # echo "****************** Dry run log for removal IAF ******************" > $UPGRADE_DEPLOYMENT_IAF_LOG
        #         # source ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $control_namespace "icp4ba" "client" >> $UPGRADE_DEPLOYMENT_IAF_LOG
        #         # Excute IAF remove script
        #         echo "****************** Execution log for removal IAF ******************" >> $UPGRADE_DEPLOYMENT_IAF_LOG
        #         source ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $control_namespace "icp4ba" "none" >> $UPGRADE_DEPLOYMENT_IAF_LOG
        #         info "The log of removal IBM Automation Foundation is $UPGRADE_DEPLOYMENT_IAF_LOG"
        #     fi
        # fi

        # Check IAF operator already removed
        # info "Checking if IAF components be removed from the project \"$TARGET_PROJECT_NAME\""
        # maxRetry=10
        # for ((retry=0;retry<=${maxRetry};retry++)); do
        #     iaf_core_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-core-operator,app.kubernetes.io/instance=iaf-core-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        #     iaf_operator_pod_name=$(kubectl get pod -l=app.kubernetes.io/name=iaf-operator,app.kubernetes.io/instance=iaf-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')

        #     # if [[ -z $isReadyWebhook || -z $isReadyCertmanager || -z $isReadyCainjector || -z $isReadyCertmanagerOperator ]]; then
        #     if [[ (! -z $iaf_core_operator_pod_name) || (! -z $iaf_operator_pod_name) ]]; then
        #         if [[ $retry -eq ${maxRetry} ]]; then
        #             printf "\n"
        #             warning "Timeout Waiting for IBM Automation Foundation be removed from the project \"$TARGET_PROJECT_NAME\""
        #             echo -e "\x1B[1mPlease remove IAF manually with cmd: \"${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $control_namespace \"icp4ba\" \"none\"\"\x1B[0m"
        #             exit 1
        #         else
        #             sleep 30
        #             echo -n "..."
        #             continue
        #         fi
        #     else
        #         success "IBM Automation Foundation was removed successfully!"
        #         break
        #     fi
        # done


        # Check ibm-bts-operator/cloud-native-postgresql version
        if [[ $UPGRADE_MODE == "dedicated2dedicated"  ]]; then
            target_namespace="$TARGET_PROJECT_NAME"
        elif [[ $UPGRADE_MODE == "shared2shared" || $UPGRADE_MODE == "shared2dedicated" ]]; then
            target_namespace="ibm-common-services"
        fi
        cloud_native_postgresql_flag=$(kubectl get subscriptions.operators.coreos.com cloud-native-postgresql --no-headers --ignore-not-found -n $target_namespace | wc -l)
        ibm_bts_operator_flag=$(kubectl get subscriptions.operators.coreos.com ibm-bts-operator --no-headers --ignore-not-found -n $target_namespace | wc -l)
        maxRetry=20
        if [ $cloud_native_postgresql_flag -ne 0 ]; then
            info "Checking the version of subsciption 'cloud-native-postgresql' under project \"$target_namespace\""
            sleep 60
            for ((retry=0;retry<=${maxRetry};retry++)); do
                current_version_postgresql=$(kubectl get subscriptions.operators.coreos.com cloud-native-postgresql --no-headers --ignore-not-found -n $target_namespace -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                installed_version_postgresql=$(kubectl get subscriptions.operators.coreos.com cloud-native-postgresql --no-headers --ignore-not-found -n $target_namespace -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                prefix_postgresql="cloud-native-postgresql.v"
                current_version_postgresql=${current_version_postgresql#"$prefix_postgresql"}
                installed_version_postgresql=${installed_version_postgresql#"$prefix_postgresql"}
                # REQUIREDVER_POSTGRESQL="1.18.5"
                if [[ (! "$(printf '%s\n' "$REQUIREDVER_POSTGRESQL" "$current_version_postgresql" | sort -V | head -n1)" = "$REQUIREDVER_POSTGRESQL") || (! "$(printf '%s\n' "$REQUIREDVER_POSTGRESQL" "$installed_version_postgresql" | sort -V | head -n1)" = "$REQUIREDVER_POSTGRESQL") ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        info "Timeout Checking for the version of cloud-native-postgresql subscription under project \"$target_namespace\""
                        cloud_native_postgresql_ready="No"
                        break
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi         
                else
                    success "The version of subsciption 'cloud-native-postgresql' is v$current_version_postgresql."
                    cloud_native_postgresql_ready="Yes"
                    break
                fi
            done
        fi

        if [ $ibm_bts_operator_flag -ne 0 ]; then
            info "Checking the version of subsciption 'ibm-bts-operator' under project \"$target_namespace\""
            for ((retry=0;retry<=${maxRetry};retry++)); do
                current_version_bts=$(kubectl get subscriptions.operators.coreos.com ibm-bts-operator --no-headers --ignore-not-found -n $target_namespace -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                installed_version_bts=$(kubectl get subscriptions.operators.coreos.com ibm-bts-operator --no-headers --ignore-not-found -n $target_namespace -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                prefix_bts="ibm-bts-operator.v"
                current_version_bts=${current_version_bts#"$prefix_bts"}
                installed_version_bts=${installed_version_bts#"$prefix_bts"}
                # REQUIREDVER_BTS="3.28.0"
                if [[ (! "$(printf '%s\n' "$REQUIREDVER_BTS" "$current_version_bts" | sort -V | head -n1)" = "$REQUIREDVER_BTS") || (! "$(printf '%s\n' "$REQUIREDVER_BTS" "$installed_version_bts" | sort -V | head -n1)" = "$REQUIREDVER_BTS") ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        info "Timeout Checking for the version of ibm-bts-operator subscription under project \"$target_namespace\""
                        ibm_bts_operator_ready="No"
                        break
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi         
                else
                    success "The version of subsciption 'ibm-bts-operator' is v$current_version_bts."
                    ibm_bts_operator_ready="Yes"
                    break
                fi
            done
        fi

        if [[ ("$ibm_bts_operator_ready" == "Yes" && "$cloud_native_postgresql_ready" == "Yes") || ("$cloud_native_postgresql_flag" == "0" && "$ibm_bts_operator_flag" == "0") ]]; then
            if [[ $UPGRADE_MODE == "dedicated2dedicated" ]]; then
                printf "\n"
                echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}: How to upgrade the IBM Cloud Pak foundational services before upgrading BAI stand-alone deployed capabilities."
                msgB "1. Remove IAF components using the below command before upgrade IBM Cloud Pak foundational services to $CS_OPERATOR_VERSION :"
                echo "   # ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $control_namespace \"icp4ba\" \"none\""
                msgB "2. Upgrade IBM Cloud Pak foundational services to $CS_OPERATOR_VERSION using the below command: "                
                echo "   # $COMMON_SERVICES_SCRIPT_FOLDER/migrate_tenant.sh --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TARGET_PROJECT_NAME --cert-manager-source ibm-cert-manager-catalog --enable-licensing true --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --license-accept"
                msgB "3. Check the version of IBM Cloud Pak foundational services operator."
                echo "   # kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.spec.version}'"
                echo "   # kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.phase}'"
                echo "${YELLOW_TEXT}[TIPS]${RESET_TEXT}:"
                msgB "If you find IAF components still existing, you could remove it manually."
                msgB "${YELLOW_TEXT}* How to check whether IAF components is removed or not.${RESET_TEXT}"
                echo "  # kubectl get pod -l=app.kubernetes.io/name=iaf-operator,app.kubernetes.io/instance=iaf-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name' --no-headers | head -1"
                msgB "${RED_TEXT}* If above command return iaf-operator pod name, you could run below command to remove IAF components manually.${RESET_TEXT}"
                echo "  # ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME $control_namespace \"icp4ba\" \"none\""
            elif [[ $UPGRADE_MODE == "shared2shared" ]]; then
                printf "\n"
                echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}: How to upgrade the IBM Cloud Pak foundational services before upgrading BAI stand-alone deployed capabilities."
                msgB "1. Remove IAF components using the below command before upgrade IBM Cloud Pak foundational services to $CS_OPERATOR_VERSION :"
                echo "   # ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME ibm-common-services \"icp4ba\" \"none\""
                msgB "2. Upgrade IBM Cloud Pak foundational services to $CS_OPERATOR_VERSION using the below command: "
                echo "   # $COMMON_SERVICES_SCRIPT_FOLDER/migrate_tenant.sh --operator-namespace ibm-common-services --cert-manager-source ibm-cert-manager-catalog --enable-licensing true --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --license-accept"
                msgB "3. Check the version of IBM Cloud Pak foundational services operator."
                echo "   # kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n ibm-common-services -o jsonpath='{.spec.version}'"
                echo "   # kubectl get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n ibm-common-services -o jsonpath='{.status.phase}'"
                echo "${YELLOW_TEXT}[TIPS]${RESET_TEXT}:"
                msgB "If you find IAF components still existing, you could remove it manually."
                msgB "${YELLOW_TEXT}* How to check whether IAF components is removed or not.${RESET_TEXT}"
                echo "  # kubectl get pod -l=app.kubernetes.io/name=iaf-operator,app.kubernetes.io/instance=iaf-operator -n $TARGET_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name' --no-headers | head -1"
                msgB "${RED_TEXT}* If above command return iaf-operator pod name, you could run below command to remove IAF components manually.${RESET_TEXT}"
                echo "  # ${CUR_DIR}/helper/upgrade/remove_iaf.sh $cr_type $cp4ba_cr_metaname $TARGET_PROJECT_NAME ibm-common-services \"icp4ba\" \"none\""
            fi
        else
            fail "cloud-native-postgresql or ibm-bts-operator were not upgraded as expected! exiting..."
        fi
    else
        fail "Not found the working mode of IBM Cloud Pak foundational services, exiting ..."
        exit 1
    fi
fi

if [[ "$RUNTIME_MODE" == "upgradeDeploymentStatus" ]]; then
    project_name=$TARGET_PROJECT_NAME
    content_cr_name=$(kubectl get content -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [[ ! -z $content_cr_name ]]; then
        # info "Retrieving existing BAI stand-alone Content (Kind: content.icp4a.ibm.com) Custom Resource"
        cr_type="content"
        cr_metaname=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
        owner_ref=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.ownerReferences.[0].kind)
        if [[ "$owner_ref" != "ICP4ACluster" ]]; then
            kubectl scale --replicas=1 deployment ibm-content-operator -n $project_name >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                sleep 1
            else
                fail "Failed to scale up \"IBM BAI stand-alone FileNet Content Manager\" operator"
            fi
            kubectl scale --replicas=1 deployment icp4a-foundation-operator -n $project_name >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                sleep 1
            else
                fail "Failed to scale up \"IBM BAI stand-alone Foundation\" operator"
            fi
            cr_verison=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - spec.appVersion)
            if [[ $cr_verison != "${BAI_RELEASE_BASE}" ]]; then
                fail "The release version: \"$cr_verison\" in content custom resource \"$content_cr_name\" is not correct, please apply new version of CR firstly."
                exit 1
            fi
        fi
    fi

    icp4acluster_cr_name=$(kubectl get icp4acluster -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $icp4acluster_cr_name ]; then
        kubectl scale --replicas=1 deployment ibm-cp4a-operator -n $project_name >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            sleep 1
        else
            fail "Failed to scale up \"IBM Business Automation Insights stand-alone (CP4BA) multi-pattern\" operator"
        fi
        cr_verison=$(kubectl get icp4acluster $icp4acluster_cr_name -n $project_name -o yaml | ${YQ_CMD} r - spec.appVersion)
        if [[ $cr_verison != "${BAI_RELEASE_BASE}" ]]; then
            fail "The release version: \"$cr_verison\" in icp4acluster custom resource \"$icp4acluster_cr_name\" is not correct, please apply new version of CR firstly."
            exit 1
        fi
    fi

    while true; do
        clear
        isReady_cp4ba=$(kubectl get configmap ibm-cp4ba-shared-info --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.data.cp4ba_operator_of_last_reconcile}')
        isReady_foundation=$(kubectl get configmap ibm-cp4ba-shared-info --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.data.foundation_operator_of_last_reconcile}')
        if [[ -z "$isReady_cp4ba" && -z "$isReady_foundation" ]]; then
            CP4BA_DEPLOYMENT_STATUS="Getting Upgrade Status ..."
            printf '%s %s\n' "$(date)" "[refresh interval: 30s]"
            echo -en "[Press Ctrl+C to exit] \t\t"
            printHeaderMessage "CP4BA Upgrade Status"
            echo -en "${GREEN_TEXT}$CP4BA_DEPLOYMENT_STATUS${RESET_TEXT}"
            sleep 30
        else
            break
        fi
    done

   # check for zenStatus and currentverison for zen
    
    zen_service_name=$(kubectl get zenService --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME |awk '{print $1}')
    if [[ ! -z "$zen_service_name" ]]; then
        clear
        maxRetry=60
        for ((retry=0;retry<=${maxRetry};retry++)); do
            zenservice_version=$(kubectl get zenService $zen_service_name --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.currentVersion}')
            isCompleted=$(kubectl get zenService $zen_service_name --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.zenStatus}')
            isProgressDone=$(kubectl get zenService $zen_service_name --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath='{.status.Progress}')

            if [[ "$isCompleted" != "Completed" || "$isProgressDone" != "100%" || "$zenservice_version" != "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                clear
                CP4BA_DEPLOYMENT_STATUS="Waiting for the zenService to be ready (could take up to 120 minutes) before upgrade the BAI stand-alone capabilities..."
                printf '%s %s\n' "$(date)" "[refresh interval: 60s]"
                echo -en "[Press Ctrl+C to exit] \t\t"
                printf "\n"
                echo "${YELLOW_TEXT}$CP4BA_DEPLOYMENT_STATUS${RESET_TEXT}"
                printHeaderMessage "CP4BA Upgrade Status"
                if [[ "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Version (${ZEN_OPERATOR_VERSION//v/})       : ${GREEN_TEXT}$zenservice_version${RESET_TEXT}"
                else
                    echo "zenService Version (${ZEN_OPERATOR_VERSION//v/})       : ${RED_TEXT}$zenservice_version${RESET_TEXT}"
                fi
                if [[ "$isCompleted" == "Completed" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Status (Completed)    : ${GREEN_TEXT}$isCompleted${RESET_TEXT}"
                else
                    echo "zenService Status (Completed)    : ${RED_TEXT}$isCompleted${RESET_TEXT}"
                fi

                if [[ "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Progress (100%)       : ${GREEN_TEXT}$isProgressDone${RESET_TEXT}"
                else
                    echo "zenService Progress (100%)       : ${RED_TEXT}$isProgressDone${RESET_TEXT}"
                fi
                sleep 60
            elif [[ "$isCompleted" == "Completed" && "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                break
            elif [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout Waiting for the Zen Service to start"
                echo -e "\x1B[1mPlease check the status of the Zen Service\x1B[0m"
                printf "\n"
                exit 1
            fi
        done
        clear
        # success "The Zen Service (${ZEN_OPERATOR_VERSION//v/}) is ready for CP4BA"
        CP4BA_DEPLOYMENT_STATUS="The Zen Service (${ZEN_OPERATOR_VERSION//v/}) is ready for CP4BA"
        printf '%s %s\n' "$(date)" "[refresh interval: 30s]"
        echo -en "[Press Ctrl+C to exit] \t\t"
        printf "\n"
        echo "${YELLOW_TEXT}$CP4BA_DEPLOYMENT_STATUS${RESET_TEXT}"
        info "Starting all BAI stand-alone Operators to upgrade BAI stand-alone capabilities"
        printHeaderMessage "CP4BA Upgrade Status"
        if [[ "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
            echo "zenService Version        : ${GREEN_TEXT}$zenservice_version${RESET_TEXT}"
        else
            echo "zenService Version        : ${RED_TEXT}$zenservice_version${RESET_TEXT}"
        fi
        if [[ "$isCompleted" == "Completed" ]]; then
            echo "zenService Status         : ${GREEN_TEXT}$isCompleted${RESET_TEXT}"
        else
            echo "zenService Status         : ${RED_TEXT}$isCompleted${RESET_TEXT}"
        fi

        if [[ "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
            echo "zenService Progress       : ${GREEN_TEXT}$isProgressDone${RESET_TEXT}"
        else
            echo "zenService Progress       : ${RED_TEXT}$isProgressDone${RESET_TEXT}"
        fi

        # start all BAI stand-alone operators after zen/im ready

        startup_operator $TARGET_PROJECT_NAME "silent"
        sleep 30
    else
        fail "No found the zenService under project \"$TARGET_PROJECT_NAME\", exit..."
        echo "****************************************************************************"
        exit 1
    fi
    
    # show_cp4ba_upgrade_status
    while true
    do
        printf '%s\n' "$(clear; show_cp4ba_upgrade_status)"
        sleep 30
    done
fi

if [ "$RUNTIME_MODE" == "upgradePostconfig" ]; then
    project_name=$TARGET_PROJECT_NAME
    UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/cp4ba-upgrade/project/$project_name
    UPGRADE_DEPLOYMENT_PROPERTY_FILE=${UPGRADE_DEPLOYMENT_FOLDER}/cp4ba_upgrade.property

    UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
    UPGRADE_DEPLOYMENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR}/backup

    UPGRADE_DEPLOYMENT_CONTENT_CR=${UPGRADE_DEPLOYMENT_CR}/content.yaml
    UPGRADE_DEPLOYMENT_CONTENT_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.content_tmp.yaml
    UPGRADE_DEPLOYMENT_CONTENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/content_cr_backup.yaml

    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR=${UPGRADE_DEPLOYMENT_CR}/icp4acluster.yaml
    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.icp4acluster_tmp.yaml
    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/icp4acluster_cr_backup.yaml
    
    mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
    mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK} >/dev/null 2>&1

    info "Starting to execute script for post BAI stand-alone upgrade"
    # Retrieve existing WfPSRuntime CR
    exist_wfps_cr_array=($(kubectl get WfPSRuntime -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | awk '{print $1}'))
    if [ ! -z $exist_wfps_cr_array ]; then
        for item in "${exist_wfps_cr_array[@]}"
        do
            info "Retrieving existing IBM BAI stand-alone Workflow Process Service (Kind: WfPSRuntime.icp4a.ibm.com) Custom Resource: \"${item}\""
            cr_type="WfPSRuntime"
            cr_metaname=$(kubectl get $cr_type ${item} -n $TARGET_PROJECT_NAME -o yaml | ${YQ_CMD} r - metadata.name)
            UPGRADE_DEPLOYMENT_WFPS_CR=${UPGRADE_DEPLOYMENT_CR}/wfps_${cr_metaname}.yaml
            UPGRADE_DEPLOYMENT_WFPS_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.wfps_${cr_metaname}_tmp.yaml
            UPGRADE_DEPLOYMENT_WFPS_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/wfps_cr_${cr_metaname}_backup.yaml

            kubectl get $cr_type ${item} -n $TARGET_PROJECT_NAME -o yaml > ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP}
            
            # Backup existing WfPSRuntime CR
            mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
            ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} ${UPGRADE_DEPLOYMENT_WFPS_CR_BAK}

            info "Merging existing IBM BAI stand-alone Workflow Process Service custom resource: \"${item}\" with new version ($BAI_RELEASE_BASE)"
            # Delete unnecessary section in CR
            ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} status
            ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} metadata.annotations
            ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} metadata.creationTimestamp
            ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} metadata.generation
            ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} metadata.resourceVersion
            ${YQ_CMD} d -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} metadata.uid

            # replace release/appVersion
            # ${SED_COMMAND} "s|release: .*|release: ${BAI_RELEASE_BASE}|g" ${UPGRADE_DEPLOYMENT_PFS_CR_TMP}
            ${SED_COMMAND} "s|appVersion: .*|appVersion: ${BAI_RELEASE_BASE}|g" ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP}

            # # change failureThreshold/periodSeconds for WfPS after upgrade
            # ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} spec.node.probe.startupProbe.failureThreshold 80
            # ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} spec.node.probe.startupProbe.periodSeconds 5

            ${SED_COMMAND} "s|'\"|\"|g" ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP}
            ${SED_COMMAND} "s|\"'|\"|g" ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP}

            
            success "Completed to merge existing IBM BAI stand-alone Workflow Process Service custom resource with new version ($BAI_RELEASE_BASE)"
            ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_WFPS_CR_TMP} ${UPGRADE_DEPLOYMENT_WFPS_CR}

            info "Apply the new version ($BAI_RELEASE_BASE) of IBM BAI stand-alone Workflow Process Service custom resource"
            kubectl annotate WfPSRuntime ${item} kubectl.kubernetes.io/last-applied-configuration- -n $TARGET_PROJECT_NAME >/dev/null 2>&1
            sleep 3
            kubectl apply -f ${UPGRADE_DEPLOYMENT_WFPS_CR} -n $TARGET_PROJECT_NAME >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                fail "IBM BAI stand-alone Workflow Process Service custom resource update failed"
                exit 1
            else
                echo "Done!"

                printf "\n"
                echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}:"
                msgB "Run \"bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME\" to get overview upgrade status for IBM BAI stand-alone Workflow Process Service"
            fi
        done
    fi

    # Retrieve existing Content CR for remove route cp-console-iam-provider/cp-console-iam-idmgmt
    content_cr_name=$(kubectl get content -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $content_cr_name ]; then
        info "Retrieving existing BAI stand-alone Content (Kind: content.icp4a.ibm.com) Custom Resource"
        cr_type="content"
        cr_metaname=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
        owner_ref=$(kubectl get content $content_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.ownerReferences.[0].kind)
        if [[ ${owner_ref} != "ICP4ACluster" ]]; then
            iam_idprovider=$(kubectl get route -n $project_name -o 'custom-columns=NAME:.metadata.name' --no-headers --ignore-not-found | grep cp-console-iam-provider)
            iam_idmgmt=$(kubectl get route -n $project_name -o 'custom-columns=NAME:.metadata.name' --no-headers --ignore-not-found | grep cp-console-iam-idmgmt)
            if [[ ! -z $iam_idprovider ]]; then
                info "Remove \"cp-console-iam-provider\" route from project \"$project_name\"."
                kubectl delete route $iam_idprovider -n $project_name >/dev/null 2>&1
            fi
            if [[ ! -z $iam_idmgmt ]]; then
                info "Remove \"cp-console-iam-idmgmt\" route from project \"$project_name\"."
                kubectl delete route $iam_idmgmt -n $project_name >/dev/null 2>&1
            fi
        fi
    fi
    # Retrieve existing ICP4ACluster CR for ADP post upgrade
    icp4acluster_cr_name=$(kubectl get icp4acluster -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $icp4acluster_cr_name ]; then
        info "Retrieving existing BAI stand-alone ICP4ACluster (Kind: icp4acluster.icp4a.ibm.com) Custom Resource"
        cr_type="icp4acluster"
        cr_metaname=$(kubectl get icp4acluster $icp4acluster_cr_name -n $project_name -o yaml | ${YQ_CMD} r - metadata.name)
        kubectl get $cr_type $icp4acluster_cr_name -n $project_name -o yaml > ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP}
        
        # Backup existing icp4acluster CR
        mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
        ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP} ${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK}

        # Get EXISTING_PATTERN_ARR/EXISTING_OPT_COMPONENT_ARR
        existing_pattern_list=""
        existing_opt_component_list=""
        
        EXISTING_PATTERN_ARR=()
        EXISTING_OPT_COMPONENT_ARR=()
        existing_pattern_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_deployment_patterns`
        existing_opt_component_list=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.sc_optional_components`

        OIFS=$IFS
        IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
        IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
        IFS=$OIFS
        if [[ (" ${EXISTING_PATTERN_ARR[@]} " =~ "document_processing") ]]; then
            aca_db_type=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.datasource_configuration.dc_ca_datasource.dc_database_type`
            aca_db_server=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.datasource_configuration.dc_ca_datasource.database_servername`
            aca_base_db=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.datasource_configuration.dc_ca_datasource.database_name`
            aca_tenant_db=()

            if [[ $aca_db_type == "db2" ]]; then
                # Get tenant_db list
                item=0
                while true; do
                    tenant_name=`cat $UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_TMP | ${YQ_CMD} r - spec.datasource_configuration.dc_ca_datasource.tenant_databases.[${item}]`
                    if [[ -z "$tenant_name" ]]; then
                        break
                    else
                        aca_tenant_db=( "${aca_tenant_db[@]}" "${tenant_name}" )
                        ((item++))
                    fi
                done

                # Convert aca_tenant_db array to list by common
                delim=""
                aca_tenant_db_joined=""
                for item in "${aca_tenant_db[@]}"; do
                    aca_tenant_db_joined="$aca_tenant_db_joined$delim$item"
                    delim=","
                done

                printf "\n"
                echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}: How to upgrading your Document Processing databases."
                msgB "1. ${YELLOW_TEXT}Update the base Db2 database:${RESET_TEXT}"
                echo "   * Database server is on AIX or Linux:"
                echo "     1. Copy \"${PARENT_DIR}/ACA/configuration-ha/DB2\" to database server \"$aca_db_server\""
                echo "     2. run \"${PARENT_DIR}/ACA/configuration-ha/DB2/UpgradeBaseDB.sh\" to update the base database \"$aca_base_db\""
                echo "   * Database server is on Microsoft Windows:"
                echo "     1. Copy \"${PARENT_DIR}/ACA/configuration-ha/DB2\" to database server \"$aca_db_server\""
                echo "     2. run \"${PARENT_DIR}/ACA/configuration-ha/DB2/UpgradeBaseDB.bat\" to update the base database \"$aca_base_db\""
                msgB "2. ${YELLOW_TEXT}Upgrade the tenant Db2 databases:${RESET_TEXT}"
                echo "   * Database server is on AIX or Linux:"
                echo "     1. Copy \"${PARENT_DIR}/ACA/configuration-ha/DB2\" to database server \"$aca_db_server\""
                echo "     2. run \"${PARENT_DIR}/ACA/configuration-ha/DB2/UpgradeTenantDB.sh\" to update the tenant database \"$aca_tenant_db_joined\""
                echo "   * Database server is on Microsoft Windows:"
                echo "     1. Copy \"${PARENT_DIR}/ACA/configuration-ha/DB2\" to database server \"$aca_db_server\""
                echo "     2. run \"${PARENT_DIR}/ACA/configuration-ha/DB2/UpgradeTenantDB.bat\" to update the tenant database \"$aca_tenant_db_joined\""
                msgB "For more information, check in  https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$BAI_RELEASE_BASE?topic=2302-upgrading-your-automation-document-processing-databases"
            fi
        fi

        # Remove cp-console-iam-provider/cp-console-iam-idmgmt
        if [[ (" ${EXISTING_PATTERN_ARR[@]} " =~ "document_processing") || (" ${EXISTING_PATTERN_ARR[@]} " =~ "content") || ("${EXISTING_OPT_COMPONENT_ARR[@]}" =~ "ae_data_persistence") || ("${EXISTING_OPT_COMPONENT_ARR[@]}" =~ "baw_authoring") ]]; then
            iam_idprovider=$(kubectl get route -n $project_name -o 'custom-columns=NAME:.metadata.name' --no-headers --ignore-not-found | grep cp-console-iam-provider)
            iam_idmgmt=$(kubectl get route -n $project_name -o 'custom-columns=NAME:.metadata.name' --no-headers --ignore-not-found | grep cp-console-iam-idmgmt)
            if [[ ! -z $iam_idprovider ]]; then
                info "Remove \"cp-console-iam-provider\" route from project \"$project_name\"."
                kubectl delete route $iam_idprovider -n $project_name >/dev/null 2>&1
            fi
            if [[ ! -z $iam_idmgmt ]]; then
                info "Remove \"cp-console-iam-idmgmt\" route from project \"$project_name\"."
                kubectl delete route $iam_idmgmt -n $project_name >/dev/null 2>&1
            fi
        fi
    fi
    success "Completed to execute script for post BAI stand-alone upgrade"
fi
