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

############################################################
#Setup Variables
############################################################

DIR="$( cd "$( dirname "$0" )" && pwd )"

# Import common utilities and environment variables
source ${DIR}/helper/common.sh

source $DIR/helper/post-install/env.sh
source $DIR/helper/post-install/services/functions.sh

#Source all capabilities specific functions
source $DIR/helper/post-install/services/bai.sh

CP_FUNCTION_NAME="BAI Service"

#############################################################
case ${1} in
    --help|--?|?|-?|help|-help|--Help|-Help)
        printHeaderMessage "Help Menu for service flags"
        echo "--Precheck                           This will precheck OCP access"
        echo "--Status                             This will give status for services"
        echo "--Console                            This will give console for services URLs"
        echo "--Probe                              This will probe readiness/liveness of the endpoints"
        echo ""
        consoleFooter "${CP_FUNCTION_NAME}"
        exit 0
        ;;
esac

#Check for OS and set some vars accordingly:
OS
#Check connection to cluster:
validateOCPAccess
#Load APIs and Operator info
#operatorAndAPIVersions

case ${1} in
    --precheck|--Precheck)
         echo "--- Good to go!"
         consoleFooter "${CP_FUNCTION_NAME}"
         exit 0
         ;;
    --Status|--status)
          # Check the BAI status
          BAIStatus
          consoleFooter "${CP_FUNCTION_NAME}"
          cleanUp
          exit 0
          ;;
    --Console|--console)
          # Check the BAI console
          BAIConsole
          consoleFooter "${CP_FUNCTION_NAME}"
          cleanUp
          exit 0
          ;;
    --Probe|--probe)
          BAIServiceProbe
          exit 0
          ;;
    --*|-*)
        echo "${RED_TEXT}Unsupported flag in command line - ${1}. ${RESET_TEXT}"
        echo ""
        consoleFooter "${CP_FUNCTION_NAME}"
        ;;
    *)
        # Default: run all checks
        # Check the BAI status
        BAIStatus
        # Check the BAI console
        BAIConsole
        #Cleanup
        cleanUp
        ;;
esac
