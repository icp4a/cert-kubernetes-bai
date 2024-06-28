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

  kubectl get InsightsEngine ${BAI_DEPLOYMENT_NAME} -n ${BAI_AUTO_NAMESPACE} -o jsonpath='{.status.insightsEngineStatus}' 2> /dev/null   &> ${LOG_DIR}/bai-status.log

  #################################################
  #BAI InsightsEngine Status and Version
  #################################################
  BAI_BAI_INSIGHT_ENGINE_STATUS=`cat ${LOG_DIR}/bai-status.log`
  if [ "$BAI_BAI_INSIGHT_ENGINE_STATUS" = "Ready" ]; then
    BAI_BAI_INSIGHT_ENGINE_STATUS="Installed"
  fi
  echo "InsightsEngine:                               :  ${BAI_BAI_INSIGHT_ENGINE_STATUS}"

  kubectl get InsightsEngine ${BAI_DEPLOYMENT_NAME} -n ${BAI_AUTO_NAMESPACE} -o jsonpath='{.status.currentVersion}' 2> /dev/null   &> ${LOG_DIR}/bai-version.log
  BAI_BAI_INSIGHT_ENGINE_VERSION=`cat ${LOG_DIR}/bai-version.log`
  echo "InsightsEngine Version:                       :  ${BAI_BAI_INSIGHT_ENGINE_VERSION}"
}
BAIConsole()
{
  printHeaderMessage "BAI - Business Automation Insights Console"
  oc get cm bai-bai-access-info -o jsonpath='{.data.bai-access-info}' 2> /dev/null &> ${LOG_DIR}/bai-console.yaml

  BPC_URL=`cat  ${LOG_DIR}/bai-console.yaml | grep "Business Performance Center URL"  | awk '{print $5}'| head -n 1`
  echo "Business Performance Center URL               : ${BPC_URL}"
}