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
# Script to apply Turbonomic OperatorResourceMapping (ORM) for BAI
# This script works for both OCP and CNCF platforms
###############################################################################

CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BAI_NAMESPACE=""
HELP=""
UNINSTALL=""
INSIGHTS_ENGINE_CR_NAME=""
CLI_CMD=""
PLATFORM_SELECTED=""

function info() { printf '%b\n' "\033[34m[INFO]\033[0m $1"; }
function success() { printf '%b\n' "\033[32m[SUCCESS]\033[0m $1"; }
function warning() { printf '%b\n' "\033[33m[WARNING]\033[0m $1"; }
function error() { printf '%b\n' "\033[31m[ERROR]\033[0m $1"; exit 1; }


function check_cluster_login() {
    if [[ "$CLI_CMD" == "oc" ]]; then
        ${CLI_CMD} whoami >/dev/null 2>&1
    else
        ${CLI_CMD} auth whoami >/dev/null 2>&1
    fi
    
    if [ $? -gt 0 ]; then
        error "Not logged in to a cluster. Please login to a cluster before running this script."
        exit 1
    fi
}

function select_platform(){
    printf "\n"
    COLUMNS=12
    printf '%b\n' "\x1B[1mSelect the cloud platform where BAI has been deployed: \x1B[0m"

    otherOption="Other - Cloud Native Computing Foundation ( CNCF )"
    options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "$otherOption")
    PS3='Enter a valid option [1 to 3]: '

    select opt in "${options[@]}"
    do
        case $opt in
            "RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud")
                PLATFORM_SELECTED="ROKS"
                break
                ;;
            "Openshift Container Platform (OCP) - Private Cloud")
                PLATFORM_SELECTED="OCP"
                break
                ;;
            "$otherOption")
                PLATFORM_SELECTED="other"
                break
                ;;
            *) echo "invalid option $REPLY";;
        esac
    done

    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        CLI_CMD=oc
    elif [[ "$PLATFORM_SELECTED" == "other" ]]; then
        CLI_CMD=kubectl
    fi
}

function cli_check(){
    if ! [ -x "$(command -v ${CLI_CMD})" ]; then
        error "OpenShift/Kubectl CLI is not installed. Please install OpenShift/Kubectl CLI before running this script."
    fi
}

function parse_arguments() {
  while getopts 'n:hU' OPTION; do
    case "$OPTION" in
      n) BAI_NAMESPACE=$OPTARG ;;
      h) HELP="true" ;;
      U) UNINSTALL="true" ;;
      ?) HELP="true" ;;
    esac
  done
  shift "$(($OPTIND - 1))"
}

function validate_namespace() {
  if [ -z "$BAI_NAMESPACE" ]; then
    error "BAI namespace required. Use -n <namespace>."
  fi

  if [ -z "$(${CLI_CMD} get namespace "${BAI_NAMESPACE}" 2>/dev/null)" ]; then
    error "Namespace ${BAI_NAMESPACE} does not exist. Specify an existing namespace where BAI is installed."
  fi
}

function detect_cr_name() {
  # Detect InsightsEngine CR
  local insights_engine_cr=$(${CLI_CMD} get insightsengine -n "$BAI_NAMESPACE" --no-headers --ignore-not-found 2>/dev/null | awk '{print $1}')
  if [ -n "$insights_engine_cr" ]; then
    INSIGHTS_ENGINE_CR_NAME="$insights_engine_cr"
    info "Detected InsightsEngine CR: $INSIGHTS_ENGINE_CR_NAME"
  else
    error "Could not detect InsightsEngine CR in namespace ${BAI_NAMESPACE}."
  fi
}

function apply_orm() {
  local found=0
  
  info "Applying ORM to namespace: ${BAI_NAMESPACE}"
  info "Using InsightsEngine CR name: ${INSIGHTS_ENGINE_CR_NAME}"
  
  for f in "$CUR_DIR"/ORMs/*.yaml; do
    [ -e "$f" ] || continue
    found=1
    local filename=$(basename "$f")
    
    info "Applying $filename with CR name: $INSIGHTS_ENGINE_CR_NAME ..."
    if sed -e "s/{{ placeholder_namespace }}/$BAI_NAMESPACE/g" \
           -e "s/{{ meta.name }}/$INSIGHTS_ENGINE_CR_NAME/g" "$f" \
       | $CLI_CMD -n "$BAI_NAMESPACE" apply -f - ; then
      success "Applied $filename"
    else
      error "Failed to apply $filename"
    fi
  done
  
  [[ $found -eq 0 ]] && error "No ORM YAML files found in $CUR_DIR/ORMs"
  
  success "ORM applied successfully."
}

function uninstall_orm() {
  local found=0
  
  info "Uninstalling ORM from namespace: ${BAI_NAMESPACE}"
  
  for f in "$CUR_DIR"/ORMs/*.yaml; do
    [ -e "$f" ] || continue
    found=1
    orm_name=$(awk '/^kind:[[:space:]]*OperatorResourceMapping/{f=1} f && /^[[:space:]]*name:[[:space:]]*/{gsub(/^[[:space:]]*name:[[:space:]]*/, ""); print; exit}' "$f")
    orm_exists=$(${CLI_CMD} get operatorresourcemapping "$orm_name" -n "$BAI_NAMESPACE" --ignore-not-found 2>/dev/null)
    if [[ -n "$orm_name" ]] && [[ -n "$orm_exists" ]]; then
      info "Deleting ORM: $orm_name"
      if $CLI_CMD -n "$BAI_NAMESPACE" delete operatorresourcemapping "$orm_name" --ignore-not-found ; then
        success "Deleted ORM: $orm_name"
      else
        warning "Failed to delete ORM: $orm_name"
      fi
    else
      info "ORM $orm_name not found or already deleted"
    fi
  done
  
  [[ $found -eq 0 ]] && error "No ORM YAML files found in $CUR_DIR/ORMs"
  
  success "Uninstall complete."
}

parse_arguments "$@"

if [[ $HELP == "true" ]]; then
  echo "This script applies or uninstalls Turbonomic OperatorResourceMapping (ORM) for BAI."
  echo "Works with both OpenShift (oc) and CNCF Kubernetes (kubectl)."
  echo ""
  echo "Usage: $0 -n <namespace> [-U] [-h]"
  echo ""
  echo "Options:"
  echo "  -n  Target BAI namespace (required)"
  echo "  -U  Uninstall ORM"
  echo "  -h  Display help"
  echo ""
  echo "Examples:"
  echo "  Apply ORM:     $0 -n bai-namespace"
  echo "  Uninstall ORM: $0 -n bai-namespace -U"
  exit 0
fi

select_platform
cli_check

info "Using CLI: ${CLI_CMD}"
check_cluster_login
validate_namespace
detect_cr_name

if [[ "$UNINSTALL" == "true" ]]; then
  uninstall_orm
else
  apply_orm
fi
