###############################################################################
#
# LICENSED MATERIALS - PROPERTY OF IBM
#
# (C) COPYRIGHT IBM CORP. 2022. ALL RIGHTS RESERVED.
#
# US GOVERNMENT USERS RESTRICTED RIGHTS - USE, DUPLICATION OR
# DISCLOSURE RESTRICTED BY GSA ADP SCHEDULE CONTRACT WITH IBM CORP.
#
###############################################################################

cd $DIR
mkdir logs 2> /dev/null
LOG_DIR=$DIR/logs

BAIStatus()
{
  printHeaderMessage "BAI Status - InsightsEngine"
  rm ${LOG_DIR}/bai-status.log 2> /dev/null
  echo '' > ${LOG_DIR}/bai-status.log

  ${CLI_CMD} get InsightsEngine ${BAI_DEPLOYMENT_NAME} -n ${BAI_AUTO_NAMESPACE} -o jsonpath='{.status.insightsEngineStatus}' 2> /dev/null   &> ${LOG_DIR}/bai-status.log

  #################################################
  #BAI InsightsEngine Status and Version
  #################################################
  BAI_BAI_INSIGHT_ENGINE_STATUS=`cat ${LOG_DIR}/bai-status.log`
  if [ "$BAI_BAI_INSIGHT_ENGINE_STATUS" = "Ready" ]; then
    BAI_BAI_INSIGHT_ENGINE_STATUS="Installed"
  fi
  echo "InsightsEngine:                               :  ${BAI_BAI_INSIGHT_ENGINE_STATUS}"

  ${CLI_CMD} get InsightsEngine ${BAI_DEPLOYMENT_NAME} -n ${BAI_AUTO_NAMESPACE} -o jsonpath='{.status.currentVersion}' 2> /dev/null   &> ${LOG_DIR}/bai-version.log
  BAI_BAI_INSIGHT_ENGINE_VERSION=`cat ${LOG_DIR}/bai-version.log`
  echo "InsightsEngine Version:                       :  ${BAI_BAI_INSIGHT_ENGINE_VERSION}"
}
BAICommonServicesConsoleInfo()
{
  printHeaderMessage "Service Console - Common"
  # BAI uses the cpd route for the Cloud Pak dashboard
  local COMMON_CONSOLE_URL=`${CLI_CMD} get routes -n ${BAI_AUTO_NAMESPACE} 2> /dev/null | grep "^cpd " | awk '{print $2}'`
  echo "Cloud Pak Common Dashboard                    : ${BLUE_TEXT}https://${COMMON_CONSOLE_URL}${RESET_TEXT}"

  local COMMON_USERNAME=`${CLI_CMD} get secret platform-auth-idp-credentials -n ${BAI_AUTO_NAMESPACE} -o go-template --template="{{.data.admin_username|base64decode}}" 2> /dev/null`
  local COMMON_PASSWORD=`${CLI_CMD} get secret platform-auth-idp-credentials -n ${BAI_AUTO_NAMESPACE} -o go-template --template="{{.data.admin_password|base64decode}}" 2> /dev/null`
  echo "Admin Username                                : ${COMMON_USERNAME}"
  echo "Admin Password                                : ${COMMON_PASSWORD}"
}

BAIConsole()
{
  BAICommonServicesConsoleInfo

  printHeaderMessage "BAI - Business Automation Insights Console"
  ${CLI_CMD} get cm bai-bai-access-info -n ${BAI_AUTO_NAMESPACE} -o jsonpath='{.data.bai-access-info}' 2> /dev/null &> ${LOG_DIR}/bai-console.yaml

  BPC_URL=`cat ${LOG_DIR}/bai-console.yaml | grep "Business Performance Center URL" | awk '{print $5}' | head -n 1`
  echo "Business Performance Center URL               : ${BPC_URL}"

  KAFKA_BOOTSTRAP=`cat ${LOG_DIR}/bai-console.yaml | grep "Kafka Bootstrap_Servers" | awk '{print $3}' | head -n 1`
  echo "Kafka Bootstrap Servers                       : ${KAFKA_BOOTSTRAP}"

  OPENSEARCH_URL=`cat ${LOG_DIR}/bai-console.yaml | grep "OpenSearch URL" | awk '{print $3}' | head -n 1`
  echo "OpenSearch URL                                : ${OPENSEARCH_URL}"
}