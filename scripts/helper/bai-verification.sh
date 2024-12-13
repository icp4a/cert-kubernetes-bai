#!/bin/bash
# set -x
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
function verify_storage_class_valid(){
  local STORAGE_CLASS_SAMPLE=$TEMP_FOLDER/.storage_sample.yaml
  local sc_name=$1
  local sc_mode=$2
  local sample_pvc_name=$3

cat << EOF > ${STORAGE_CLASS_SAMPLE}
# YAML template for sample storage class
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    bai: test-only
  name: ${sample_pvc_name}
spec:
  accessModes:
  - ${sc_mode}
  resources:
    requests:
      storage: 10Mi
  storageClassName: ${sc_name}
EOF
  
    # CREATE_PVC_CMD="kubectl apply -f ${STORAGE_CLASS_SAMPLE}"
    # if $CREATE_PVC_CMD ; then
    #     echo -e "\x1B[1mDone\x1B[0m"
    # else
    #     echo -e "\x1B[1;31mFailed\x1B[0m"
    # fi
   # Check Operator Persistent Volume status every 5 seconds (max 1 minutes) until allocate.
    kubectl apply -f ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
    ATTEMPTS=0
    TIMEOUT=12
    printf "\n"
    info "Checking the storage class: \"${sc_name}\"..."
    until kubectl get pvc | grep ${sample_pvc_name}| grep -q -m 1 "Bound" || [ $ATTEMPTS -eq $TIMEOUT ]; do
        ATTEMPTS=$((ATTEMPTS + 1))
        echo -e "......"
        sleep 5
        if [ $ATTEMPTS -eq $TIMEOUT ] ; then
            fail "Failed to allocate the persistent volumes using storage class: \"${sc_name}\"!"
            # info "Run the following command to check the claim 'kubectl describe pvc ${sample_pvc_name}'"
            verification_sc_passed="No"
        fi
    done
    if [ $ATTEMPTS -lt $TIMEOUT ] ; then
            success "Verification storage class: \"${sc_name}\", PASSED!"
            kubectl delete -f ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
            verification_sc_passed="Yes"
            printf "\n"
    fi

    rm -rf ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
}

# verify ldap connection
function verify_ldap_connection(){
  local LDAP_TEST_JAR_PATH=${CUR_DIR}/helper/verification/ldap
  local ldap_server=$1
  local ldap_port=$2
  local ldap_basedn=$3
  local ldap_binddn=$4
  local ldap_binddn_pwd=$5
  local ldap_ssl=$6

  if [[ $ldap_ssl == "true" || $ldap_ssl == "yes" || $ldap_ssl == "y" ]]; then
    tmp_cert_folder="$(prop_ldap_property_file LDAP_SSL_CERT_FILE_FOLDER)"
    if [[ ! -f "${tmp_cert_folder}/ldap-cert.crt" ]]; then
      fail "Not found required certificat file \"ldap-cert.crt\" under \"$tmp_cert_folder\", exit..."
      exit 1
    fi

    rm -rf /tmp/ldap.der 2>&1 </dev/null
    rm -rf /tmp/ldap-truststore.jks 2>&1 </dev/null
    #  add keytool to system PATH.
    sudo -s export PATH="/opt/ibm/java/jre/bin/:$PATH"; export PATH="/opt/ibm/java/jre/bin/:$PATH"; echo "PATH=$PATH:/opt/ibm/java/jre/bin/" >> ~/.bashrc; source ~/.bashrc

    openssl x509 -outform der -in $tmp_cert_folder/ldap-cert.crt -out /tmp/ldap.der 2>&1 </dev/null
    keytool -import -alias cp4baLdapCerts -keystore /tmp/ldap-truststore.jks -file /tmp/ldap.der -storepass changeit -storetype JKS -noprompt 2>&1 </dev/null
    msg "Checking connection for LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\".."
    output=$(java -Dsemeru.fips=$fips_flag -Djavax.net.ssl.trustStore=/tmp/ldap-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u "ldaps://$ldap_server:$ldap_port" -b "$ldap_basedn" -D "$ldap_binddn" -w "$ldap_binddn_pwd" 2>&1)
    retVal_verify_ldap_tmp=$?
    connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
    echo "Latency: $connection_time ms"
    # Check if elapsed time is greater than 10 ms using awk
    if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
      echo "The latency is less than 10ms, which is acceptable performance for a simple LDAP operation."
    elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
      echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple LDAP operation, but the service is still accessible."
    elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
      echo "The latency exceeds 30ms for a simple LDAP operation, which indicates potential for failures."
    fi

    [[ retVal_verify_ldap_tmp -ne 0 ]] && \
    warning "Execute: java -Dsemeru.fips=$fips_flag -Djavax.net.ssl.trustStore=/tmp/ldap-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u \"ldaps://$ldap_server:$ldap_port\" -b \"$ldap_basedn\" -D \"$ldap_binddn\" -w \"******\"" && \
    fail "Unable to connect to LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\", please check configuration in ldap property again."
    [[ retVal_verify_ldap_tmp -eq 0 ]] && \
    success "Connected to LDAP \"$ldap_server\" using BindDN:\"$ldap_binddn\" successfuly, PASSED!"
  else
    msg "Checking connection for LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\".."
    output=$(java -Dsemeru.fips=$fips_flag -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u "ldap://$ldap_server:$ldap_port" -b "$ldap_basedn" -D "$ldap_binddn" -w "$ldap_binddn_pwd" 2>&1)
    retVal_verify_ldap_tmp=$?
    connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
    echo "Latency: $connection_time ms"
    # Check if elapsed time is greater than 10 ms using awk
    if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
      echo "The latency is less than 10ms, which is acceptable performance for a simple LDAP operation."
    elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
      echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple LDAP operation, but the service is still accessible."
    elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
      echo "The latency exceeds 30ms for a simple LDAP operation, which indicates potential for failures."
    fi

    [[ retVal_verify_ldap_tmp -ne 0 ]] && \
    warning "Execution: java -Dsemeru.fips=$fips_flag -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u \"ldap://$ldap_server:$ldap_port\" -b \"$ldap_basedn\" -D \"$ldap_binddn\" -w \"******\"" && \
    fail "Unable to connect to LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\", please check configuration in ldap property again."
    [[ retVal_verify_ldap_tmp -eq 0 ]] && \
    success "Connected to LDAP \"$ldap_server\" using BindDN:\"$ldap_binddn\" successfuly, PASSED!"
  fi 
}

