#!/bin/bash
#set -x
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


# This file is a helper script used to store all functions that are used by the bai-prerequistes.sh in the validate mode

    # Set default values if variables are not set DBACLD-170075 (Allow customers to customize the country and language being passed to the jar files being used for validation in cp4a-prerequisites.sh)
    BAI_AUTO_LANGUAGE=${BAI_AUTO_LANGUAGE:-"EN"}
    BAI_AUTO_REGION=${BAI_AUTO_REGION:-"US"} #abhishek bug-170075

    # Validate that both values are exactly two characters long
    if [[ ${#BAI_AUTO_LANGUAGE} -ne 2 || ${#BAI_AUTO_REGION} -ne 2 ]]; then
        echo "Error: BAI_AUTO_LANGUAGE and BAI_AUTO_REGION must each be exactly 2 characters long."
        exit 1
    fi

# Validates if certain CLI tooks required for the validate mode are installed , and if requested can be installed
function validate_utility_tools_for_validate_mode(){
    which kubectl &>/dev/null
    if [[ $? -ne 0 ]]; then
        printf '%b\n'  "\x1B[1;31mUnable to locate Kubernetes CLI. You must install it to run this script.\x1B[0m" && \
        while true; do
            printf "\x1B[1mDo you want install the Kubernetes CLI by the bai-prerequisites.sh script? (Yes/No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                install_kubectl_cli
                break
                ;;
            "n"|"N"|"no"|"No"|"NO")
                info "Kubernetes CLI must be installed to continue the next validation"
                exit 1
                ;;
            *)
                printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    fi
    # DBACLD-198782: Check if Java is installed and meets the minimum version requirement
    # Priority: --java-path > JAVA_HOME > system PATH
    JAVA_PATH="${CUSTOM_JAVA_PATH:-$JAVA_HOME}"
    validate_java_runtime "$JAVA_PATH"

    which openssl &>/dev/null
    if [[ $? -ne 0 ]]; then
        printf '%b\n'  "\x1B[1;31mUnable to locate openssl. You must install it to run this script.\x1B[0m" && \
        while true; do
            printf "\x1B[1mDo you want install the OpenSSL by the bai-prerequisites.sh script? (Yes/No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                install_openssl
                break
                ;;
            "n"|"N"|"no"|"No"|"NO")
                info "OpenSSL must be installed for the next validation"
                exit 1
                ;;
            *)
                printf '%b\n' "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        done
    fi
}

#### Start - Functions being called by the validate_prerequisites function ####

# Function that verifies the storage class by creating a temporary PVC
function verify_storage_class_valid(){
    local STORAGE_CLASS_SAMPLE=$TEMP_FOLDER/.storage_sample.yaml
    local sc_name=$1
    local sc_mode=$2
    local sample_pvc_name=$3
    # Check if storage class exists first
    if ! ${CLI_CMD} get storageclass "$sc_name" &>/dev/null; then
        fail "Storage class '$sc_name' does not exist!"
        verification_sc_passed="No"
        return 1
    fi

    # Get the volumeBindingMode
    local binding_mode=$(${CLI_CMD} get storageclass "$sc_name" -o jsonpath='{.volumeBindingMode}' 2>/dev/null)

    # If binding mode is empty, default is Immediate
    if [[ -z "$binding_mode" ]]; then
        binding_mode="Immediate"
    fi

    # Skip PVC test for WaitForFirstConsumer
    # https://jsw.ibm.com/browse/DBACLD-229416
    if [[ "$binding_mode" == "WaitForFirstConsumer" ]]; then
        info "Storage class '$sc_name' detected with volumeBindingMode: WaitForFirstConsumer"
        warning "Skipping PVC binding test - PVC will bind when first pod is scheduled during deployment"
        success "Verification storage class: \"${sc_name}\", PASSED (existence and configuration verified)!"
        verification_sc_passed="Yes"
        printf "\n"
        return 0
    fi

  # Continue with normal PVC test for Immediate binding mode
  info "Storage class '$sc_name' uses volumeBindingMode: $binding_mode . The script will now perform a PVC binding test for the storage class"

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
    #     printf '%b\n' "\x1B[1mDone\x1B[0m"
    # else
    #     printf '%b\n' "\x1B[1;31mFailed\x1B[0m"
    # fi
   # Check Operator Persistent Volume status every 5 seconds (max 1 minutes) until allocate.
    ${CLI_CMD} apply -f ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
    ATTEMPTS=0
    TIMEOUT=12
    printf "\n"
    info "Checking the storage class: \"${sc_name}\"..."
    until ${CLI_CMD} get pvc | grep ${sample_pvc_name}| grep -q -m 1 "Bound" || [ $ATTEMPTS -eq $TIMEOUT ]; do
        ATTEMPTS=$((ATTEMPTS + 1))
        printf '%b\n' "......"
        sleep 5
        if [ $ATTEMPTS -eq $TIMEOUT ] ; then
            fail "Failed to allocate the persistent volumes using storage class: \"${sc_name}\"!"
            # info "Run the following command to check the claim 'kubectl describe pvc ${sample_pvc_name}'"
            verification_sc_passed="No"
        fi
    done
    if [ $ATTEMPTS -lt $TIMEOUT ] ; then
        success "Verification storage class: \"${sc_name}\", PASSED!"
        ${CLI_CMD} delete -f ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
        verification_sc_passed="Yes"
        printf "\n"
    fi

    rm -rf ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
}

# Function to validate the domain
# Only used when platform type is other
function validate_domain_name(){
    INFO "Checking if the Domain Name of the Cluster where BAI stand-alone is to be deployed is accessible"
    printf "\n"
    tmp_domain_name=$(prop_user_profile_property_file BAI_STANDALONE.DOMAIN_NAME)
    if ping -c 1 -W 2 "$tmp_domain_name" >/dev/null 2>&1; then
        success "The Domain '$tmp_domain_name' is accessible."
        printf "\n"
    else
        warning "The Domain '$tmp_domain_name' is not accessible. Please check your cluster and try again."
    fi
}

# Check if the required secrets and configmaps have been created
# Moved to this file as it is technically a function used while running validate mode
function validate_secret_in_cluster(){
    INFO "Checking if the secrets required by BAI stand-alone are found in the cluster" 
    local files=()
    SECRET_CREATE_PASSED="true"
    files=($(find $SECRET_FILE_FOLDER -name '*.yaml'))
    for item in ${files[*]}
    do
        secret_name_tmp=`cat $item | ${YQ_CMD} r - metadata.name`
        if [ -z "$secret_name_tmp" ]; then
            error "secret name not found in YAML file: \"$item\"! Please check and fix it"
            exit 1
        else
            secret_name_tmp=$(sed -e 's/^"//' -e 's/"$//' <<<"$secret_name_tmp")
            # need to check ibm-zen-metastore-edb-cm/im-datastore-edb-cm for Zen/IM and ibm-bts-config-extension external postgresql db support
            if [[ $secret_name_tmp != "ibm-zen-metastore-edb-cm" && $secret_name_tmp != "im-datastore-edb-cm" && $secret_name_tmp != "ibm-bts-config-extension" ]]; then
                secret_exists=`${CLI_CMD} get secret $secret_name_tmp -n $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ "$secret_exists" -ne 2 ] ; then
                    error "Secret \"$secret_name_tmp\" not found in Kubernetes cluster! Please create it before deploying BAI Standalone"
                    SECRET_CREATE_PASSED="false"
                else
                    success "Secret \"$secret_name_tmp\" found in Kubernetes cluster, PASSED!"              
                fi
            else
                secret_exists=`${CLI_CMD} get configmap $secret_name_tmp -n $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1
                if [ "$secret_exists" -ne 2 ] ; then
                    error "ConfigMap \"$secret_name_tmp\" not found in Kubernetes cluster! Please create it before deploying BAI Standalone"
                    SECRET_CREATE_PASSED="false"
                else
                    success "ConfigMap \"$secret_name_tmp\" found in Kubernetes cluster, PASSED!"              
                fi
            fi
        fi
    done
    
    files=($(find $SECRET_FILE_FOLDER -name '*.sh'))
    for item in ${files[*]}
    do
        if [[ "$machine" == "Mac" ]]; then
            secret_name_tmp=`grep ' create secret generic' $item | tail -1 | cut -d'"' -f2`

            # for DPE secret format specially
            if [ -z "$secret_name_tmp" ]; then
                secret_name_tmp=`grep ' create secret generic' $item | tail -1 | cut -d'"' -f2`
            fi
        else
            secret_name_tmp=`cat $item | grep -oP '(?<=generic ).*?(?= --from-file)'`

            # for DPE secret format specially
            if [ -z "$secret_name_tmp" ]; then
                secret_name_tmp=`cat $item | grep -oP '(?<=generic ).*?(?= \\\\)' | tail -1`
            fi

        fi
        if [ -z "$secret_name_tmp" ]; then
            error "Not found secret name in shell script file: \"$item\"! Please check and fix it"
            exit 1
        else
            secret_name_tmp=$(sed -e 's/^"//' -e 's/"$//' <<<"$secret_name_tmp")
            secret_exists=`${CLI_CMD} get secret $secret_name_tmp -n $BAI_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1
            if [ "$secret_exists" -ne 2 ] ; then
                error "Secret \"$secret_name_tmp\" not found in Kubernetes cluster! Please create it before deploying BAI Standalone"
                SECRET_CREATE_PASSED="false"
            else
                success "Secret \"$secret_name_tmp\" found in Kubernetes cluster, PASSED!"              
            fi
        fi
    done
    if [[ $SECRET_CREATE_PASSED == "false" ]]; then
        info "Please create all the secrets required ,exiting..."
        exit 1
    else
        INFO "All secrets created in Kubernetes cluster, PASSED!"
    fi
}

# function to verify ldap connection
function verify_ldap_connection(){
    local LDAP_TEST_JAR_PATH=${CUR_DIR}/helper/verification/ldap
    local ldap_server=$1
    local ldap_port=$2
    local ldap_basedn=$3
    local ldap_binddn=$4
    local ldap_binddn_pwd=$5
    local ldap_ssl=$6
    local ldap_truststore_password=$(generate_truststore_password)

    if [[ $ldap_ssl == "true" || $ldap_ssl == "yes" || $ldap_ssl == "y" ]]; then
        tmp_cert_folder="$(prop_ldap_property_file LDAP_SSL_CERT_FILE_FOLDER)"
        if [[ ! -f "${tmp_cert_folder}/ldap-cert.crt" ]]; then
            fail "Not found required certificat file \"ldap-cert.crt\" under \"$tmp_cert_folder\", exit..."
            exit 1
        fi

        rm -rf /tmp/ldap.der 2>&1 </dev/null
        rm -rf /tmp/ldap-truststore.jks 2>&1 </dev/null
        
        openssl x509 -outform der -in $tmp_cert_folder/ldap-cert.crt -out /tmp/ldap.der 2>&1 </dev/null
        $KEYTOOL_CMD -import -alias cp4baLdapCerts -keystore /tmp/ldap-truststore.jks -file /tmp/ldap.der -storepass "$ldap_truststore_password" -storetype JKS -noprompt 2>&1 </dev/null
        msg "Checking connection for LDAP server \"$ldap_server\" using BindDN \"$ldap_binddn\".."
        output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -Djavax.net.ssl.trustStore=/tmp/ldap-truststore.jks -Djavax.net.ssl.trustStorePassword=$ldap_truststore_password -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u "ldaps://$ldap_server:$ldap_port" -b "$ldap_basedn" -D "$ldap_binddn" -w "$ldap_binddn_pwd" 2>&1)

        # https://jsw.ibm.com/browse/DBACLD-192983 Check for successful connection - ONLY consider it successful if:
        # The output contains "Connected to: ldaps://$ldap_server:$ldap_port" (indicating successful connection)
        if [[ "$output" == *"Connected to: ldaps://$ldap_server:$ldap_port"* ]]; then
            success "Connected to LDAP \"$ldap_server\" using BindDN:\"$ldap_binddn\" successfully, PASSED!"
            printf "\n"
            connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
            if [[ ! -z $connection_time ]]; then
              display_latency_warning $connection_time "LDAP"
            fi
        else
            warning "Execute: $JAVA_CMD -Dsemeru.fips=$fips_flag -Djavax.net.ssl.trustStore=/tmp/ldap-truststore.jks -Djavax.net.ssl.trustStorePassword=$ldap_truststore_password -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u \"ldaps://$ldap_server:$ldap_port\" -b \"$ldap_basedn\" -D \"$ldap_binddn\" -w \"******\"" && \
            fail "Unable to connect to LDAP server \"$ldap_server\" using BindDN \"$ldap_binddn\", please check configuration in LDAP property again."
        fi
    else
        msg "Checking connection for LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\".."
        output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u "ldap://$ldap_server:$ldap_port" -b "$ldap_basedn" -D "$ldap_binddn" -w "$ldap_binddn_pwd" 2>&1)
        
        # https://jsw.ibm.com/browse/DBACLD-192983 Check for successful connection - ONLY consider it successful if:
        # The output contains "Connected to: ldap://$ldap_server:$ldap_port" (indicating successful connection)
        if [[ "$output" == *"Connected to: ldap://$ldap_server:$ldap_port"* ]]; then
            success "Connected to LDAP \"$ldap_server\" using BindDN:\"$ldap_binddn\" successfully, PASSED!"
            printf "\n"
            connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
            if [[ ! -z $connection_time ]]; then
              display_latency_warning $connection_time "LDAP"
            fi
        else
            warning "Execution: $JAVA_CMD -Dsemeru.fips=$fips_flag -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u \"ldap://$ldap_server:$ldap_port\" -b \"$ldap_basedn\" -D \"$ldap_binddn\" -w \"******\"" && \
            fail "Unable to connect to LDAP server \"$ldap_server\" using BindDN \"$ldap_binddn\", please check configuration in LDAP property again."
        fi
    fi 
}

# Function to validate the external postgres connection for IM
function validate_external_postgres_connection_for_im() {
    printf "\n"
    im_external_db_cert_folder="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
    im_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$im_external_db_cert_folder")

    dbserver="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
    dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
    dbport="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_PORT)"
    dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
    dbname="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_NAME)"
    dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
    dbuser="$(prop_user_profile_property_file BAI.IM_EXTERNAL_POSTGRES_DATABASE_USER)"
    dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
    dbuserpwd="changit" # client auth does not need dbuserpwd

    info "Checking connection for IM metastore external Postgres database \"${dbname}\" that belongs to database instance \"${dbserver}\"...."

    postgres_cafile="${im_external_db_cert_folder}/root.crt"
    postgres_clientkeyfile="${im_external_db_cert_folder}/client.key"
    postgres_clientcertfile="${im_external_db_cert_folder}/client.crt"

    rm -rf ${im_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
    openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${im_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null

    output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.11.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
    retVal_verify_db_tmp=$?
    connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
    if [[ ! -z $connection_time ]]; then
        display_latency_warning $connection_time "Database"
    fi

    [[ retVal_verify_db_tmp -ne 0 ]] && \
    warning "Execute: $JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.11.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
    fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
    [[ retVal_verify_db_tmp -eq 0 ]] && \
    success "The DB connection check for \"$dbname\" on database server \"$dbserver\" PASSED!"
}

# Function to validate the external postgres connection for zen
function validate_external_postgres_connection_for_zen(){
    printf "\n"
    zen_external_db_cert_folder="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
    zen_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$zen_external_db_cert_folder")

    dbserver="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
    dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
    dbport="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_PORT)"
    dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
    dbname="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_NAME)"
    dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
    dbuser="$(prop_user_profile_property_file BAI.ZEN_EXTERNAL_POSTGRES_DATABASE_USER)"
    dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
    dbuserpwd="changit" # client auth does not need dbuserpwd

    info "Checking connection for Zen metastore external Postgres database \"${dbname}\" that belongs to database instance \"${dbserver}\"...."

    postgres_cafile="${zen_external_db_cert_folder}/root.crt"
    postgres_clientkeyfile="${zen_external_db_cert_folder}/client.key"
    postgres_clientcertfile="${zen_external_db_cert_folder}/client.crt"

    rm -rf ${zen_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
    openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${zen_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null

    output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.11.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
    retVal_verify_db_tmp=$?
    connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
    if [[ ! -z $connection_time ]]; then
        display_latency_warning $connection_time "Database"
    fi

    [[ retVal_verify_db_tmp -ne 0 ]] && \
    warning "Execute: $JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.11.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
    fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
    [[ retVal_verify_db_tmp -eq 0 ]] && \
    success "The DB connection check for \"$dbname\" on database server \"$dbserver\" PASSED!"
}

# Function to validate the external postgres connection for bts
function validate_external_postgres_connection_for_bts(){
    printf "\n"
    bts_external_db_cert_folder="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
    bts_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$bts_external_db_cert_folder")

    dbserver="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_HOSTNAME)"
    dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
    dbport="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_PORT)"
    dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
    dbname="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_NAME)"
    dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
    dbuser="$(prop_user_profile_property_file BAI.BTS_EXTERNAL_POSTGRES_DATABASE_USER_NAME)"
    dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
    dbuserpwd="changit" # client auth does not need dbuserpwd

    info "Checking connection for BTS metastore external Postgres database \"${dbname}\" that belongs to database instance \"${dbserver}\"...."

    postgres_cafile="${bts_external_db_cert_folder}/root.crt"
    postgres_clientkeyfile="${bts_external_db_cert_folder}/client.key"
    postgres_clientcertfile="${bts_external_db_cert_folder}/client.crt"

    rm -rf ${bts_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
    openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${bts_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null

    output=$($JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.11.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
    retVal_verify_db_tmp=$?
    connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
    if [[ ! -z $connection_time ]]; then
        display_latency_warning $connection_time "Database"
    fi

    [[ retVal_verify_db_tmp -ne 0 ]] && \
    warning "Execute: $JAVA_CMD -Dsemeru.fips=$fips_flag -Duser.language=$BAI_AUTO_LANGUAGE -Duser.country=$BAI_AUTO_REGION -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.11.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
    fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
    [[ retVal_verify_db_tmp -eq 0 ]] && \
    success "The DB connection check for \"$dbname\" on database server \"$dbserver\" PASSED!"
}

#### End - Functions being called by the validate_prerequisites function ####

# Function that validates some of the prerequisites required, like storage class, LDAP connection , external Postgres connection 
function validate_prerequisites(){
    # check FIPS enabled or disabled
    fips_flag="false"

    # VALIDATION CHECK 1
    # Validating the storage class
    INFO "Checking Medium/Fast/Block storage class required by BAI stand-alone" 

    tmp_storage_classname=$(prop_user_profile_property_file BAI_STANDALONE.MEDIUM_FILE_STORAGE_CLASSNAME)
    sample_pvc_name="bai-test-medium-pvc-$RANDOM"
    verify_storage_class_valid $tmp_storage_classname "ReadWriteMany" $sample_pvc_name

    tmp_storage_classname=$(prop_user_profile_property_file BAI_STANDALONE.FAST_FILE_STORAGE_CLASSNAME)
    sample_pvc_name="bai-test-fase-pvc-$RANDOM"
    verify_storage_class_valid $tmp_storage_classname "ReadWriteMany" $sample_pvc_name

    tmp_storage_classname=$(prop_user_profile_property_file BAI_STANDALONE.BLOCK_STORAGE_CLASS_NAME)
    sample_pvc_name="bai-test-block-pvc-$RANDOM"
    verify_storage_class_valid $tmp_storage_classname "ReadWriteOnce" $sample_pvc_name

    if [[ $verification_sc_passed == "No" ]]; then
        ${CLI_CMD} delete pvc -l bai=test-only >/dev/null 2>&1
        exit 0
    fi

    
    # VALIDATION CHECK 2
    # Validate Secrets required for BAI stand-alone. ( checks for the secrets generated as part of generate mode)
    validate_secret_in_cluster


    # VALIDATION CHECK 3
    # Validate if the domain name is accessible if the platform type is other
    # DBACLD-168345
    tmp_platform_type=$(prop_user_profile_property_file BAI_STANDALONE.PLATFORM_TYPE)
    if [[ $tmp_platform_type == "other" ]]; then
        validate_domain_name
    fi


    # VALIDATION CHECK 4
    # Validate LDAP connection for BAI stand-alone if LDAP option was selected
    # DBACLD-168779
    if [[ ! ("${#flink_job_cr_arr[@]}" -eq "1" && "${flink_job_cr_arr[@]}" =~ "workflow-process-service" && $LDAP_WFPS_AUTHORING == "No") && $selected_ldap_flag == "Yes" ]]; then
        INFO "Checking the LDAP connection required by BAI stand-alone" 
        tmp_servername="$(prop_ldap_property_file LDAP_SERVER)"
        tmp_serverport="$(prop_ldap_property_file LDAP_PORT)"
        tmp_basdn="$(prop_ldap_property_file LDAP_BASE_DN)"
        tmp_ldapssl="$(prop_ldap_property_file LDAP_SSL_ENABLED)"
        ## <https://jsw.ibm.com/browse/DBACLD-172803> - We are now asking user to use {xor} for special characters in password, so we need to use decode_xor_password to get the password decoded before validation.
        tmp_user=$($CLI_CMD get secret -n "$bai_services_namespace" -l name=ldap-bind-secret -o jsonpath='{.items[0].data.ldapUsername}' | ${BASE64_DECODE})
        tmp_userpwd=$($CLI_CMD get secret -n "$bai_services_namespace" -l name=ldap-bind-secret -o jsonpath='{.items[0].data.ldapPassword}' | ${BASE64_DECODE})
        if [[ "$tmp_userpwd" =~ "{xor}" ]]; then
            bai_operator=$( $CLI_CMD get pods -l name=ibm-bai-insights-engine-operator --no-headers --ignore-not-found -n $bai_operators_namespace | awk '{print $1}' )
            tmp_userpwd=$(decode_xor_password $tmp_userpwd $bai_operators_namespace $bai_operator)
        fi

        tmp_servername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_servername")
        tmp_serverport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_serverport")
        tmp_basdn=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_basdn")
        tmp_ldapssl=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_ldapssl")
        tmp_ldapssl=$(echo $tmp_ldapssl | tr '[:upper:]' '[:lower:]')
        tmp_user=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_user")
        tmp_userpwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_userpwd")

        verify_ldap_connection "$tmp_servername" "$tmp_serverport" "$tmp_basdn" "$tmp_user" "$tmp_userpwd" "$tmp_ldapssl"
    fi

    # Check db connection for im/zen/bts external postgresql db
    local DB_JDBC_NAME=${JDBC_DRIVER_DIR}/postgresql
    local DB_CONNECTION_JAR_PATH=${CUR_DIR}/helper/verification/postgresql

    # VALIDATION CHECK 5
    if [[ $EXTERNAL_POSTGRESDB_FOR_IM_FLAG == "true" ]]; then
        validate_external_postgres_connection_for_im
    fi

    # VALIDATION CHECK 6
    if [[ $EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG == "true" ]]; then
        validate_external_postgres_connection_for_zen
    fi

    # VALIDATION CHECK 7
    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS_FLAG == "true" ]]; then
        validate_external_postgres_connection_for_bts
    fi

    info "If all prerequisites check have PASSED, you can run bai-deployment.sh script to deploy BAI stand-alone. Otherwise, please check the configuration again."
    info "After BAI stand-alone is deployed, please refer to the documentation for post-deployment steps."
}
