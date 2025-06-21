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


# Function that displays the information required for the help ( -h ) mode 
function show_help() {
        echo
    echo "Usage:"
    echo
    echo " ${CUR_DIR}/bai-deployment.sh -m [modetype] -n <BAI_NAMESPACE>"
    echo " ${CUR_DIR}/bai-deployment.sh -n <BAI_NAMESPACE>"
    echo
    echo "Options:"
    echo
    echo "  -h  Display help."
    echo
    echo "  -m  The valid mode types are: [upgradeOperator], [upgradeOperatorStatus], [upgradeDeployment], and [upgradeDeploymentStatus]."
    echo
    echo "  -n  Required: The target namespace of the BAI Standalone deployment. "
    echo "                If BAI Standalone is deployed using separate namespaces for operators and operands/services and the script is being used for upgrade, the value is the namespace where the BAI Standalone operators are deployed"
    echo "                If BAI Standalone is deployed using separate namespaces for operators and operands/services and the script is being used for generating a custom resource file, the value is the namespace where BAI Standalone operands/services are to be deployed."
    echo
    echo "  -i  Optional: Operator image name. By default, it is cp.icr.io/cp/cp4a/icp4a-operator:$BAI_RELEASE_BASE."
    echo
    echo "  -p  Optional: Pull secret to use to connect to the registry. By default, it is ibm-entitlement-key."
    echo
    echo "  --ingress  Optional: Set this flag if you want to generate the ingress templates required for platform type -> Other - Cloud Native Computing Foundation ( CNCF )"
    echo
    echo "  --enable-private-catalog Optional: Set this flag to switch CatalogSource from global to namespace-scoped. Default is in the openshift-marketplace namespace."
    echo
    echo "Additional Information:"
    echo
    echo "  ${YELLOW_TEXT}* Running the script to create a custom resource file for a new BAI Standalone deployment:${RESET_TEXT}"
    echo "      - STEP 1: Run the script with \"-n <BAI_NAMESPACE>\"."
    echo "  ${YELLOW_TEXT}* Running the script to upgrade a BAI Standalone deployment from 24.0.1.X to $BAI_RELEASE_BASE GA/$BAI_RELEASE_BASE.X. You must run the modes in the following order:${RESET_TEXT}"
    echo "      - STEP 1: Run the script in [upgradeOperator] mode to upgrade the BAI Standalone operator."
    echo "      - STEP 2: Run the script in [upgradeOperatorStatus] mode to check that the upgrade of the BAI Standalone operator and its dependencies was successful."
    echo "      - STEP 3: Run the script in [upgradeDeployment] mode to upgrade the BAI Standalone deployment."
    echo "      - STEP 4: Run the script in [upgradeDeploymentStatus] mode to check that the upgrade of the BAI Standalone deployment was successful."
    echo "  ${YELLOW_TEXT}* Running the script to upgrade a BAI Standalone deployment from $BAI_RELEASE_BASE GA/$BAI_RELEASE_BASE.X to $BAI_RELEASE_BASE.X. You must run the modes in the following order:${RESET_TEXT}"
    echo "      - STEP 1: Run the script in [upgradeOperator] mode to upgrade the BAI Standalone operator."
    echo "      - STEP 2: Run the script in [upgradeOperatorStatus] mode to check that the upgrade of the BAI Standalone operator and its dependencies was successful."
    echo "      - STEP 3: Run the script in [upgradeDeploymentStatus] mode to check that the upgrade of the BAI Standalone deployment was successful."

}

function parse_arguments() {
    # process options
    while [[ "$@" != "" ]]; do
        case "$1" in
        -m)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -m flag requires an argument"
                exit 1
            fi
            RUNTIME_MODE=$1
            if [[ $RUNTIME_MODE == "upgradeOperator" || $RUNTIME_MODE == "upgradeOperatorStatus" || $RUNTIME_MODE == "upgradeDeployment" || $RUNTIME_MODE == "upgradeDeploymentStatus" ]]; then
                echo -n
            else
                msg "Provide a valid argument for -m: [upgradeOperator] or [upgradeOperatorStatus] or [upgradeDeployment] [upgradeDeploymentStatus]"
                exit -1
            fi
            ;;
        -s)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -s flag requires an argument"
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
                echo "Invalid option: -n flag requires an argument"
                exit 1
            fi
            TARGET_PROJECT_NAME=$1
            validate_namespace # Function that validates the namespace, it also internally checks for cluster login. Defintion found in helper/common.sh
            ;;
        -i)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -i flag requires an argument"
                exit 1
            fi
            IMAGEREGISTRY=$1
            ;;
        -p)
            shift
            if [ -z $1 ]; then
                echo "Invalid option: -p flag requires an argument"
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
        #Hidden flag if ingress files should be generated without tls for CNCF
        -t)
            shift
            tls_flag=false
            ;;
        # adding a flag to generate ingress for CNCF
        # DBACLD-168345
        --ingress)
        INGRESS_MODE=true
        ;;
        dev)
        SCRIPT_MODE="dev"
        ;;
        review)
        SCRIPT_MODE="review"
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

# Adding a function that parses args that are passed when the script is executed
# This function along with the check below makes sure that namespace argument is mandatory regardless of whether the mode argument is passed or not
# DBACLD-161415
parse_arguments "$@"

# Adding a check for requiring the -n parameter
# DBACLD-161415
if [[ -z "$TARGET_PROJECT_NAME" ]]; then
    echo "\x1B[1;31m\"-n\" is a required argument.Input a namespace value for \"-n <BAI_NAMESPACE>\" argument.\n\x1B[0m"
    show_help
    exit 1
fi


# Import common utilities and environment variables
source ${CUR_DIR}/helper/common.sh $TARGET_PROJECT_NAME

# Import variables for property file
source ${CUR_DIR}/helper/bai-property.sh

DOCKER_RES_SECRET_NAME="ibm-entitlement-key"
DOCKER_REG_USER=""

if [[ "$SCRIPT_MODE" == "dev" || "$SCRIPT_MODE" == "review" ]] # During dev, OLM uses stage image repo
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
# CR to be generated in a folder specific to the project name
# for DBACLD-166508
FINAL_CR_FOLDER=${CUR_DIR}/generated-cr/project/$TARGET_PROJECT_NAME

DEPLOY_TYPE_IN_FILE_NAME="" # Default value is empty





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

FOUNDATION_CR_SELECTED=""
optional_component_arr=()
optional_component_cr_arr=()
foundation_component_arr=()


# This function is never called , so commenting it out
#function select_installation_type(){
#    COLUMNS=12
#    echo -e "\x1B[1mIs this a new installation or an existing installation?\x1B[0m"
#    options=("New" "Existing")
#    PS3='Enter a valid option [1 to 2]: '
#    select opt in "${options[@]}"
#    do
#        case $opt in
#            "New")
#                INSTALLATION_TYPE="new"
#                break
#                ;;
#            "Existing")
#                INSTALLATION_TYPE="existing"
#                mkdir -p $TEMP_FOLDER >/dev/null 2>&1
#                mkdir -p $BAK_FOLDER >/dev/null 2>&1
#                mkdir -p $FINAL_CR_FOLDER >/dev/null 2>&1
#                get_existing_pattern_name
#               break
#                ;;
#            *) echo "invalid option $REPLY";;
#        esac
#    done
#    if [[ "${INSTALLATION_TYPE}" == "new" ]]; then
#        clean_up_temp_file
#        rm -rf $BAK_FOLDER >/dev/null 2>&1
#        rm -rf $FINAL_CR_FOLDER >/dev/null 2>&1
#
#        mkdir -p $TEMP_FOLDER >/dev/null 2>&1
#        mkdir -p $BAK_FOLDER >/dev/null 2>&1
#        mkdir -p $FINAL_CR_FOLDER >/dev/null 2>&1
#    fi
#}

# This function is never called , so commenting it out
#function select_ocp_olm(){
#    printf "\n"
#    while true; do
#        printf "\x1B[1mAre you using the OCP Catalog (OLM) to perform this install? (Yes/No, default: No) \x1B[0m"
#
#        read -rp "" ans
#        case "$ans" in
#        "y"|"Y"|"yes"|"Yes"|"YES")
#            SCRIPT_MODE="OLM"
#            break
#            ;;
#        "n"|"N"|"no"|"No"|"NO"|"")
#            break
#            ;;
#        *)
#            echo -e "Answer must be \"Yes\" or \"No\"\n"
#            ;;
#        esac
#    done
#}

# This function is never called , so commenting it out
#function select_deployment_type(){
#    printf "\n"
#    echo -e "\x1B[1mWhat type of deployment is being performed?\x1B[0m"
#    COLUMNS=12
#    options_var=("Production")
#    for i in ${!options_var[@]}; do
#        if [[ "${options_var[i]}" == "Production" ]]; then
#            printf "%1d) %s \x1B[1m%s\x1B[0m\n" $((i+1)) "${options_var[i]}"  "(Selected)"
#        else
#            printf "%1d) %s\n" $((i+1)) "${options_var[i]}"
#        fi
#    done
#    echo -e "${YELLOW_TEXT}BAI standalone only supports production deployment${RESET_TEXT}"
#    prompt_press_any_key_to_continue
#}

# This function is never called , so commenting it out
#function select_upgrade_mode(){
#    printf "\n"
#    COLUMNS=12
#    echo -e "\x1B[1mWhich migration mode for the IBM Foundational Services you want to select? \x1B[0m"
#    options=("Shared to Dedicated (Incoming)" "Shared to Shared")
#    PS3='Enter a valid option [1 to 2]: '
#    select opt in "${options[@]}"
#    do
#        case $opt in
#            "Shared to Dedicated"*)
#                UPGRADE_MODE="shared2dedicated"
#                warning "Implementing upgrade from shared to dedicated"
#                exit 1
#                ;;
#            "Shared to Shared")
#                UPGRADE_MODE="shared2shared"
#                break
#                ;;
#            *) echo "invalid option $REPLY";;
#        esac
#    done
#}

# Function called during select_installation_type which is not used anymore so commenting it out
#function clean_up_temp_file(){
#    local files=()
#    if [[ -d $TEMP_FOLDER ]]; then
#        files=($(find $TEMP_FOLDER -name '*.yaml'))
#        for item in ${files[*]}
#        do
#            rm -rf $item >/dev/null 2>&1
#        done
#        
#        files=($(find $TEMP_FOLDER -name '*.swp'))
#        for item in ${files[*]}
#        do
#            rm -rf $item >/dev/null 2>&1
#        done
#    fi
#}


# This function is never called , so commenting it out
#function startup_operator(){
#    # scale up BAI standalone operators
#    local project_name=$1
#    local run_mode=$2  # silent
#    info "Scaling up \"IBM Business Automation Insights standalone\" operator"
#    kubectl scale --replicas=1 deployment ibm-bai-insights-engine-operator -n $project_name >/dev/null 2>&1
#    if [ $? -eq 0 ]; then
#        sleep 1
#        if [[ -z "$run_mode" ]]; then
#            echo "Done!"
#        fi
#    else
#        fail "Failed to scale up \"IBM Business Automation Insights standalone\" operator"
#    fi
#
#
#    info "Scaling up \"IBM BAI standalone Foundation\" operator"
#    kubectl scale --replicas=1 deployment ibm-bai-foundation-operator -n $project_name >/dev/null 2>&1
#    if [ $? -eq 0 ]; then
#        sleep 1
#        if [[ -z "$run_mode" ]]; then
#            echo "Done!"
#        fi
#    else
#        fail "Failed to scale up \"IBM BAI standalone Foundation\" operator"
#    fi
#}





########################################################################
#### Begin - Main code blocks for the different modes of the script ####
########################################################################


###################################################################################
##### Begin - Logging set up #####
###################################################################################

# Log files to be generated in the folder specific to the project being used with the scripts
# For DBACLD-166508
save_log "bai-script-logs/project/$TARGET_PROJECT_NAME" "bai-deployment-log"
trap cleanup_log EXIT

###################################################################################
##### END - Logging set up #####
###################################################################################


# Import upgrade upgrade_check_version.sh script
source ${CUR_DIR}/helper/upgrade/upgrade_check_status.sh



###################################################################################
### BEGIN - Code for generating ingress templates (--ingress flag being passed) ###
###################################################################################

# IF the INGRESS_MODE variable is set that means the user has used --ingress flag and wants to generate ingress template files for CNCF
if [[ ! -z "$INGRESS_MODE" ]]; then

    # IF tls flag is not passed, we default the ingress files to be generated with tls
    if [[ -z "$tls_flag" ]]; then
        tls_flag=true
    fi
    # Import the functions required when ingress flag is passed to the script
    source ${CUR_DIR}/helper/bai-deployment-modes/ingress-mode.sh
    generate_ingress_templates $tls_flag # function definition can be found in helper/bai-deployment-modes/ingress-mode.sh
fi

###################################################################################
### END - Code for generating ingress templates (--ingress flag being passed) ###
###################################################################################


###################################################################################
### BEGIN - Code for generating the CR for fresh install (no flag being passed) ###
###################################################################################



if [[ ($SCRIPT_MODE == "" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "dev" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "review" && $RUNTIME_MODE == "") ]]; then
    # Import the functions required for fresh install
    source ${CUR_DIR}/helper/bai-deployment-modes/fresh-install.sh
    fresh_install
fi

###################################################################################
### END - Code for generating the CR for fresh install (no flag being passed) ###
###################################################################################


###########################################################################################
### BEGIN - Code for upgradeDeployment mode (-m upgradeDeployment being passed)        ###
###########################################################################################

# This runtime does the upgrade of BAI Standalone operators
if [ "$RUNTIME_MODE" == "upgradeOperator" ]; then
    # Import the functions required for the upgradeOperator runtime mode
    source ${CUR_DIR}/helper/bai-deployment-modes/upgradeOperator-mode.sh
    upgradeoperator_mode
fi
###########################################################################################
### END - Code for upgradeDeployment mode (-m upgradeDeployment being passed)           ###
###########################################################################################


###########################################################################################
### BEGIN - Code for upgradeOperatorStatus mode (-m upgradeOperatorStatus being passed) ###
###########################################################################################


#This runtime is to check the operator status after the upgrade is completed
if [ "$RUNTIME_MODE" == "upgradeOperatorStatus" ]; then
    # Import the functions required for the upgradeOperatorStatus runtime mode
    source ${CUR_DIR}/helper/bai-deployment-modes/upgradeOperatorStatus-mode.sh
    upgradeoperatorstatus_mode
fi

###########################################################################################
### END - Code for upgradeOperatorStatus mode (-m upgradeOperatorStatus being passed)   ###
###########################################################################################



###########################################################################################
### BEGIN - Code for upgradeDeployment mode (-m upgradeDeployment being passed)        ###
###########################################################################################

if [ "$RUNTIME_MODE" == "upgradeDeployment" ]; then
    # Import the functions required for the upgradeDeployment runtime mode
    source ${CUR_DIR}/helper/bai-deployment-modes/upgradeDeployment-mode.sh
    upgradedeployment_mode
fi

###########################################################################################
### END - Code for upgradeDeployment mode (-m upgradeDeployment being passed)           ###
###########################################################################################



################################################################################################
### BEGIN - Code for upgradeDeploymentStatus mode (-m upgradeDeploymentStatus being passed)  ###
################################################################################################

# This mode is for upgradeDeploymentStatus , shows the upgrade status for zen and also how to track the deployment status 
# Currently the BAI standalone operator does not have enough code in place for the correct status variables in the CR for components that we use for showing the status of components
if [[ "$RUNTIME_MODE" == "upgradeDeploymentStatus" ]]; then
    # Import the functions required for the upgradeDeployment runtime mode
    source ${CUR_DIR}/helper/bai-deployment-modes/upgradeDeploymentStatus-mode.sh
    upgradedeploymentstatus_mode
fi

##############################################################################################
### END - Code for upgradeDeploymentStatus mode (-m upgradeDeploymentStatus being passed)  ###
##############################################################################################