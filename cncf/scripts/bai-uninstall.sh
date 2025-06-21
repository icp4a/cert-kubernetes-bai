#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${current_dir}/bai-utils.sh"

function show_help() {
    echo "Usage: $0 [-h] -n <bai-namespace>"
    echo "  -n <bai-namespace>    Namespace from where BAI will be uninstalled"
}

bai_namespace=""
is_openshift=false

while getopts "h?n:f" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    n)  bai_namespace=$OPTARG
        ;;
    esac
done

if [[ -z ${bai_namespace} ]]; then
    error "BAI namespace is mandatory"
    show_help
    exit 1
fi

function check_prereqs() {
    title "Checking prereqs ..."
    check_command kubectl

    oc_version=$(kubectl get clusterversion version -o=jsonpath={.status.desired.version} 2>/dev/null)
    if [[ ! -z ${oc_version} ]]; then
      info "openshift version ${oc_version} detected."
      is_openshift=true
    fi
}

function delete_bai_cr {
  title "Deleting BAI CR ..."
  kubectl -n ${bai_namespace} get insightsengine -o name --ignore-not-found | xargs -I {} kubectl -n ${bai_namespace} delete {} --timeout=45s
  success "Done"
}

function delete_bai_namespace {
  title "Deleting BAI namespace ..."
  ns=$(kubectl get ns ${bai_namespace} -o=jsonpath={.metadata.name} 2>/dev/null)
  if [[ -z ${ns} ]]; then
    info "Namespace ${bai_namespace} does not exist."
  else
    kubectl delete namespace ${bai_namespace} --ignore-not-found --timeout=45s
    kubectl get -n ${bai_namespace} authentications.operator.ibm.com example-authentication > /dev/null 2>&1 && kubectl patch -n ${bai_namespace} authentications.operator.ibm.com example-authentication -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl get -n ${bai_namespace} clients zenclient-bai > /dev/null 2>&1 && kubectl patch -n ${bai_namespace} clients zenclient-bai -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl get -n ${bai_namespace} operandbindinfos ibm-iam-bindinfo > /dev/null 2>&1 && kubectl patch -n ${bai_namespace} operandbindinfos ibm-iam-bindinfo -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl get -n ${bai_namespace} operandbindinfos ibm-zen-bindinfo > /dev/null 2>&1 && kubectl patch -n ${bai_namespace} operandbindinfos ibm-zen-bindinfo -p '{"metadata":{"finalizers":null}}' --type=merge

    for zx in $(kubectl -n ${bai_namespace} get zenextensions -o name); do
      kubectl patch -n ${bai_namespace} ${zx} -p '{"metadata":{"finalizers":null}}' --type=merge
    done
    for co in $(kubectl -n ${bai_namespace} get client.oidc.security.ibm.com -o name); do
      kubectl patch -n ${bai_namespace} ${co} -p '{"metadata":{"finalizers":null}}' --type=merge
    done
    for fd in $( kubectl get -n ${bai_namespace} flinkdeployment.flink.ibm.com -o name); do
      kubectl patch -n ${bai_namespace} ${fd} -p '{"metadata":{"finalizers":null}}' --type=merge
    done

  fi
  success "Done"
}


function delete_operand_requests() {
  title "Deleting operand requests ..."

  if [[ ! -z "$(kubectl get crd | grep operandrequests)" ]]; then
    for request in $(kubectl -n ${bai_namespace} get operandrequests -o name); do
      info "Deleting ${request} ..."
      kubectl -n ${bai_namespace} delete ${request} --ignore-not-found --timeout=60s
    done

    for request in $(kubectl -n ${bai_namespace} get operandrequests -o name); do
      info "Force deleting ${request} ..."
      kubectl -n ${bai_namespace} patch ${request} --type="json" -p '[{"op": "remove", "path":"/metadata/finalizers"}]'
      kubectl -n ${bai_namespace} delete ${request} --ignore-not-found --timeout=10s
    done
  fi
  success "Done"
}

function delete_pvc() {
  title "Deleting pvc ..."

  if [[ ! -z "$(kubectl get pvc -n ${bai_namespace} )" ]]; then

    for request in $(kubectl -n ${bai_namespace} get pvc -o name); do
      info "Force deleting ${request} ..."
      kubectl -n ${bai_namespace} patch ${request} --type="json" -p '[{"op": "remove", "path":"/metadata/finalizers"}]'
      kubectl -n ${bai_namespace} delete ${request} --ignore-not-found --timeout=10s
    done
  fi
  success "Done"
}


function uninstall() {
    check_prereqs
    delete_bai_cr
    delete_operand_requests
    delete_pvc
    delete_bai_namespace
}

# --- Run ---
uninstall