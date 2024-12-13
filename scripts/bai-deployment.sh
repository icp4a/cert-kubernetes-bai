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

FOUNDATION_CR_SELECTED=""
optional_component_arr=()
optional_component_cr_arr=()
foundation_component_arr=()

function prompt_license(){
    clear

    echo -e "\x1B[1;31mIMPORTANT: Review the IBM Business Automation Insights standalone license information here: \n\x1B[0m"
    echo -e "\x1B[1;31mhttps://www.ibm.com/support/customer/csol/terms/?id=L-YZSW-9CAE3A\n\x1B[0m"
    INSTALL_BAW_ONLY="No"


    read -rsn1 -p"Press any key to continue";echo

    printf "\n"
    while true; do
        printf "\x1B[1mDo you accept the IBM Business Automation Insights standalone license (Yes/No, default: No): \x1B[0m"

        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            echo -e "Starting to Install the IBM Business Automation Insights standalone Operator...\n"
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
        printf "\n"
        echo -e "\x1B[1mWhere do you want to deploy IBM Business Automation Insights standalone?\x1B[0m"
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

function select_profile_type(){
    printf "\n"
    COLUMNS=12
    echo -e "\x1B[1mPlease select the deployment profile (default: small).  Refer to the documentation in BAI standalone Knowledge Center for details on profile.\x1B[0m"
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
    echo -e "${YELLOW_TEXT}BAI standalone only supports production deployment${RESET_TEXT}"
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
        printf "\x1B[1mDo you want to restrict network egress to unknown external destination for this BAI standalone deployment?\x1B[0m ${YELLOW_TEXT}(Notes: BAI standalone $BAI_RELEASE_BASE prevents all network egress to unknown destinations by default. You can either (1) enable all egress or (2) accept the new default and create network policies to allow your specific communication targets as documented in the knowledge center.)${RESET_TEXT} (Yes/No, default: Yes): "
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
    fi
}

function select_ldap_user_for_zen(){
    printf "\n"
    LDAP_USER_NAME=""

    echo -e  "${YELLOW_TEXT}For BAI standalone, if you select LDAP, then provide one ldap user here for onborading ZEN.${RESET_TEXT}"    
    while [[ $LDAP_USER_NAME == "" ]] # While get medium storage clase name
    do
        printf "\x1B[1mplease enter one LDAP user for BAI standalone: \x1B[0m"
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
            printf "\x1B[1mYour OCP cluster has FIPS enabled, do you want to enable FIPS with this BAI standalone deployment？\x1B[0m (Yes/No, default: No): "
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
        # BAI standalone only support Production
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
    success "All values in the property file have been applied in the final CR under $FINAL_CR_FOLDER"
    msgB "Please confirm final custom resource under $FINAL_CR_FOLDER"
}

function select_private_catalog_bai(){
    printf "\n"
    echo "${YELLOW_TEXT}[NOTES] You can switch the BAI Standalone deployment as a private catalog (namespace scope) or keep the global catalog namespace (GCN). The private catalog (recommended) uses the same target namespace of the BAI Standalone deployment, the GCN uses the openshift-marketplace namespace.${RESET_TEXT}"

    while true; do
        printf "\x1B[1mDo you want to switch BAI Standalone deployment to use global catalog? (Yes/No, default: No): \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES"|"")
            ENABLE_PRIVATE_CATALOG=0
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")          
            ENABLE_PRIVATE_CATALOG=1
            break
            ;;
        *)
            PRIVATE_CATALOG=""
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
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

    # remove ldap_configuration when select LDAP is false for BAI standalone
    if [[ $SELECTED_LDAP == "No" ]]; then
        ${YQ_CMD} d -i ${BAI_PATTERN_FILE_TMP} spec.ldap_configuration
    fi

    ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_BAK}

    ${COPY_CMD} -rf ${BAI_PATTERN_FILE_TMP} ${BAI_PATTERN_FILE_FINAL}

    echo -e "\x1B[1mThe custom resource file used is: \"${BAI_PATTERN_FILE_FINAL}\"\x1B[0m"
    printf "\n"
    echo -e "\x1B[1mTo monitor the deployment status, follow the Operator logs.\x1B[0m"
    echo -e "\x1B[1mFor details, refer to the troubleshooting section in Knowledge Center here: \x1B[0m"
    echo -e "\x1B[1m https://www.ibm.com/docs/en/bai/$BAI_RELEASE_BASE?topic=troubleshooting \x1B[0m"
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

    echo -e "${YELLOW_TEXT}7. Target project for this BAI standalone deployment: ${RESET_TEXT}${TARGET_PROJECT_NAME}"

    echo -e "${YELLOW_TEXT}8. Restrict network egress or not for this BAI standalone deployment: ${RESET_TEXT}${RESTRICTED_INTERNET_ACCESS}"

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
    # scale up BAI standalone operators
    local project_name=$1
    local run_mode=$2  # silent
    info "Scaling up \"IBM Business Automation Insights standalone\" operator"
    kubectl scale --replicas=1 deployment ibm-bai-insights-engine-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM Business Automation Insights standalone\" operator"
    fi


    info "Scaling up \"IBM BAI standalone Foundation\" operator"
    kubectl scale --replicas=1 deployment ibm-bai-foundation-operator -n $project_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
        if [[ -z "$run_mode" ]]; then
            echo "Done!"
        fi
    else
        fail "Failed to scale up \"IBM BAI standalone Foundation\" operator"
    fi
}

function shutdown_operator(){
    # scale down BAI standalone operators
    local project_name=$1
    info "Scaling down \"IBM BAI standalone Insights Engine\" operator"
    kubectl scale --replicas=0 deployment ibm-bai-insights-engine-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"
    info "Scaling down \"IBM BAI standalone Foundation\" operator"
    kubectl scale --replicas=0 deployment ibm-bai-foundation-operator -n $project_name >/dev/null 2>&1
    sleep 1
    echo "Done!"
}

function create_project() {
    local project_name=$1
    project_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$project_name")

    isProjExists=`${CLI_CMD} get project $project_name --ignore-not-found | wc -l`  >/dev/null 2>&1

    if [ $isProjExists -ne 2 ] ; then
        oc new-project ${project_name} >/dev/null 2>&1
        returnValue=$?
        if [ "$returnValue" == 1 ]; then
            if [ -z "$BAI_AUTO_NAMESPACE" ]; then
                echo -e "\x1B[1;31mInvalid project name, please enter a valid name...\x1B[0m"
                project_name=""
                return 1
            else
                echo -e "\x1B[1;31mInvalid project name \"$BAI_AUTO_NAMESPACE\", please set a valid name...\x1B[0m"
                project_name=""
                exit 1
            fi
        else
            echo -e "\x1B[1mUsing project ${project_name}...\x1B[0m"
            return 0
        fi
    else
        echo -e "\x1B[1mProject \"${project_name}\" already exists! Continue...\x1B[0m"
        return 0
    fi
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
    echo "  -n  The target namespace of the BAI standalone operator and deployment."
    echo "  -i  Optional: Operator image name, by default it is cp.icr.io/cp/cp4a/icp4a-operator:$BAI_RELEASE_BASE"
    echo "  -p  Optional: Pull secret to use to connect to the registry, by default it is ibm-entitlement-key"
    echo "  --enable-private-catalog Optional: Set this flag to let the script to switch CatalogSource from global to namespace scoped. Default is in openshift-marketplace namespace"
    echo "  ${YELLOW_TEXT}* Running the script to create a custom resource file for new BAI standalone deployment:${RESET_TEXT}"
    echo "      - STEP 1: Run the script without any parameter."
    echo "  ${YELLOW_TEXT}* Running the script to upgrade a BAI standalone deployment from 23.0.1.X to $BAI_RELEASE_BASE GA/$BAI_RELEASE_BASE.X. You must run the modes in the following order:${RESET_TEXT}"
    echo "      - STEP 1: Run the script in [upgradeOperator] mode to upgrade the BAI standalone operator"
    echo "      - STEP 2: Run the script in [upgradeOperatorStatus] mode to check that the upgrade of the BAI standalone operator and its dependencies is successful."
    echo "      - STEP 3: Run the script in [upgradeDeployment] mode to upgrade the BAI standalone deployment."
    echo "      - STEP 4: Run the script in [upgradeDeploymentStatus] mode to check that the upgrade of the BAI standalone deployment is successful."
    echo "  ${YELLOW_TEXT}* Running the script to upgrade a BAI standalone deployment from $BAI_RELEASE_BASE GA/$BAI_RELEASE_BASE.X to $BAI_RELEASE_BASE.X. You must run the modes in the following order:${RESET_TEXT}"
    echo "      - STEP 1: Run the script in [upgradeOperator] mode to upgrade the BAI standalone operator"
    echo "      - STEP 2: Run the script in [upgradeOperatorStatus] mode to check that the upgrade of the BAI standalone operator and its dependencies is successful."
    echo "      - STEP 3: Run the script in [upgradeDeploymentStatus] mode to check that the upgrade of the BAI standalone deployment is successful."

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
        --original-bai-csv-ver)
            shift
            BAI_ORIGINAL_CSV_VERSION=$1
            ;;
        --cpfs-upgrade-mode)
            shift
            UPGRADE_MODE=$1
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
                    echo -e "\x1B[1mCreating the Custom Resource of the IBM Business Automation Insights standalone Operator...\x1B[0m"
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

                printf "\x1B[1mEnter the number from 1 to 9 that you want to change: \x1B[0m"

                read -rp "" ans
                case "$ans" in
                "1")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_platform
                    else
                        info "Please run bai-prerequisites.sh to modify the platform type"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "2")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_ldap_type
                    else
                        info "Please run bai-prerequisites.sh to modify the LDAP type"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "3")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_profile_type
                    else
                        info "Please run bai-prerequisites.sh to modify the profile size"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "4")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_iam_default_admin
                    else
                        info "Please run bai-prerequisites.sh to modify the IAM default admin"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "5"|"6")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        get_storage_class_name
                    else
                        info "Please run bai-prerequisites.sh to modify the storage class"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "7")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        TARGET_PROJECT_NAME=""
                        select_project
                    else
                        info "Please run bai-prerequisites.sh to modify the target project"
                        read -rsn1 -p"Press any key to continue";echo
                    fi
                    break
                    ;;
                "8")
                    if [[ $DEPLOYMENT_WITH_PROPERTY == "No" ]]; then
                        select_restricted_internet_access
                    else
                        info "Please run bai-prerequisites.sh to modify the storage class"
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
                    echo -e "\x1B[1mEnter a valid number [1 to 9] \x1B[0m"
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


# This runtime does the upgrade of BAI Standalone operators
if [ "$RUNTIME_MODE" == "upgradeOperator" ]; then
    info "Starting to upgrade BAI standalone operators and IBM foundation services"
    # check current bai operator version
    check_bai_operator_version $TARGET_PROJECT_NAME
    if [[ "$bai_operator_csv_version" == "${BAI_CSV_VERSION//v/}" ]]; then
        warning "The BAI standalone operator is already at $BAI_CSV_VERSION."
        printf "\n"
        while true; do
            printf "\x1B[1mDo you want to continue to run the upgrade? (Yes/No, default: No): \x1B[0m"
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
    # check if the deployment has seperate operators and operands
    check_bai_separate_operand $TARGET_PROJECT_NAME
    if [[ $SEPARATE_OPERAND_FLAG == "No" ]]; then

        BAI_SERVICES_NS=$TARGET_PROJECT_NAME
        bai_services_namespace=$TARGET_PROJECT_NAME
        bai_operators_namespace=$TARGET_PROJECT_NAME
    fi

    # ENV variables needed
    TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME
    UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/bai-upgrade/project/$BAI_SERVICES_NS
    UPGRADE_DEPLOYMENT_PROPERTY_FILE=${UPGRADE_DEPLOYMENT_FOLDER}/bai_upgrade.property

    UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
    UPGRADE_DEPLOYMENT_CR_BAK=${UPGRADE_DEPLOYMENT_CR}/backup

    UPGRADE_DEPLOYMENT_BAI_CR=${UPGRADE_DEPLOYMENT_CR}/insightsengine.yaml
    UPGRADE_DEPLOYMENT_BAI_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.insightsengine_tmp.yaml
    UPGRADE_DEPLOYMENT_BAI_CR_BAK=${UPGRADE_DEPLOYMENT_CR_BAK}/insightsengine_cr_backup.yaml
    RUN_BAI_SAVEPOINT="No"

    UPGRADE_DEPLOYMENT_BAI_TMP=${UPGRADE_DEPLOYMENT_CR}/.bai_tmp.yaml
    mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
    mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1

    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
        source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $BAI_SERVICES_NS
    else
        source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $TARGET_PROJECT_NAME
    fi

    
    info "Starting to upgrade BAI Standalone operators and IBM Cloud Pak foundational services"
    # bai_operator_csv_version is set from the check_bai_operator_version function
    if [[ "$bai_operator_csv_version" == "${BAI_CSV_VERSION//v/}" ]]; then
        warning "The ClusterServiceVersion (CSV) of BAI Standalone operator already is $BAI_CSV_VERSION."
        printf "\n"
        while true; do
            printf "\n"
            printf "\x1B[1mDo you want to continue to do upgrade? (Yes/No, default: No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again."
                echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                echo "           Usage:"
                echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.1.0] for 24.1.0 GA"
                echo "           Example command: "
                echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.1.0${RESET_TEXT}"
                exit 1
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

    PLATFORM_SELECTED=$(eval echo $(kubectl get insightsengine $(kubectl get insightsengine --no-headers --ignore-not-found -n $BAI_SERVICES_NS | grep NAME -v | awk '{print $1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o yaml | grep sc_deployment_platform | tail -1 | cut -d ':' -f 2))
    if [[ -z $PLATFORM_SELECTED ]]; then
        fail "Not found any custom resource for BAI standalone under project \"$BAI_SERVICES_NS\", exiting"
        exit 1
    fi

    # Currently no support for this platform type but this condition has been kept in case this script has to be enhanced
    if [[ "$PLATFORM_SELECTED" == "others" ]]; then
        #[ -f ${UPGRADE_DEPLOYMENT_FOLDER}/upgradeOperator.yaml ] && rm ${UPGRADE_DEPLOYMENT_FOLDER}/upgradeOperator.yaml
        #cp ${CUR_DIR}/../descriptors/operator.yaml ${UPGRADE_DEPLOYMENT_FOLDER}/upgradeOperator.yaml
        #cncf_install
        fail "Upgraded Not support for Platform type \"$BAI_SERVICES_NS\", exiting"
        exit
    else
        info "Checking ibm-bai-shared-info configMap existing or not in the project \"$BAI_SERVICES_NS\""
        ibm_bai_shared_info_cm=$(${CLI_CMD} get configmap ibm-bai-shared-info --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.data.bai_operator_of_last_reconcile}')
        
        # Create ibm-bai-shared-info configMap if it doesn't exist
        insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
        if [[ ! -z $insightsengine_cr_name ]]; then
            cr_version=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - spec.appVersion)
            cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
            cr_uid=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.uid)
            if [[ -z $ibm_bai_shared_info_cm ]]; then
                info "ibm-bai-shared-info configMap was not found,the script will now create it."
                create_ibm_bai_shared_info_cm_yaml
                ${SED_COMMAND} "s|<bai_namespace>|$BAI_SERVICES_NS|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
                ${SED_COMMAND} "s|<cr_metaname>|$cr_metaname|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
                ${SED_COMMAND} "s|<cr_uid>|$cr_uid|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
                ${SED_COMMAND} "s|<csv_version>|$bai_operator_csv_version|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}
                ${SED_COMMAND} "s|<cr_version>|$cr_version|g" ${UPGRADE_BAI_SHARED_INFO_CM_FILE}

                ${CLI_CMD} apply -f $UPGRADE_BAI_SHARED_INFO_CM_FILE  >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    success "Created ibm-bai-shared-info configMap in the project \"$BAI_SERVICES_NS\"!"
                    ${CLI_CMD} patch configmap ibm-bai-shared-info -n $BAI_SERVICES_NS --type=json -p="[{'op': 'add', 'path': '/data/bai_original_csv_ver_for_upgrade_script', 'value': '$(echo $bai_operator_csv_version)'}]" >/dev/null 2>&1
                    bai_original_csv_ver_for_upgrade_script=$bai_operator_csv_version
                else
                    fail "Failed to create ibm-bai-shared-info configMap in the project \"$BAI_SERVICES_NS\"!"
                fi
            else
                success "Found ibm-bai-shared-info configMap under \"$BAI_SERVICES_NS\"!"
                ${CLI_CMD} patch configmap ibm-bai-shared-info -n $BAI_SERVICES_NS --type=json -p="[{'op': 'add', 'path': '/data/bai_original_csv_ver_for_upgrade_script', 'value': '$(echo $bai_operator_csv_version)'}]" >/dev/null 2>&1
                bai_original_csv_ver_for_upgrade_script=$bai_operator_csv_version
            fi
        fi
        # Checking the CPfs mode
        ALL_NAMESPACE_FLAG="No" # no all namespaces support for BAI Standalone
        
        if [[ -z $UPGRADE_MODE ]]; then
            if [[ $ALL_NAMESPACE_FLAG == "Yes" ]]; then
                fail "All Namespaces deployment is not supported for BAI standalone under project \"$TARGET_PROJECT_NAME\", exiting"
                exit 1
            elif [[ $ALL_NAMESPACE_FLAG == "No" ]]; then
                info "IBM Cloud Pak foundational services is working in \"Namespace-scoped\"."
                UPGRADE_MODE="dedicated2dedicated"
            fi
        fi
        # checking existing catalog type
        if ${CLI_CMD} get catalogsource -n openshift-marketplace --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
            CATALOG_FOUND="Yes"
            PINNED="Yes"
        elif ${CLI_CMD} get catalogsource -n openshift-marketplace --no-headers --ignore-not-found | grep ibm-operator-catalog >/dev/null 2>&1; then
            CATALOG_FOUND="Yes"
            PINNED="No"
        else
            CATALOG_FOUND="No"
            PINNED="Yes" # Fresh install use pinned catalog source
        fi

        # Check if --enable-private-catalog is set or not
        # shared to shared code can be removed
        # Call select_private_catalog_bai if --enable-private-catalog option is not set
        if ${CLI_CMD} get catalogsource -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
            PRIVATE_CATALOG_FOUND="Yes"
            ENABLE_PRIVATE_CATALOG=1
            info "This BAI Standalone deployment is installed using private catalog in the project \"$TARGET_PROJECT_NAME\""
        elif ${CLI_CMD} get catalogsource -n openshift-marketplace --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
            PRIVATE_CATALOG_FOUND="No"
            info "This BAI deployment is installed using global catalog in the project \"openshift-marketplace\""
            if [[ $ENABLE_PRIVATE_CATALOG -eq 1 && $UPGRADE_MODE == "shared2shared" ]]; then
                ENABLE_PRIVATE_CATALOG=0
                warning "Can NOT switch catalog source from global catalog namespace (GCN) to private catalog (namespace-scoped) when migration IBM Cloud Pak foundational services from \"Cluster-scoped to Namespace-scoped\"."
                read -rsn1 -p"Press any key to continue";echo
            elif [[ $ENABLE_PRIVATE_CATALOG -eq 1 && ($UPGRADE_MODE == "shared2dedicated" || $UPGRADE_MODE == "dedicated2dedicated") ]]; then
                info "You have set the option \"--enable-private-catalog\" for this BAI Standalone deployment to use private catalog"
            elif [[ $ENABLE_PRIVATE_CATALOG -eq 0 || -z $ENABLE_PRIVATE_CATALOG ]]; then
                if [[ $UPGRADE_MODE == "shared2dedicated" || $UPGRADE_MODE == "dedicated2dedicated" ]]; then
                    select_private_catalog_bai
                elif [[ $UPGRADE_MODE == "shared2shared" ]]; then
                    fail "This upgrade mode path \"$UPGRADE_MODE\" is not supported for BAI Standalone upgrade"
                    exit 1
                    #info "Keep to use global catalog namespace (GCN) for this BAI deployment when migration IBM Cloud Pak foundational services from \"Cluster-scoped\" to \"Cluster-scoped\"."
                    #sleep 2
                fi
            fi
        fi

        
        if [[ $ENABLE_PRIVATE_CATALOG -eq 1 && $PRIVATE_CATALOG_FOUND == "No" && ($UPGRADE_MODE == "shared2dedicated" || $UPGRADE_MODE == "dedicated2dedicated") ]]; then
            info "The global catalog namespace (GCN) will be switched to private catalog (namespace-scoped)."
            sleep 2
        elif [[ $PRIVATE_CATALOG_FOUND == "Yes" ]]; then
            ENABLE_PRIVATE_CATALOG=1
            info "The BAI Standalone deployment will continue to use private catalog (namespace-scoped)."
            sleep 2
        fi

        # For shared->dedicated upgrade, we should allow user option to keep "global catalog"
        if [[ $ENABLE_PRIVATE_CATALOG -eq 0 && $UPGRADE_MODE == "shared2dedicated" ]]; then
            echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the upgrade: if you have multiple BAI Standalone deployments on this cluster and you don't want them to be updated, please update installPlan approval for BTS, EDB PostgreSQL on the other BAI deployments from \"Automatic\" to \"Manual\".${RESET_TEXT}"
            read -rsn1 -p"Press any key to continue ...";echo
        fi

        # Retrieve existing InsightsEngine CR
        insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')

        if [[ ! -z $insightsengine_cr_name ]]; then
            cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
            ${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

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
        fi
        ############## Start - Decide whether to create savepoint for Flink job ##############
        # NOTES: No need to create save point for upgrade IFIX by IFIX
        # Checking CSV for bai-operator to decide whether to do BAI save point during IFIX to IFIX upgrade
        sub_inst_list=$(${CLI_CMD} get subscriptions.operators.coreos.com -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
        if [[ -z $sub_inst_list ]]; then
            info "No existing BAI Standalone subscriptions have been found, continuing ..."
            # exit 1
        fi
        sub_array=($sub_inst_list)
        target_csv_version=${BAI_CSV_VERSION//v/}
        for i in ${!sub_array[@]}; do
            if [[ ! -z "${sub_array[i]}" ]]; then
                if [[ ${sub_array[i]} = ibm-bai-operator-catalog* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
                    current_version=$(${CLI_CMD} get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                    installed_version=$(${CLI_CMD} get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                    if [[ -z $current_version || -z $installed_version ]]; then
                        error "Failed to get installed or current CSV. Aborting the upgrade procedure. Please check ${sub_array[i]} subscription status."
                        exit 1
                    fi
                    case "${sub_array[i]}" in
                    "ibm-bai-insights-engine-operator"*)
                        prefix_sub="ibm-bai-insights-engine-operator.v"
                        ;;
                    "ibm-bai-foundation-operator"*)
                        prefix_sub="ibm-bai-foundation-operator.v"
                        ;;
                    esac
                    current_version=${current_version#"$prefix_sub"}
                    installed_version=${installed_version#"$prefix_sub"}
                    if [[ $current_version != $installed_version || $current_version != $target_csv_version || $installed_version != $target_csv_version ]]; then      
                        RUN_BAI_SAVEPOINT="Yes"
                    fi
                fi
            else
                fail "No found subscription '${sub_array[i]}'! exiting now..."
                exit 1
            fi
        done

        # No need to create Flink job savepoint for upgrading from IFIX to IFIX
        if [[ "$is_ifix_to_ifix_upgrade" == "false" ]]; then
            # In 24.0.0, follow the flow of migration from  Elasticsearch to Opensearch, the bai savepoint creation already done before upgrade BAI
            # So do not rerun savepoint. But need to covert bai json into UPGRADE_DEPLOYMENT_BAI_TMP for next upgradeDeployment mode.
            # Keep below logic for future IFIX to IFX upgrade.  Setting the RUN_BAI_SAVEPOINT="No" which will skip the savepoint creation in IFIX to IFIX upgrade
            # This section is for normal increment, n-1, upgrade like 24.0.0 to 24.0.1 for BAI.
            if [[ $RUN_BAI_SAVEPOINT == "Yes" ]]; then
                # Retrieve existing InsightsEngine CR for Create BAI save points
                insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
                if [ ! -z $insightsengine_cr_name ]; then
                    info "Retrieving the existing BAI InsightsEngine CR (Kind: insightsengines.bai.ibm.com) Custom Resource"
                    cr_type="insightsengine"
                    cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
                    ${CLI_CMD} get $cr_type $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

                    # Backup existing icp4acluster CR
                    mkdir -p ${UPGRADE_DEPLOYMENT_CR_BAK}
                    ${COPY_CMD} -rf ${UPGRADE_DEPLOYMENT_BAI_CR_TMP} ${UPGRADE_DEPLOYMENT_BAI_CR_BAK}

                    convert_olm_cr "${UPGRADE_DEPLOYMENT_BAI_CR_TMP}"
                    if [[ $olm_cr_flag == "No" ]]; then
                        # Get EXISTING_PATTERN_ARR/EXISTING_OPT_COMPONENT_ARR
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

                    # Create BAI save points
                    info "Checking for any BAI save points"
                    mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
                    # Check the jq install on MacOS
                    if [[ "$machine" == "Mac" ]]; then
                        which jq &>/dev/null
                        [[ $? -ne 0 ]] && \
                        echo -e  "\x1B[1;31mUnable to locate an jq CLI. You must install it to run this script on MacOS.\x1B[0m" && \
                        exit 1
                    fi
                    info "Creating the BAI savepoints for recovery path used for updating the custom resource file"
                    ${CLI_CMD} get crd |grep insightsengines.bai.ibm.com >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        INSIGHTS_ENGINE_CR=$(${CLI_CMD} get insightsengines.bai.ibm.com --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o name)
                    fi
                    if [[ -z $INSIGHTS_ENGINE_CR ]]; then
                        error "Insightsengine custom resource instance not found in the project \"${TARGET_PROJECT_NAME}\"."
                    fi
                    if [[ ! -z $INSIGHTS_ENGINE_CR ]]; then
                        MANAGEMENT_URL=$(${CLI_CMD} get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].uri}')
                        MANAGEMENT_AUTH_SECRET=$(${CLI_CMD} get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].authentication.secret.secretName}')
                        MANAGEMENT_USERNAME=$(${CLI_CMD} get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.data.username}' | base64 -d)
                        MANAGEMENT_PASSWORD=$(${CLI_CMD} get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${TARGET_PROJECT_NAME} -o jsonpath='{.data.password}' | base64 -d)
                        if [[ -z "$MANAGEMENT_URL" || -z "$MANAGEMENT_AUTH_SECRET" || -z "$MANAGEMENT_USERNAME" || -z "$MANAGEMENT_PASSWORD" ]]; then
                            error "Can not create the BAI savepoints for recovery path."
                            # exit 1
                        else
                            # rm -rf ${UPGRADE_DEPLOYMENT_CR}/bai.json >/dev/null 2>&1
                            touch ${UPGRADE_DEPLOYMENT_BAI_TMP} >/dev/null 2>&1
                            if [[ -e ${UPGRADE_DEPLOYMENT_CR}/bai.json ]]; then
                                [ "$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json)" != "[]" ] && mkdir -p ${UPGRADE_DEPLOYMENT_CR}/bai-json-backup && cp ${UPGRADE_DEPLOYMENT_CR}/bai.json ${UPGRADE_DEPLOYMENT_CR}/bai-json-backup/bai_$(date +'%Y%m%d%H%M%S').json
                            fi
                            curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} "${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints" -o ${UPGRADE_DEPLOYMENT_CR}/bai.json >/dev/null 2>&1

                            json_file_content="[]"
                            if [ "$json_file_content" == "$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json)" ] ;then
                                fail "None return in \"${UPGRADE_DEPLOYMENT_CR}/bai.json\" when request BAI savepoint through REST API: curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} \"${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints\" "
                                warning "Please fetch Flink job savepoints for recovery path using above REST API manually, and then put JSON file (bai.json) under the directory \"${TEMP_FOLDER}/\""
                                read -rsn1 -p"Press any key to continue";echo
                            fi
                            ##########################################################################################################################
                            ## In 24.0.1 and later, we'll only support n-1 upgrade therefore we're back to the old way of saving content event-forwarder savepoint and bai-content savepoint UNLESS the ALLOW_DIRECT_UPGRADE == 1 .
                            ##########################################################################################################################
                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-event-forwarder)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-event-forwarder |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.event-forwarder.recovery_path ${tmp_recovery_path}
                                success "Savepoint for Event-forwarder has been created: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.event-forwarder.recovery_path."
                            fi
                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-content)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-content |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.content.recovery_path ${tmp_recovery_path}
                                success "Flink savepoint for Content has been merged: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.content.recovery_path."
                            fi

                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-icm)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-icm |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.icm.recovery_path ${tmp_recovery_path}
                                success "Flink savepoint for ICM has been merged: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.icm.recovery_path."
                            fi

                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-odm)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-odm |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.odm.recovery_path ${tmp_recovery_path}
                                success "Flink savepoint for ODM has been merged: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.odm.recovery_path."
                            fi

                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-bawadv)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-bawadv |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bawadv.recovery_path ${tmp_recovery_path}
                                success "Flink savepoint for BAW ADV has been merged: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.bawadv.recovery_path."
                            fi

                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-bpmn)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-bpmn |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.bpmn.recovery_path ${tmp_recovery_path}
                                success "Flink savepoint for BPMN has been merged: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.bpmn.recovery_path."
                            fi
                            # Adding Navigator's recovery path
                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-navigator)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-navigator |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.navigator.recovery_path ${tmp_recovery_path}
                                success "Flink savepoint for Navigator has been merged: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.navigator.recovery_path."
                            fi
                            # Adding ADS's recovery path
                            if [[ "$machine" == "Mac" ]]; then
                                tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep bai-ads)
                            else
                                tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep bai-ads |cut -d':' -f2)
                            fi
                            tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
                            if [ ! -z "$tmp_recovery_path" ]; then
                                ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.ads.recovery_path ${tmp_recovery_path}
                                success "Flink savepoint for ADS has been merged: \"$tmp_recovery_path\""
                                info "When bai-deployment script is executed with -m upgradeDeployment flag, this savepoint will be auto-filled into spec.bai_configuration.ads.recovery_path."
                            fi
                        fi
                    fi
                fi
            fi
        fi
        
        ############## Start - Migration CPfs mode and upgrade BAI Standalone Operators ##############
        #  Switch BAI Operator to private catalog source
        if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
            sub_inst_list=$(${CLI_CMD} get subscriptions.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
            if [[ -z $sub_inst_list ]]; then
                info "Not existing BAI Standalone subscriptions has been found, continuing ..."
                # exit 1
            fi

            sub_array=($sub_inst_list)
            for i in ${!sub_array[@]}; do
                if [[ ! -z "${sub_array[i]}" ]]; then
                    if [[ ${sub_array[i]} = ibm-bai-operator-catalog* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
                        ${CLI_CMD} patch subscriptions.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -p '{"spec":{"sourceNamespace":"'"$TARGET_PROJECT_NAME"'"}}' --type=merge >/dev/null 2>&1
                        if [ $? -eq 0 ]
                        then
                            sleep 1
                            success "Switched the CatalogSource of subscription '${sub_array[i]}' to project \"$TARGET_PROJECT_NAME\"!"
                            printf "\n"
                        else
                            fail "Failed to switch the CatalogSource of subscription '${sub_array[i]}' to project \"$TARGET_PROJECT_NAME\"!"
                        fi
                    fi
                else
                    fail "No found subscription '${sub_array[i]}' in the project \"$TARGET_PROJECT_NAME\"! exiting now..."
                    exit 1
                fi
            done
        fi
        if [[ ! -z $bai_operators_namespace ]]; then
            bts_sub_flag=""
            export bts_sub_flag=$(${CLI_CMD} get subscriptions.operators.coreos.com --no-headers --ignore-not-found -n $bai_operators_namespace|grep ibm-bts-operator|awk '{print $1}')
            info "BTS subscription name is: $bts_sub_flag"
            if [[ ! -z "$bts_sub_flag" ]]; then
                info "Updating the catalog source of subscription "${bts_sub_flag}" to $BTS_CATALOG_VERSION"
                if [[ $ENABLE_PRIVATE_CATALOG -eq 1 || $PRIVATE_CATALOG_FOUND == "Yes" ]]; then
                    ${CLI_CMD} patch subscriptions.operators.coreos.com "${bts_sub_flag}" -n $bai_operators_namespace -p '{"spec":{"sourceNamespace":"'"$bai_operators_namespace"'"}}' --type=merge >/dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        success "Switch the catalog source of subscription "${bts_sub_flag}" to $bai_operators_namespace"
                        printf "\n"
                    else
                        fail "Failed to switch the catalog source of subscription "${bts_sub_flag}" to $bai_operators_namespace! exiting now..."
                        exit 1
                    fi
                fi
                ${CLI_CMD} patch subscriptions.operators.coreos.com "${bts_sub_flag}" -n $bai_operators_namespace -p '{"spec":{"source":"'"$BTS_CATALOG_VERSION"'"}}' --type=merge >/dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    success "Updated the catalog source of subscription "${bts_sub_flag}" to $BTS_CATALOG_VERSION"
                    printf "\n"
                else
                    fail "Failed to update the catalog source of subscription "${bts_sub_flag}" to $BTS_CATALOG_VERSION! exiting now..."
                    exit 1
                fi
                
                info "Updating the channel of subscription "${bts_sub_flag}" to $BTS_CHANNEL_VERSION"
                ${CLI_CMD} patch subscriptions.operators.coreos.com "${bts_sub_flag}" -n $bai_operators_namespace -p '{"spec":{"channel":"'"$BTS_CHANNEL_VERSION"'"}}' --type=merge >/dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    success "Updated the channel of subscription "${bts_sub_flag}" to $BTS_CHANNEL_VERSION"
                    printf "\n"
                else
                    fail "Failed to update the channel of subscription "${bts_sub_flag}" to $BTS_CHANNEL_VERSION! exiting now..."
                    exit 1
                fi
            fi
        fi
        #  Patch BAI channel to latest version, wait for all the operators are upgraded before applying operandRequest.
        sub_inst_list=$(${CLI_CMD} get subscriptions.operators.coreos.com -n $TARGET_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
        if [[ -z $sub_inst_list ]]; then
            info "No existing BAI Standalone subscriptions has been found, continuing ..."
            # exit 1
        fi

        sub_array=($sub_inst_list)
        for i in ${!sub_array[@]}; do
            if [[ ! -z "${sub_array[i]}" ]]; then
                if [[ ${sub_array[i]} = ibm-bai-operator-catalog* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
                    ${CLI_CMD} patch subscriptions.operators.coreos.com ${sub_array[i]} -n $TARGET_PROJECT_NAME -p '{"spec":{"channel":"v24.1"}}' --type=merge >/dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        success "Updated the channel of subscription '${sub_array[i]}' to $BAI_CHANNEL_VERSION"
                        printf "\n"
                    else
                        fail "Failed to update the channel of subscription '${sub_array[i]}' to $BAI_CHANNEL_VERSION! exiting now..."
                        exit 1
                    fi
                fi
            else
                fail "No found subscription '${sub_array[i]}'! exiting now..."
                exit 1
            fi
        done

        success "Completed the switch of channels for all subscriptions of BAI Standalone operators"

        # Apply the new catalog source and creating new namespaces for cert manager and license manager
        if [[ ($CATALOG_FOUND == "Yes" && $PINNED == "Yes") || $PRIVATE_CATALOG_FOUND == "Yes" ]]; then
            # switch catalog from "global" to "namespace" catalog or keep private catalog source
            if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
                TEMP_CATALOG_PROJECT_NAME=${TARGET_PROJECT_NAME}
                OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
                OLM_CATALOG_TMP=${TEMP_FOLDER}/.catalog_source.yaml

                info "Creating project \"$CERT_MANAGER_PROJECT\" for IBM Cert Manager operator catalog."
                create_project "$CERT_MANAGER_PROJECT"
                if [[ $? -eq 0 ]]; then
                    success "Created project \"$CERT_MANAGER_PROJECT\" for IBM Cert Manager operator catalog."
                fi

                info "Creating project \"$LICENSE_MANAGER_PROJECT\" for IBM Licensing operator catalog."
                create_project "$LICENSE_MANAGER_PROJECT"
                if [[ $? -eq 0 ]]; then
                    success "Created project \"$LICENSE_MANAGER_PROJECT\" for IBM Licensing operator catalog."
                    printf "\n"
                fi

                # Additionally, we would check if cs-control namespace exists.
                isProjExists=`${CLI_CMD} get project $DEDICATED_CS_PROJECT --no-headers --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ $isProjExists -eq 1 ] ; then
                    # If it exists, we will deploy the same ibm-licensing-catalog into cs-control namespace.
                    if [[ $machine == "Linux" ]]; then
                        TMP_LICENSING_OLM_CATALOG=$(mktemp --suffix=.yaml)
                    elif [[ $machine == "Mac" ]]; then
                        TMP_LICENSING_OLM_CATALOG=$(mktemp -t licensing_olm_catalog).yaml
                    fi
                    start_num="# IBM License Manager"
                    end_num="interval: 45m"

                    reading_section=false

                    while IFS= read -r line; do
                        if [[ "$line" == *"$start_num"* ]]; then
                            reading_section=true
                        fi

                        if $reading_section; then
                            echo "$line" >> "$TMP_LICENSING_OLM_CATALOG"
                        fi

                        if [[ "$line" == *"$end_num"* ]]; then
                            reading_section=false
                        fi
                    done < "${OLM_CATALOG}"

                    # replace openshift-marketplace for ibm-licensing-catalog with cs-control
                    ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: \"$DEDICATED_CS_PROJECT\"/;}" ${TMP_LICENSING_OLM_CATALOG}

                    ${CLI_CMD} apply -f $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        echo "Create IBM License Manager Catalog source in project \"$DEDICATED_CS_PROJECT\"!"
                    else
                        echo "Generic Operator catalog source update failed"
                        exit 1
                    fi
                    rm -rf $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
                fi

                sed "s/REPLACE_CATALOG_SOURCE_NAMESPACE/$CATALOG_NAMESPACE/g" ${OLM_CATALOG} > ${OLM_CATALOG_TMP}
                # replace all other catalogs with <BAI NS> namespaces
                ${SED_COMMAND} "s|namespace: .*|namespace: \"$TARGET_PROJECT_NAME\"|g" ${OLM_CATALOG_TMP}
                # replace openshift-marketplace for ibm-cert-manager-catalog with ibm-cert-manager
                ${SED_COMMAND} "/name: ibm-cert-manager-catalog/{n;s/namespace: .*/namespace: $CERT_MANAGER_PROJECT/;}" ${OLM_CATALOG_TMP}
                # replace openshift-marketplace for ibm-licensing-catalog with ibm-licensing
                ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: $LICENSE_MANAGER_PROJECT/;}" ${OLM_CATALOG_TMP}

                ${CLI_CMD} apply -f $OLM_CATALOG_TMP
                if [ $? -eq 0 ]; then
                    echo "IBM Business Automation Insights Catalog source updated!"
                else
                    echo "IBM Business Automation Insights Catalog source update failed"
                    exit 1
                fi
            else
                TEMP_CATALOG_PROJECT_NAME="openshift-marketplace"
                info "Applying latest BAI Standalone catalog source ..."
                OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
                ${CLI_CMD} apply -f $OLM_CATALOG >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                    echo "IBM Business Automation Insights Catalog source updated!"
                    exit 1
                fi
                echo "Done!"
            fi

            # Checking if BAI Standalone catalog source pods are ready
            info "Checking Business Automation Insights operator catalog pod ready or not in the project \"$TEMP_CATALOG_PROJECT_NAME\""
            maxRetry=50
            for ((retry=0;retry<=${maxRetry};retry++)); do
                bai_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-bai-operator-catalog -n $TEMP_CATALOG_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                postgresql_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=cloud-native-postgresql-catalog -n $TEMP_CATALOG_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                cs_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=$CS_CATALOG_VERSION -n $TEMP_CATALOG_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ $ENABLE_PRIVATE_CATALOG -eq 1 ]; then
                    cert_mgr_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-cert-manager-catalog -n $CERT_MANAGER_PROJECT -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                    license_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-licensing-catalog -n $LICENSE_MANAGER_PROJECT -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                else
                    cert_mgr_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-cert-manager-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                    license_catalog_pod_name=$(${CLI_CMD} get pod -l=olm.catalogSource=ibm-licensing-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                fi
                if [[ ( -z $cert_mgr_catalog_pod_name) || ( -z $license_catalog_pod_name) || ( -z $cs_catalog_pod_name) || (-z $postgresql_catalog_pod_name) ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        printf "\n"
                        if [[ -z $bai_catalog_pod_name ]]; then
                            warning "Timeout waiting for ibm-bai-operator-catalog catalog pod to be ready in the project \"$TEMP_CATALOG_PROJECT_NAME\""
                        elif [[ -z $postgresql_catalog_pod_name ]]; then
                            warning "Timeout waiting for cloud-native-postgresql-catalog catalog pod to be ready in the project \"$TEMP_CATALOG_PROJECT_NAME\""
                        elif [[ -z $cs_catalog_pod_name ]]; then
                            warning "Timeout waiting for $CS_CATALOG_VERSION catalog pod to be ready in the project \"$TEMP_CATALOG_PROJECT_NAME\""
                        elif [[ -z $cert_mgr_catalog_pod_name ]]; then
                            warning "Timeout waiting for ibm-cert-manager-catalog catalog pod to be ready in the project \"openshift-marketplace\""
                        elif [[ -z $license_catalog_pod_name ]]; then
                            warning "Timeout waiting for ibm-licensing-catalog catalog pod to be ready in the project \"openshift-marketplace\""
                        fi
                        exit 1
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi
                else
                    success "Business Automation Insights operator catalog pod is ready in the project \"$TEMP_CATALOG_PROJECT_NAME\"!"
                    break
                fi
            done
        else
            fail "Not found IBM Business Automation Insights catalog source!"
            exit 1
        fi

        # Upgrade BAI Standalone operator
        info "Starting to upgrade IBM Business Automation Insights operator"

        # Check ibm-bts-operator/cloud-native-postgresql already upgrade to latest version
        if [[ $UPGRADE_MODE == "dedicated2dedicated"  ]]; then
            cs_service_target_namespace="$TARGET_PROJECT_NAME"
        elif [[ $UPGRADE_MODE == "shared2shared" || $UPGRADE_MODE == "shared2dedicated" ]]; then
            cs_service_target_namespace="ibm-common-services"
        fi

        # Check cloud-native-postgresql/ibm-bts-operator
        if [[ $ENABLE_PRIVATE_CATALOG -eq 0 ]]; then
            cloud_native_postgresql_flag=$(${CLI_CMD} get subscriptions.operators.coreos.com cloud-native-postgresql --no-headers --ignore-not-found -n $cs_service_target_namespace | wc -l)
            ibm_bts_operator_flag=$(${CLI_CMD} get subscriptions.operators.coreos.com "${bts_sub_flag}" --no-headers --ignore-not-found -n $cs_service_target_namespace | wc -l)
            maxRetry=50
            if [ $cloud_native_postgresql_flag -ne 0 ]; then
                info "Checking the version of subscription 'cloud-native-postgresql' in the project \"$cs_service_target_namespace\""
                sleep 60
                for ((retry=0;retry<=${maxRetry};retry++)); do
                    current_version_postgresql=$(${CLI_CMD} get subscriptions.operators.coreos.com cloud-native-postgresql --no-headers --ignore-not-found -n $cs_service_target_namespace -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                    installed_version_postgresql=$(${CLI_CMD} get subscriptions.operators.coreos.com cloud-native-postgresql --no-headers --ignore-not-found -n $cs_service_target_namespace -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                    prefix_postgresql="cloud-native-postgresql.v"
                    current_version_postgresql=${current_version_postgresql#"$prefix_postgresql"}
                    installed_version_postgresql=${installed_version_postgresql#"$prefix_postgresql"}
                    # REQUIREDVER_POSTGRESQL="1.18.5"
                    if [[ (! "$(printf '%s\n' "$REQUIREDVER_POSTGRESQL" "$current_version_postgresql" | sort -V | head -n1)" = "$REQUIREDVER_POSTGRESQL") || (! "$(printf '%s\n' "$REQUIREDVER_POSTGRESQL" "$installed_version_postgresql" | sort -V | head -n1)" = "$REQUIREDVER_POSTGRESQL") ]]; then
                        if [[ $retry -eq ${maxRetry} ]]; then
                            info "Timeout Checking for the version of cloud-native-postgresql subscription in the project \"$cs_service_target_namespace\""
                            cloud_native_postgresql_ready="No"
                            break
                        else
                            sleep 30
                            echo -n "..."
                            continue

                        fi
                    else
                        success "The version of subscription 'cloud-native-postgresql' is v$current_version_postgresql."
                        cloud_native_postgresql_ready="Yes"
                        break
                    fi
                done
            else
                cloud_native_postgresql_ready="Yes"
            fi

            if [ $ibm_bts_operator_flag -ne 0 ]; then
                info "Checking the version of subscription "${bts_sub_flag}" in the project \"$cs_service_target_namespace\""
                for ((retry=0;retry<=${maxRetry};retry++)); do
                    current_version_bts=$(${CLI_CMD} get subscriptions.operators.coreos.com "${bts_sub_flag}" --no-headers --ignore-not-found -n $cs_service_target_namespace -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                    installed_version_bts=$(${CLI_CMD} get subscriptions.operators.coreos.com "${bts_sub_flag}" --no-headers --ignore-not-found -n $cs_service_target_namespace -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                    prefix_bts="ibm-bts-operator.v"
                    current_version_bts=${current_version_bts#"$prefix_bts"}
                    installed_version_bts=${installed_version_bts#"$prefix_bts"}
                    # REQUIREDVER_BTS="3.28.0"
                    if [[ (! "$(printf '%s\n' "$REQUIREDVER_BTS" "$current_version_bts" | sort -V | head -n1)" = "$REQUIREDVER_BTS") || (! "$(printf '%s\n' "$REQUIREDVER_BTS" "$installed_version_bts" | sort -V | head -n1)" = "$REQUIREDVER_BTS") ]]; then
                        if [[ $retry -eq ${maxRetry} ]]; then
                            info "Timeout Checking for the version of "${bts_sub_flag}" subscription in the project \"$cs_service_target_namespace\""
                            ibm_bts_operator_ready="No"
                            break
                        else
                            sleep 30
                            echo -n "..."
                            continue
                        fi
                    else
                        success "The version of subscription "${bts_sub_flag}" is v$current_version_bts."
                        ibm_bts_operator_ready="Yes"
                        break
                    fi
                done
            else
                ibm_bts_operator_ready="Yes"
            fi
        elif [[ $ENABLE_PRIVATE_CATALOG -eq 1 ]]; then
            # For shared2dedicated/dedicated2dedicated enable private catalog, we do not switch common service catalog source in ibm-common-services project.
            ibm_bts_operator_ready="Yes"
            cloud_native_postgresql_ready="Yes"
        fi

        #ibm_bai_foundation_operator_flag=$(${CLI_CMD} get subscriptions.operators.coreos.com -l=operators.coreos.com/ibm-bai-foundation-operator.$TEMP_OPERATOR_PROJECT_NAME --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME | wc -l)
        #if [ $ibm_bai_foundation_operator_flag -ne 0 ]; then
        #    ibm_bai_foundation_sub_name=$(${CLI_CMD} get subscriptions.operators.coreos.com -l=operators.coreos.com/ibm-bai-foundation-operator.$TEMP_OPERATOR_PROJECT_NAME --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME | awk '{print $1}')

        #    info "Checking the version of subscription '$ibm_bai_foundation_sub_name' in the project \"$TEMP_OPERATOR_PROJECT_NAME\""
        #    for ((retry=0;retry<=${maxRetry};retry++)); do
        #        current_version_foundation=$(${CLI_CMD} get subscriptions.operators.coreos.com $ibm_bai_foundation_sub_name --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
        #        installed_version_foundation=$(${CLI_CMD} get subscriptions.operators.coreos.com $ibm_bai_foundation_sub_name --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
        #        prefix_bts="ibm-bai-foundation-operator.v"
        #        current_version_foundation=${current_version_foundation#"$prefix_bts"}
        #        installed_version_foundation=${installed_version_foundation#"$prefix_bts"}
        #        REQUIREDVER_VERSION="${BAI_CSV_VERSION//v/}"
        #        if [[ (! "$(printf '%s\n' "$REQUIREDVER_VERSION" "$current_version_foundation" | sort -V | head -n1)" = "$REQUIREDVER_VERSION") || (! "$(printf '%s\n' "$REQUIREDVER_VERSION" "$installed_version_foundation" | sort -V | head -n1)" = "$REQUIREDVER_VERSION") ]]; then
        #            if [[ $retry -eq ${maxRetry} ]]; then
        #                info "Timeout Checking for the version of $ibm_bai_foundation_sub_name subscription in the project \"$TEMP_OPERATOR_PROJECT_NAME\""
        #                ibm_bai_foundation_operator_ready="No"
        #                break
        #            else
        #                sleep 30
        #                echo -n "..."
        #                continue
        #            fi
        #        else
        #            success "The version of subscription '$ibm_bai_foundation_sub_name' is v$current_version_foundation."
        #            ibm_bai_foundation_operator_ready="Yes"
        #            break
        #        fi
        #    done
        #fi

        if [[ "$bai_operator_csv_version" == "24.0."* && (("$ibm_bts_operator_ready" == "Yes" && "$cloud_native_postgresql_ready" == "Yes" )) ]]; then
            READY_FOR_DIRECT_UPGRADE="Yes"
        else
            READY_FOR_DIRECT_UPGRADE="No"
            fail "Prerequisite for upgrade did not complete, exiting..."
        fi
        # upgrading the CPFS operators
        if [[ $READY_FOR_DIRECT_UPGRADE == "Yes" ]]; then
            info "Prerequisites for upgrade have been completed with no errors, continue..."
            if [[ "$bai_operator_csv_version" == "24.0."* ]]; then
                info "Starting to upgrade IBM Cloud Pak foundational services to $CS_OPERATOR_VERSION"
                # Check if without option --enable-private-catalog, the catalog is in target project, set the private catalog as default.
                info "Checking if ibm-bai-operator-catalog catalog source is global or private namespace scoped"
                if [[ $ENABLE_PRIVATE_CATALOG -eq 0 ]]; then
                    if ${CLI_CMD} get catalogsource -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep ibm-bai-operator-catalog >/dev/null 2>&1; then
                        ENABLE_PRIVATE_CATALOG=1
                    else
                        info "ibm-bai-operator-catalog catalog source is not found under target project \"$TARGET_PROJECT_NAME\""
                    fi
                fi
                if [[ $UPGRADE_MODE == "dedicated2dedicated" && $ENABLE_PRIVATE_CATALOG -eq 1 ]]; then
                    # Additionally, we would check if cs-control namespace exists.
                    isProjExists=`${CLI_CMD} get project $DEDICATED_CS_PROJECT --no-headers --ignore-not-found | wc -l`  >/dev/null 2>&1
                    if [ $isProjExists -eq 1 ] ; then
                        # If it exists, we will deploy the same ibm-licensing-catalog into cs-control namespace.
                        if [[ $machine == "Linux" ]]; then
                            TMP_LICENSING_OLM_CATALOG=$(mktemp --suffix=.yaml)
                        elif [[ $machine == "Mac" ]]; then
                            TMP_LICENSING_OLM_CATALOG=$(mktemp -t licensing_olm_catalog).yaml
                        fi
                        start_num="# IBM License Manager"
                        end_num="interval: 45m"

                        reading_section=false

                        while IFS= read -r line; do
                            if [[ "$line" == *"$start_num"* ]]; then
                                reading_section=true
                            fi

                            if $reading_section; then
                                echo "$line" >> "$TMP_LICENSING_OLM_CATALOG"
                            fi

                            if [[ "$line" == *"$end_num"* ]]; then
                                reading_section=false
                            fi
                        done < "${OLM_CATALOG}"

                        # replace openshift-marketplace for ibm-licensing-catalog with cs-control
                        ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: \"$DEDICATED_CS_PROJECT\"/;}" ${TMP_LICENSING_OLM_CATALOG}

                        ${CLI_CMD} apply -f $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            echo "Created IBM License Manager Catalog source in project \"$DEDICATED_CS_PROJECT\"!"
                        else
                            echo "Generic Operator catalog source update failed"
                            exit 1
                        fi
                        rm -rf $TMP_LICENSING_OLM_CATALOG >/dev/null 2>&1
                    fi

                    # Upgrading Cert-Manager and Licensing Service
                    msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --enable-private-catalog --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
                    $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --enable-private-catalog --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
                    if [ $? -ne 0 ]; then
                        warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --enable-private-catalog --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
                        echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                        echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                        echo "           Usage:"
                        echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                        echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                        echo "           Example command: "
                        echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                        exit 1
                    fi
                    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
                        # switch catalog from GCN to private
                        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $BAI_SERVICES_NS --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1"
                        $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $BAI_SERVICES_NS --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1
                        if [ $? -ne 0 ]; then
                            warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $BAI_SERVICES_NS --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1"
                            echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                            echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                            echo "           Usage:"
                            echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                            echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                            echo "           Example command: "
                            echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                            exit 1
                        fi
                    else
                        # switch catalog from GCN to private
                        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TARGET_PROJECT_NAME --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1"
                        $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TARGET_PROJECT_NAME --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1
                        if [ $? -ne 0 ]; then
                            warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TARGET_PROJECT_NAME --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog -v 1"
                            echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                            echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                            echo "           Usage:"
                            echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                            echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                            echo "           Example command: "
                            echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                            exit 1
                        fi
                    fi
                elif [[ $UPGRADE_MODE == "dedicated2dedicated" && $ENABLE_PRIVATE_CATALOG -eq 0 ]]; then
                    # Upgrading Cert-Manager and Licensing Service
                    msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
                    $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
                    if [ $? -ne 0 ]; then
                        warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
                        echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                        echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                        echo "           Usage:"
                        echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                        echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                        echo "           Example command: "
                        echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                        exit 1
                    fi
                    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
                        # keep GCN catalog
                        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $BAI_SERVICES_NS --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
                        $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $BAI_SERVICES_NS --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1
                        if [ $? -ne 0 ]; then
                            warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $BAI_SERVICES_NS --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
                            echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                            echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                            echo "           Usage:"
                            echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                            echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                            echo "           Example command: "
                            echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                            exit 1
                        fi
                    else
                        # keep GCN catalog
                        msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TARGET_PROJECT_NAME --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
                        $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TARGET_PROJECT_NAME --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1
                        if [ $? -ne 0 ]; then
                            warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace $TARGET_PROJECT_NAME --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
                            echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                            echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                            echo "           Usage:"
                            echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                            echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                            echo "           Example command: "
                            echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                            exit 1
                        fi
                    fi
                elif [[ $UPGRADE_MODE == "shared2shared" && $ALL_NAMESPACE_FLAG == "No" ]]; then
                    # Upgrading Cert-Manager and Licensing Service
                    msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
                    $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
                    if [ $? -ne 0 ]; then
                        warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --license-accept --enable-licensing --yq \"$CPFS_YQ_PATH\" -c $CERT_LICENSE_CHANNEL_VERSION"
                        echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                        echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                        echo "           Usage:"
                        echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                        echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                        echo "           Example command: "
                        echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                        exit 1
                    fi
                    # keep GCN catalog
                    msg "All arguments passed into the CPfs script: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace ibm-common-services --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
                    $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace ibm-common-services --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1
                    if [ $? -ne 0 ]; then
                        warning "Failed to execute command: $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --license-accept --enable-licensing --operator-namespace $TARGET_PROJECT_NAME --services-namespace ibm-common-services --yq \"$CPFS_YQ_PATH\" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -v 1"
                        echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fix migration issue of IBM Cloud Pak foundational services."
                        echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
                        echo "           Usage:"
                        echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
                        echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade, the example value [24.0.1] for 24.0.0-IF001"
                        echo "           Example command: "
                        echo "           # ./bai-deployment.sh -m upgradeOperator -n $TARGET_PROJECT_NAME --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver 24.0.1"
                        exit 1
                    fi
                fi
            fi
        fi

        # Check IBM Cloud Pak foundational services Operator $CS_OPERATOR_VERSION
        maxRetry=30
        echo "****************************************************************************"
        info "Checking for IBM Cloud Pak foundational operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(${CLI_CMD} get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o jsonpath='{.status.phase}')
            # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $upgrade_operator_project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine $BAI_RELEASE_BASE")
            if [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for IBM Cloud Pak foundational operator to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-common-service-operator|awk '{print $1}') -n $TEMP_OPERATOR_PROJECT_NAME"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-common-service-operator|awk '{print $1}') -n $TEMP_OPERATOR_PROJECT_NAME"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-common-service-operator -n $TEMP_OPERATOR_PROJECT_NAME -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
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

        # Checking BAI operator CSV
        sub_inst_list=$(${CLI_CMD} get subscriptions.operators.coreos.com -n $TEMP_OPERATOR_PROJECT_NAME|grep ibm-bai-operator-catalog|awk '{if(NR>0){if(NR==1){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
        if [[ -z $sub_inst_list ]]; then
            fail "Not found any existing BAI Standalone subscriptions (version $BAI_CSV_VERSION), exiting ..."
            exit 1
        fi
        sub_array=($sub_inst_list)
        target_csv_version=${BAI_CSV_VERSION//v/}
        for i in ${!sub_array[@]}; do
            if [[ ! -z "${sub_array[i]}" ]]; then
                if [[ ${sub_array[i]} = ibm-bai-insights-engine-operator* || ${sub_array[i]} = ibm-bai-foundation-operator* ]]; then
                info "Checking the channel of subscription '${sub_array[i]}'!"
                currentChannel=$(${CLI_CMD} get subscriptions.operators.coreos.com ${sub_array[i]} -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.spec.channel}') >/dev/null 2>&1
                    if [[ "$currentChannel" == "$BAI_CHANNEL_VERSION" ]];then
                        success "The channel of subscription '${sub_array[i]}' is $currentChannel!"
                        printf "\n"
                        maxRetry=40
                        info "Waiting for the \"${sub_array[i]}\" subscription be upgraded to the ClusterServiceVersions(CSV) \"v$target_csv_version\""
                        for ((retry=0;retry<=${maxRetry};retry++)); do
                            current_version=$(${CLI_CMD} get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.currentCSV}') >/dev/null 2>&1
                            installed_version=$(${CLI_CMD} get subscriptions.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
                            if [[ -z $current_version || -z $installed_version ]]; then
                                error "Failed to get installed or current CSV, abort the upgrade procedure. Please check ${sub_array[i]} subscription status."
                                exit 1
                            fi
                            case "${sub_array[i]}" in
                            "ibm-bai-insights-engine-operator"*)
                                prefix_sub="ibm-bai-insights-engine-operator.v"
                                ;;
                            "ibm-bai-foundation-operator"*)
                                prefix_sub="ibm-bai-foundation-operator.v"
                                ;;
                            esac

                            current_version=${current_version#"$prefix_sub"}
                            installed_version=${installed_version#"$prefix_sub"}
                            if [[ $current_version != $installed_version || $current_version != $target_csv_version || $installed_version != $target_csv_version ]]; then
                                approval_mode=$(${CLI_CMD} get subscription.operators.coreos.com ${sub_array[i]} --no-headers --ignore-not-found -n $TEMP_OPERATOR_PROJECT_NAME -o jsonpath={.spec.installPlanApproval})
                                if [[ $approval_mode == "Manual" ]]; then
                                    error "${sub_array[i]} subscription is set to Manual Approval mode, please approve installPlan to upgrade."
                                    exit 1
                                fi
                                if [[ $retry -eq ${maxRetry} ]]; then
                                    warning "Timeout waiting for upgrading \"${sub_array[i]}\" subscription from ${installed_version} to ${target_csv_version} in the project \"$TEMP_OPERATOR_PROJECT_NAME\""
                                    break
                                else
                                    sleep 10
                                    echo -n "..."
                                    continue
                                fi
                            else
                                success "ClusterServiceVersions ${installed_version} is now the latest available version in ${currentChannel} channel."
                                break
                            fi
                        done

                    else
                        fail "Failed to update the channel of subscription '${sub_array[i]}' to $BAI_CHANNEL_VERSION! exiting now..."
                        exit 1
                    fi
                fi
            else
                fail "No found subscription '${sub_array[i]}'! exiting now..."
                exit 1
            fi
        done
        success "Completed the check for channels of all subscriptions of BAI Standalone operators"

        # For Major release upgrade
        if [[ "$bai_original_csv_ver_for_upgrade_script" != "24.1."* ]]; then
            printf "\n"
            echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
            step_num=1
            echo "  - STEP ${step_num} ${YELLOW_TEXT}(Optional)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeOperatorStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check that the upgrade of the IBM Business Automation Insights operator and its dependencies is successful."
            printf "\n"
            step_num=$((step_num + 1))
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeployment -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to upgrade the IBM Business Automation Insights deployment."
            printf "\n"
            step_num=$((step_num + 1))
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check that the upgrade of the IBM Business Automation Insights deployment is successful."
        # for upgrading IFIX by IFIX
        else
            printf "\n"
            echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
            step_num=1
            echo "  - STEP ${step_num} ${YELLOW_TEXT}(Optional)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeOperatorStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check that the upgrade of the IBM Business Automation Insights operator and its dependencies is successful."
            printf "\n"
            step_num=$((step_num + 1))
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check that the upgrade of the IBM Business Automation Insights deployment is successful."
        fi
    fi
fi

#This runtime is to check the operator status after the upgrade is completed
if [ "$RUNTIME_MODE" == "upgradeOperatorStatus" ]; then
    project_name=$TARGET_PROJECT_NAME
    info "Checking if the BAI standalone operators upgrade is completed..."
    check_bai_operator_version $TARGET_PROJECT_NAME
    check_bai_separate_operand $TARGET_PROJECT_NAME
    UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/bai-upgrade/project/$BAI_SERVICES_NS
    UPGRADE_DEPLOYMENT_CR=${UPGRADE_DEPLOYMENT_FOLDER}/custom_resource
    UPGRADE_DEPLOYMENT_BAI_CR_TMP=${UPGRADE_DEPLOYMENT_CR}/.insightsengine_tmp.yaml
    mkdir -p $UPGRADE_DEPLOYMENT_CR >/dev/null 2>&1

    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
        source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $BAI_SERVICES_NS
    else
        source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $TARGET_PROJECT_NAME
    fi
    bai_operator_csv_name_target_ns=$(${CLI_CMD} get csv -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep "IBM Business Automation Insights" | awk '{print $1}')
    if [[ (! -z $bai_operator_csv_name_target_ns) ]]; then
        success "Found IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        ALL_NAMESPACE_FLAG="No"
        TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME
    else
        fail "Failed to find IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        exit
    fi

    # Get value of bai_original_csv_ver_for_upgrade_script
    ibm_bai_shared_info_cm=$(${CLI_CMD} get configmap ibm-bai-shared-info --no-headers --ignore-not-found -n $BAI_SERVICES_NS)
    if [[ ! -z $ibm_bai_shared_info_cm ]]; then
        tmp_csv_val=$(${CLI_CMD} get configmap ibm-bai-shared-info -n $BAI_SERVICES_NS -o jsonpath='{.data.bai_original_csv_ver_for_upgrade_script}')
        if [[ ! -z $tmp_csv_val ]]; then
            bai_original_csv_ver_for_upgrade_script=$tmp_csv_val
        else
            fail "Configmap ibm-bai-shared-info created incorrectly, run upgradeOperator mode to fix this issue."
            exit
        fi
    else
        fail "Failed to find IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        exit
    fi

    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
    if [[ ! -z $insightsengine_cr_name ]]; then
        cr_type="insightsengine"
        bai_cr_metaname=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - metadata.name)
        ${CLI_CMD} get $cr_type $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml > ${UPGRADE_DEPLOYMENT_BAI_CR_TMP}

        bai_root_ca_secret_name=`cat $UPGRADE_DEPLOYMENT_BAI_CR_TMP | ${YQ_CMD} r - spec.shared_configuration.root_ca_secret`
        convert_olm_cr "${UPGRADE_DEPLOYMENT_BAI_CR_TMP}"
        if [[ $olm_cr_flag == "No" ]]; then
            # Get EXISTING_PATTERN_ARR/EXISTING_OPT_COMPONENT_ARR
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
    fi
    if [[ -z $insightsengine_cr_name ]]; then
        fail "Not found any BAI Standalone custom resource file in the project \"$BAI_SERVICES_NS\"."
        exit 1
    fi

    info "Checking if the BAI standalone operators upgrade is completed..."
    check_operator_status $TARGET_PROJECT_NAME "full" "channel"

    if [[ " ${CHECK_BAI_OPERATOR_RESULT[@]} " =~ "FAIL" ]]; then
        fail "Failed to upgrade BAI standalone operators"
    else
        # For Major release upgrade
        if [[ "$bai_original_csv_ver_for_upgrade_script" != "24.1."* ]]; then
            success "Business Automation Insights operators upgraded successfully!"
            printf "\n"
            echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
            step_num=1
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeployment -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to upgrade the IBM Business Automation Insights deployment."
            printf "\n"
            step_num=$((step_num + 1))
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME\"${RESET_TEXT} to check that the upgrade of the IBM Business Automation Insights deployment is successful."
        # for upgrading IFIX by IFIX
        else
            success "Business Automation Insights operators upgraded successfully!"
            printf "\n"
            echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}: "
            printf "\n"
            echo "${YELLOW_TEXT}* Run the script in [upgradeDeploymentStatus] mode directly when upgrade BAI standalone from $BAI_RELEASE_BASE IFix to IFix.${RESET_TEXT}"
            echo "${GREEN_TEXT}# ./bai-deployment.sh -m upgradeDeploymentStatus -n $TARGET_PROJECT_NAME${RESET_TEXT}"
        fi
        
    fi
fi

if [ "$RUNTIME_MODE" == "upgradeDeployment" ]; then
    project_name=$TARGET_PROJECT_NAME
    # Check whether the BAI is separation of operators and operands.
    check_bai_separate_operand $TARGET_PROJECT_NAME
    ALL_NAMESPACE_FLAG="No"
    TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME

    # Get value of bai_original_csv_ver_for_upgrade_script
    ibm_bai_shared_info_cm=$(${CLI_CMD} get configmap ibm-bai-shared-info --no-headers --ignore-not-found -n $BAI_SERVICES_NS)
    if [[ ! -z $ibm_bai_shared_info_cm ]]; then
        tmp_csv_val=$(${CLI_CMD} get configmap ibm-bai-shared-info -n $BAI_SERVICES_NS -o jsonpath='{.data.bai_original_csv_ver_for_upgrade_script}')
        if [[ ! -z $tmp_csv_val ]]; then
            bai_original_csv_ver_for_upgrade_script=$tmp_csv_val
        else
            fail "Configmap ibm-bai-shared-info created incorrectly, run upgradeOperator mode to fix this issue."
            exit
        fi
    else
        fail "Failed to find IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        exit
    fi

    if [[ "$bai_original_csv_ver_for_upgrade_script" == "24.1."* ]]; then
        warning "DO NOT NEED to run [upgradeDeployment] mode for upgrading from ${BAI_RELEASE_BASE}GA/${BAI_RELEASE_BASE}.X to ${BAI_RELEASE_BASE}.X"
        echo "Exiting ..."
        exit 1
    fi

    if [[ $SEPARATE_OPERAND_FLAG == "Yes" ]]; then
        source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $BAI_SERVICES_NS
    else
        source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $TARGET_PROJECT_NAME
    fi

    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $project_name --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $insightsengine_cr_name ]; then
        cr_version=$(kubectl get insightsengine $insightsengine_cr_name -n $project_name -o yaml | ${YQ_CMD} r - spec.appVersion)
        if [[ $cr_version == "${BAI_RELEASE_BASE}" ]]; then
            warning "The release version of insightsengine custom resource \"$insightsengine_cr_name\" is already \"$cr_version\"."
            printf "\n"
            while true; do
                printf "\x1B[1mDo you want to continue run upgrade? (Yes/No, default: No): \x1B[0m"
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
                    echo -e "Answer must be \"Yes\" or \"No\"\n"
                    ;;
                esac
            done
        fi
    fi

    # $TARGET_PROJECT_NAME for BAI deployment, $TEMP_OPERATOR_PROJECT_NAME for BAI operators
    upgrade_deployment $BAI_SERVICES_NS $TEMP_OPERATOR_PROJECT_NAME

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
    echo "  # ${CLI_CMD} get zenService $(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $BAI_SERVICES_NS |awk '{print $1}') --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.Progress}'"
fi

# This mode is for upgradeDeploymentStatus , shows the upgrade status for zen and also how to track the deployment status 
# Currently the BAI standalone operator does not have enough code in place for the correct status variables in the CR for components that we use for showing the status of components
if [[ "$RUNTIME_MODE" == "upgradeDeploymentStatus" ]]; then
    UPGRADE_DEPLOYMENT_FOLDER=${CUR_DIR}/bai-upgrade/project/$TARGET_PROJECT_NAME
    TEMP_CP_CONSOLE_FILE=${UPGRADE_DEPLOYMENT_FOLDER}/original-cp-console.yaml
    TEMP_CP_CONSOLE_FILE_ID_PROVIDER=${UPGRADE_DEPLOYMENT_FOLDER}/id-provider-cp-console.yaml
    TEMP_CP_CONSOLE_FILE_ID_MGMT=${UPGRADE_DEPLOYMENT_FOLDER}/id-mgmt-cp-console.yaml
    source ${CUR_DIR}/helper/upgrade/upgrade_merge_yaml.sh $TARGET_PROJECT_NAME

    CP_CONSOLE='cp-console'
    ID_PROVIDER_ROUTE_NAME='cp-console-iam-provider'
    ID_PROVIDER_PATH='/idprovider/'
    ID_MGMT_ROUTE_NAME='cp-console-iam-idmgmt'
    ID_MGMT_PATH='/idmgmt/'
    project_name=$TARGET_PROJECT_NAME
    # Check whether the BAI is separation of operators and operands.
    check_bai_separate_operand $TARGET_PROJECT_NAME
    bai_operator_csv_name_target_ns=$(${CLI_CMD} get csv -n $TARGET_PROJECT_NAME --no-headers --ignore-not-found | grep "IBM Business Automation Insights" | awk '{print $1}')
    if [[ (! -z $bai_operator_csv_name_target_ns) ]]; then
        success "Found IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        ALL_NAMESPACE_FLAG="No"
        TEMP_OPERATOR_PROJECT_NAME=$TARGET_PROJECT_NAME
    else
        fail "Failed to Find IBM Cloud Pak for Business Automation Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        exit
    fi
    # Get value of bai_original_csv_ver_for_upgrade_script
    ibm_bai_shared_info_cm=$(${CLI_CMD} get configmap ibm-bai-shared-info --no-headers --ignore-not-found -n $BAI_SERVICES_NS)
    if [[ ! -z $ibm_bai_shared_info_cm ]]; then
        tmp_csv_val=$(${CLI_CMD} get configmap ibm-bai-shared-info -n $BAI_SERVICES_NS -o jsonpath='{.data.bai_original_csv_ver_for_upgrade_script}')
        if [[ ! -z $tmp_csv_val ]]; then
            bai_original_csv_ver_for_upgrade_script=$tmp_csv_val
        else
            fail "Configmap ibm-bai-shared-info created incorrectly, run upgradeOperator mode to fix this issue."
            exit
        fi
    else
        fail "Failed to find IBM Business Automation Insights Operator deployed in the project \"$TARGET_PROJECT_NAME\"."
        exit
    fi
    insightsengine_cr_name=$(${CLI_CMD} get insightsengine -n $BAI_SERVICES_NS --no-headers --ignore-not-found | awk '{print $1}')
    if [ ! -z $insightsengine_cr_name ]; then
        info "Scaling up \"IBM Business Automation Insights \" operator"
        ${CLI_CMD} scale --replicas=1 deployment ibm-bai-insights-engine-operator -n $TEMP_OPERATOR_PROJECT_NAME >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            sleep 1
        else
            fail "Failed to scale up \"IBM Business Automation Insights (BAI)\" operator"
        fi

        info "Scaling up \"IBM Business Automation Insights Foundation\" operator"
        ${CLI_CMD} scale --replicas=1 deployment ibm-bai-foundation-operator -n $TEMP_OPERATOR_PROJECT_NAME >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            sleep 1
        else
            fail "Failed to scale up \"IBM Business Automation Insights (BAI) Foundation\" operator"
        fi

        cr_version=$(${CLI_CMD} get insightsengine $insightsengine_cr_name -n $BAI_SERVICES_NS -o yaml | ${YQ_CMD} r - spec.appVersion)
        if [[ $cr_version != "${BAI_RELEASE_BASE}" ]]; then
            fail "The release version: \"$cr_version\" in insightsengine custom resource \"$insightsengine_cr_name\" is not correct, please apply new version of the custom resource file first."
            exit 1
        fi
    fi
    # check for zenStatus and currentverison for zen

    zen_service_name=$(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $BAI_SERVICES_NS |awk '{print $1}')
    if [[ ! -z "$zen_service_name" ]]; then
        clear
        maxRetry=360
        for ((retry=0;retry<=${maxRetry};retry++)); do
            # # As workaround for https://github.ibm.com/IBMPrivateCloud/roadmap/issues/64207
            # # update secret postgresql-operator-controller-manager-config in <bai> namespace and/or ibm-common-services namespace and add this annotation ibm-bts/skip-updates: "true"
            # if ${CLI_CMD} get secret -n $BAI_SERVICES_NS --no-headers --ignore-not-found | grep postgresql-operator-controller-manager-config >/dev/null 2>&1; then
            #     ${CLI_CMD} patch secret postgresql-operator-controller-manager-config -n $BAI_SERVICES_NS -p '{"metadata": {"annotations": {"ibm-bts/skip-updates": "true"}}}' >/dev/null 2>&1
            # fi

            zenservice_version=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.currentVersion}')
            isCompleted=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.zenStatus}')
            isProgressDone=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $BAI_SERVICES_NS -o jsonpath='{.status.Progress}')

            if [[ "$isCompleted" != "Completed" || "$isProgressDone" != "100%" || "$zenservice_version" != "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                clear
                BAI_DEPLOYMENT_STATUS="Waiting for the zenService to be ready (could take up to 120 minutes) before upgrade the BAI Standalone capabilities..."
                printf '%s %s\n' "$(date)" "[refresh interval: 60s]"
                echo -en "[Press Ctrl+C to exit] \t\t"
                printf "\n"
                echo "${YELLOW_TEXT}$BAI_DEPLOYMENT_STATUS${RESET_TEXT}"
                printHeaderMessage "BAI Standalone Upgrade Status"
                if [[ "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Version (Expected - ${ZEN_OPERATOR_VERSION//v/})       : ${GREEN_TEXT}$zenservice_version${RESET_TEXT}"
                else
                    echo "zenService Version (Expected - ${ZEN_OPERATOR_VERSION//v/})       : ${RED_TEXT}$zenservice_version${RESET_TEXT}"
                fi
                if [[ "$isCompleted" == "Completed" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Status (Expected - Completed)    : ${GREEN_TEXT}$isCompleted${RESET_TEXT}"
                else
                    echo "zenService Status (Expected - Completed)    : ${RED_TEXT}$isCompleted${RESET_TEXT}"
                fi

                if [[ "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Progress (Expected - 100%)       : ${GREEN_TEXT}$isProgressDone${RESET_TEXT}"
                else
                    echo "zenService Progress (Expected - 100%)       : ${RED_TEXT}$isProgressDone${RESET_TEXT}"
                fi
                sleep 60
            elif [[ "$isCompleted" == "Completed" && "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                break
            elif [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for the Zen Service to start"
                echo -e "\x1B[1mPlease check the status of the Zen Service\x1B[0m"
                printf "\n"
                exit 1
            fi
        done
        BAI_DEPLOYMENT_STATUS="The Zen Service (${ZEN_OPERATOR_VERSION//v/}) is ready for BAI Standalone"
        printf '%s %s\n' "$(date)" "[refresh interval: 30s]"
        echo -en "[Press Ctrl+C to exit] \t\t"
        printf "\n"
        echo "${YELLOW_TEXT}$BAI_DEPLOYMENT_STATUS${RESET_TEXT}"
        info "Starting all BAI Standalone Operators to upgrade BAI Standalone capabilities"
        printHeaderMessage "BAI Standalone Upgrade Status"
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

    else
        fail "No found the zenService in the project \"$BAI_SERVICES_NS\", exit..."
        echo "****************************************************************************"
        exit 1
    fi

    while true
    do
        printf '%s\n' "$(show_bai_upgrade_status)"
        sleep 30
    done
fi

