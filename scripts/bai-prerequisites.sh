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
    echo -e "\nUsage: bai-prerequisites.sh -m [modetype] -n [BAI-NAMESPACE] \n"
    echo "Options:"
    echo "  -h  Display help"
    echo "  -m  The valid mode types are: [property], [generate], or [validate]"
    echo "  -n  The target namespace of the BAI deployment."
    echo ""
    echo "  STEP1: Run the script in [property] mode. It creates property files (LDAP property file) with default values (BASE DN/BIND DN ...)."
    echo "  STEP2: Modify the LDAP/user property files with your values."
    echo "  STEP3: Run the script in [generate] mode. Generates the YAML templates for the secrets based on the values in the property files."
    echo "  STEP4: Create the secrets by using the modified YAML templates for the secrets."
    echo "  STEP5: Run the script in [validate] mode. Checks the secrets are created before you install IBM Business Automation Insights."
}


# Function only used in select_fips_enable which was for enabling FIPS and is not something we ask for anymore 
#function select_project() {
#    while [[ $TARGET_PROJECT_NAME == "" ]]; 
#    do
#        printf "\n"
#        echo -e "\x1B[1mWhere do you want to deploy IBM Business Automation Insights stand-alone?\x1B[0m"
#        read -p "Enter the name for an existing project (namespace): " TARGET_PROJECT_NAME
#        if [ -z "$TARGET_PROJECT_NAME" ]; then
#            echo -e "\x1B[1;31mEnter a valid project name, project name can not be blank\x1B[0m"
#        elif [[ "$TARGET_PROJECT_NAME" == openshift* ]]; then
#            echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
#            TARGET_PROJECT_NAME=""
#        elif [[ "$TARGET_PROJECT_NAME" == kube* ]]; then
#            echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
#            TARGET_PROJECT_NAME=""
#        else
#            isProjExists=`kubectl get namespace $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1
#
#            if [ "$isProjExists" -ne 2 ] ; then
#                echo -e "\x1B[1;31mInvalid project name, please enter a existing project name ...\x1B[0m"
#                TARGET_PROJECT_NAME=""
#            else
#                echo -e "\x1B[1mUsing project ${TARGET_PROJECT_NAME}...\x1B[0m"
#            fi
#        fi
#    done
#}


# Enabling FIPS is not something we ask for anymore
#function select_fips_enable(){
#    select_project
#    all_fips_enabled_flag=$(kubectl get configmap bai-fips-status --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME -o jsonpath={.data.all-fips-enabled})
#    if [ -z $all_fips_enabled_flag ]; then
#        warning "Configmap \"bai-fips-status\" not found in project \"$TARGET_PROJECT_NAME\". setting BAI_STANDALONE.ENABLE_FIPS as \"false\" by default in the \"BAI_user_profile.property\""
#        FIPS_ENABLED="false"
#    elif [[ "$all_fips_enabled_flag" == "Yes" ]]; then
#        printf "\n"
#        while true; do
#            printf "\x1B[1mYour OCP cluster has FIPS enabled, do you want to enable FIPS with this BAI stand-alone deployment？\x1B[0m (Yes/No, default: No): "
#            read -rp "" ans
#            case "$ans" in
#            "y"|"Y"|"yes"|"Yes"|"YES")
#                if [[ (" ${optional_component_cr_arr[@]}" =~ "bai") && (! " ${optional_component_cr_arr[@]}" =~ "kafka") ]]; then
#                    FIPS_ENABLED="false"
#                    msg_tmp="BAI"
#                elif [[ (! " ${optional_component_cr_arr[@]}" =~ "bai") && (" ${optional_component_cr_arr[@]}" =~ "kafka") ]]; then
#                    FIPS_ENABLED="false"
#                    msg_tmp="Exposed Kafka Services"
#                elif [[  (" ${optional_component_cr_arr[@]}" =~ "bai") && (" ${optional_component_cr_arr[@]}" =~ "kafka") ]]; then
#                    FIPS_ENABLED="false"
#                    msg_tmp="BAI/Exposed Kafka Services"
#                else
#                    FIPS_ENABLED="true"
#                fi
#                if [[ $FIPS_ENABLED == "false" ]]; then
#                    echo -e "${YELLOW_TEXT}[ATTENTION]: ${RESET_TEXT}\x1B[1;31mBecause \"$msg_tmp\" selected does not support FIPS enabled, the script will disable FIPS mode for this BAI stand-alone deployment (shared_configuration.enable_fips: false).\x1B[0m"
#                    sleep 3
#                fi
#                break
#                ;;
#            "n"|"N"|"no"|"No"|"NO"|"")
#                FIPS_ENABLED="false"
#                break
#                ;;
#            *)
#                echo -e "Answer must be \"Yes\" or \"No\"\n"
#                ;;
#            esac
#        done
#    elif [[ "$all_fips_enabled_flag" == "No" ]]; then
#        FIPS_ENABLED="false"
#    fi
#}


# This function helps parse arguments that are passed to the script, checks and assigns runtime mode and target namespace variables based on the -m and -n parameters passed
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
            if [[ $RUNTIME_MODE == "property" || $RUNTIME_MODE == "generate" || $RUNTIME_MODE == "validate" ]]; then
                echo
            else
                msg "Use a valid value: -m [property] or [generate] or [validate]"
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
                # Check cluster login
                check_cluster_login
                # Check project name
                isProjExists=`kubectl get namespace $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ $isProjExists -ne 2 ] ; then
                    echo -e "\x1B[1;31mInvalid project name \"$TARGET_PROJECT_NAME\", please set a existing project name.\x1B[0m"
                    exit 1
                fi
                echo -n
                ;;
            esac
            ;;
        -h | --help | \?)
            show_help
            exit 0
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


########################################################################
#### Begin - Main code for the 3 modes of the prerequisites scripts ####
########################################################################

parse_arguments "$@"

###################################################################################
##### Begin - Checks for required parameters to be passed #####
###################################################################################
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

###################################################################################
##### End - Checks for required parameters to be passed #####
###################################################################################

###################################################################################
##### Begin - Logging set up #####
###################################################################################

# Log files to be generated in the folder specific to the project being used with the scripts
# For DBACLD-166508
save_log "bai-script-logs/project/$TARGET_PROJECT_NAME" "bai-prerequisites-log"
trap cleanup_log EXIT

info "The bai-prerequisite script is currently being executed in the ${RUNTIME_MODE} mode"
printf "\n"

###################################################################################
##### END - Logging set up #####
###################################################################################

# Import common utilities and environment variables
source ${CUR_DIR}/helper/common.sh $TARGET_PROJECT_NAME

clear


###################################################################################
##### Begin - property Mode specific logic #####
###################################################################################

if [[ $RUNTIME_MODE == "property" ]]; then
    # Import the functions required for the property runtime mode
    source ${CUR_DIR}/helper/bai-prerequisites-modes/property-mode.sh

    # Check for separation of duties
    check_bai_separate_operand $TARGET_PROJECT_NAME # Function Definition can be found in helper/common.sh

    prompt_license "Starting the script to generate the IBM Business Automation Insights standalone property files..." "https://www.ibm.com/support/customer/csol/terms/?id=L-ACQV-MS7LQZ&lc=en" # Function Definition can be found in helper/common.sh
    input_information # Function Definition can be found in helper/bai-prerequisites-modes/property-mode.sh
    create_property_file # Function Definition can be found in helper/bai-prerequisites-modes/property-mode.sh
    clean_up_temp_file # Function Definition can be found in helper/common.sh
fi

###################################################################################
##### End - property Mode specific logic #####
###################################################################################



###################################################################################
##### Begin - generate Mode specific logic #####
###################################################################################

if [[ $RUNTIME_MODE == "generate" ]]; then
    # Import the functions required for the generate runtime mode
    source ${CUR_DIR}/helper/bai-prerequisites-modes/generate-mode.sh

    # Check for separation of duties
    check_bai_separate_operand $TARGET_PROJECT_NAME # Function Definition can be found in helper/common.sh
    
    # load properties required for generate mode
    load_properties_from_temp_file # Function Definition can be found in helper/common.sh
    check_property_file #Function Definition can be found in helper/bai-prerequisites-modes/generate-mode.sh
    # In BAI S the only potential secret required is
    if [[ $selected_ldap_flag == "Yes" || $EXTERNAL_POSTGRESDB_FOR_IM_FLAG == "true" || $EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG == "true" || $EXTERNAL_POSTGRESDB_FOR_BTS_FLAG == "true" ]]; then
        # function to generate all required secrets 
        generate_secrets # Function Definition can be found in helper/bai-prerequisites-modes/generate-mode.sh
        clean_up_temp_file # Function Definition can be found in helper/common.sh
        generate_create_secret_script # Function Definition can be found in helper/bai-prerequisites-modes/generate-mode.sh
    else
        info "Based on the property files, there are no secret templates generated."
        info "[NEXT_STEPS]: Proceed with executing the bai-prerequisites.sh script in validate mode."
        exit
    fi
fi

###################################################################################
##### End - generate Mode specific logic #####
###################################################################################



###################################################################################
##### Begin - validate Mode specific logic #####
###################################################################################

if [[ $RUNTIME_MODE == "validate" ]]; then
    # Import the functions required for the generate runtime mode
    source ${CUR_DIR}/helper/bai-prerequisites-modes/validate-mode.sh

    echo  "*****************************************************************"
    echo  " Validating the prerequisites before you install BAI stand-alone "
    echo  "*****************************************************************"
    # Check for separation of duties
    check_bai_separate_operand $TARGET_PROJECT_NAME # Function Definition can be found in helper/common.sh

    validate_utility_tools_for_validate_mode # Function Definition can be found in helper/bai-prerequisites-modes/validate-mode.sh
    load_properties_from_temp_file # Function Definition can be found in helper/common.sh
    validate_prerequisites # Function Definition can be found in helper/bai-prerequisites-modes/validate-mode.sh
fi

###################################################################################
##### END - validate Mode specific logic #####
###################################################################################



########################################################################
#### END - Main code for the 3 modes of the prerequisites scripts   ####
########################################################################
