#!/bin/bash

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
## This files contains various functions that contain messages used in the scripts


function displayUpgradeOperatorMessage() {
  local tmp_message=$1
  local tmp_target_project_name=$2
  local tmp_original_bai_csv_ver=$3
  warning "$tmp_message"
  echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fixing the issue of IBM Cloud Pak foundational services."
  echo "           ${GREEN_TEXT}# ./bai-deployment.sh -m upgradeOperator -n $tmp_target_project_name --cpfs-upgrade-mode <migration mode> --original-bai-csv-ver <bai-csv-version-before-upgrade>${RESET_TEXT}"
  echo "           Usage:"
  echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
  echo "           --original-bai-csv-ver: The version of csv for BAI operator before upgrade such as $tmp_original_bai_csv_ver"
  echo "           Example command: "
  echo "           # ./bai-deployment.sh -m upgradeOperator -n $tmp_target_project_name --cpfs-upgrade-mode dedicated2dedicated --original-bai-csv-ver $tmp_original_bai_csv_ver"
}
