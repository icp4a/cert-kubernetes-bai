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

source $DIR/helper/post-install/env.sh
source $DIR/helper/post-install/services/functions.sh

#Source all capabilities specific functions
source $DIR/helper/post-install/services/bai.sh

#Check for OS and set some vars accordingly:
OS
#Check connection to cluster:
validateOCPAccess
# Check the BAI status
BAIStatus
# Check the BAI console 
BAIConsole
#check the commonServices components status 
cpfs_status
#Cleanup
cleanUp
