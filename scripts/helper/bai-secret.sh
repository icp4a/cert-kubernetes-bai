#!/BIN/BASH

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

# function for creating the template for ldap bind secret

function create_ldap_secret_template(){
  wait_msg "Creating ldap-bind-secret secret YAML template"
  mkdir -p $SECRET_FILE_FOLDER >/dev/null 2>&1

cat << EOF > ${LDAP_SECRET_FILE}
# YAML template for ldap-bind-secret secret
---
kind: Secret
apiVersion: v1
type: Opaque
metadata:
  name: ldap-bind-secret
  namespace: ${bai_services_namespace}
  # DO NOT change the content of metadata.labels
  labels:
    name: ldap-bind-secret
stringData:
  ldapUsername: "<LDAP_BIND_DN>"
  ldapPassword: "<LDAP_PASSWORD>"
EOF

  success "Created ldap-bind-secret secret YAML template\n"
}

# This function cover LDAP SSL
function create_cp4a_ldap_ssl_secret_template(){
  wait_msg "Creating ldap ssl cert secret YAML template"
  mkdir -p $LDAP_SSL_SECRET_FOLDER >/dev/null 2>&1

cat << EOF > ${CP4A_LDAP_SSL_SECRET_FILE}
#!/bin/bash
# Shell template for ibm-cp4a-ldap-ssl-cert-secret.sh 
if [[ -f "<cp4a-ldap-crt-file-in-local>/ldap-cert.crt" ]]; then
  kubectl delete secret generic "<cp4a-ldap_ssl_secret_name>" -n ${bai_services_namespace} >/dev/null 2>&1
  kubectl create secret generic "<cp4a-ldap_ssl_secret_name>" --from-file=tls.crt="<cp4a-ldap-crt-file-in-local>/ldap-cert.crt" -n ${bai_services_namespace}
else
  echo -e "\x1B[1;31m[FAILED]:\x1B[0m Please copy \"ldap-cert.crt\" into \"<cp4a-ldap-crt-file-in-local>\" firstly."
  exit 1
fi
EOF

  success "Created ldap ssl cert secret YAML template\n"
  chmod 755 ${CP4A_LDAP_SSL_SECRET_FILE}
}

function create_zen_external_db_secret_template(){
  wait_msg "Creating ibm-zen-metastore-edb-secret secret YAML template for Zen metastore external Postgres DB"
  mkdir -p $ZEN_SECRET_FOLDER >/dev/null 2>&1

cat << EOF > ${ZEN_SECRET_FILE}
#!/bin/bash
# Shell template for ibm-zen-metastore-edb-secret.sh
if [[ -f "<cp4a-db-crt-file-in-local>/root.crt" && -f "<cp4a-db-crt-file-in-local>/client.crt" && -f "<cp4a-db-crt-file-in-local>/client.key" ]]; then
  openssl x509 -in <cp4a-db-crt-file-in-local>/root.crt -noout -subject -issuer -startdate -enddate >/dev/null 2>&1

  openssl x509 -in <cp4a-db-crt-file-in-local>/client.crt -noout -subject -issuer -startdate -enddate >/dev/null 2>&1

  openssl rsa -in <cp4a-db-crt-file-in-local>/client.key -outform PEM -out <cp4a-db-crt-file-in-local>/client_key.pem >/dev/null 2>&1

  openssl x509 -in <cp4a-db-crt-file-in-local>/client.crt -outform PEM -out <cp4a-db-crt-file-in-local>/client.pem >/dev/null 2>&1

  openssl x509 -in <cp4a-db-crt-file-in-local>/root.crt -outform PEM -out <cp4a-db-crt-file-in-local>/root.pem >/dev/null 2>&1

  kubectl delete secret generic "ibm-zen-metastore-edb-secret" -n ${bai_services_namespace} >/dev/null 2>&1
  kubectl create secret generic "ibm-zen-metastore-edb-secret" --from-file=ca.crt="<cp4a-db-crt-file-in-local>/root.pem"\
  --from-file=tls.crt="<cp4a-db-crt-file-in-local>/client.pem"\
  --from-file=tls.key="<cp4a-db-crt-file-in-local>/client_key.pem"\
  --type=kubernetes.io/tls -n ${bai_services_namespace}
else
  echo -e "\x1B[1;31m[FAILED]:\x1B[0m Please copy \"root.crt\" \"client.crt\" \"client.key\" into \"<cp4a-db-crt-file-in-local>\" first."
  exit 1
fi
EOF
  success "Created ibm-zen-metastore-edb-secret secret YAML template for Zen metastore external Postgres DB\n"
  chmod 755 ${ZEN_SECRET_FILE}
}

function create_zen_external_db_configmap_template(){
  wait_msg "Creating ibm-zen-metastore-edb-cm configMap YAML template for Zen metastore external Postgres DB"
  mkdir -p $ZEN_SECRET_FOLDER >/dev/null 2>&1
cat << EOF > ${ZEN_CONFIGMAP_FILE}
# YAML template for ibm-zen-metastore-edb-cm configMap
# Updated for issue https://jsw.ibm.com/browse/DBACLD-166239 with these 2 DATABASE_ENABLE_SSL,DATABASE_SSL_MODE parameters
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ibm-zen-metastore-edb-cm
  namespace: ${bai_services_namespace}
data:
  IS_EMBEDDED: "false"
  DATABASE_CA_CERT: ca.crt
  DATABASE_CLIENT_CERT: tls.crt
  DATABASE_CLIENT_KEY: tls.key
  DATABASE_MONITORING_SCHEMA: <MonitoringSchema>
  DATABASE_NAME: <DatabaseName>
  DATABASE_PORT: "<DatabasePort>"
  DATABASE_R_ENDPOINT: "<DatabaseReadHostName>"
  DATABASE_RW_ENDPOINT: "<DatabaseHostName>"
  DATABASE_SCHEMA: <DatabaseSchema>
  DATABASE_USER: <DatabaseUser>
  DATABASE_ENABLE_SSL: "true"
  DATABASE_SSL_MODE: require 
EOF
  success "Created ibm-zen-metastore-edb-cm configMap YAML template for Zen metastore external Postgres DB\n"
}

function create_im_external_db_secret_template(){
  wait_msg "Creating im-datastore-edb-secret secret YAML template for IM metastore external Postgres DB"
  mkdir -p $IM_SECRET_FOLDER >/dev/null 2>&1

cat << EOF > ${IM_SECRET_FILE}
#!/bin/bash
# Shell template for im-datastore-edb-secret.sh
if [[ -f "<cp4a-db-crt-file-in-local>/root.crt" && -f "<cp4a-db-crt-file-in-local>/client.crt" && -f "<cp4a-db-crt-file-in-local>/client.key" ]]; then
  openssl x509 -in <cp4a-db-crt-file-in-local>/root.crt -noout -subject -issuer -startdate -enddate >/dev/null 2>&1
  openssl x509 -in <cp4a-db-crt-file-in-local>/client.crt -noout -subject -issuer -startdate -enddate >/dev/null 2>&1
  openssl rsa -in <cp4a-db-crt-file-in-local>/client.key -outform PEM -out <cp4a-db-crt-file-in-local>/client_key.pem >/dev/null 2>&1
  openssl x509 -in <cp4a-db-crt-file-in-local>/client.crt -outform PEM -out <cp4a-db-crt-file-in-local>/client.pem >/dev/null 2>&1
  openssl x509 -in <cp4a-db-crt-file-in-local>/root.crt -outform PEM -out <cp4a-db-crt-file-in-local>/root.pem >/dev/null 2>&1
  kubectl delete secret generic "im-datastore-edb-secret" -n ${bai_services_namespace} >/dev/null 2>&1
  kubectl create secret generic "im-datastore-edb-secret" --from-file=ca.crt="<cp4a-db-crt-file-in-local>/root.pem"\
  --from-file=tls.crt="<cp4a-db-crt-file-in-local>/client.pem"\
  --from-file=tls.key="<cp4a-db-crt-file-in-local>/client_key.pem"\
  --type=kubernetes.io/tls -n ${bai_services_namespace}
else
  echo -e "\x1B[1;31m[FAILED]:\x1B[0m Please copy \"root.crt\" \"client.crt\" \"client.key\" into \"<cp4a-db-crt-file-in-local>\" first."
  exit 1
fi
EOF
  success "Created im-datastore-edb-secret secret YAML template for IM metastore external Postgres DB\n"
  chmod 755 ${IM_SECRET_FILE}
}

function create_im_external_db_configmap_template(){
  wait_msg "Creating im-datastore-edb-cm configMap YAML template for IM metastore external Postgres DB"
  mkdir -p $IM_SECRET_FOLDER >/dev/null 2>&1
cat << EOF > ${IM_CONFIGMAP_FILE}
# YAML template for im-datastore-edb-cm configMap
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: im-datastore-edb-cm
  namespace: ${bai_services_namespace}
data:
  IS_EMBEDDED: "false"
  DATABASE_PORT: "<DatabasePort>"
  DATABASE_R_ENDPOINT: "<DatabaseReadHostName>"
  DATABASE_RW_ENDPOINT: "<DatabaseHostName>"
  DATABASE_USER: <DatabaseUser>
  DATABASE_NAME: <DatabaseName>
  DATABASE_CA_CERT: ca.crt
  DATABASE_CLIENT_CERT: tls.crt
  DATABASE_CLIENT_KEY: tls.key
EOF
  success "Created im-datastore-edb-cm configMap YAML template for IM metastore external Postgres DB\n"
}

function create_bts_external_db_secret_template(){
  wait_msg "Creating bts-datastore-edb-secret secret YAML template for BTS metastore external Postgres DB"
  mkdir -p $BTS_SECRET_FOLDER >/dev/null 2>&1

cat << EOF > ${BTS_SSL_SECRET_FILE}
#!/bin/bash
# Shell template for bts-datastore-edb-secret.sh
if [[ -f "<cp4a-db-crt-file-in-local>/root.crt" && -f "<cp4a-db-crt-file-in-local>/client.crt" && -f "<cp4a-db-crt-file-in-local>/client.key" ]]; then
  openssl x509 -in <cp4a-db-crt-file-in-local>/root.crt -noout -subject -issuer -startdate -enddate >/dev/null 2>&1
  openssl x509 -in <cp4a-db-crt-file-in-local>/client.crt -noout -subject -issuer -startdate -enddate >/dev/null 2>&1
  openssl rsa -in <cp4a-db-crt-file-in-local>/client.key -outform PEM -out <cp4a-db-crt-file-in-local>/client_key.pem >/dev/null 2>&1
  openssl x509 -in <cp4a-db-crt-file-in-local>/client.crt -outform PEM -out <cp4a-db-crt-file-in-local>/client.pem >/dev/null 2>&1
  openssl x509 -in <cp4a-db-crt-file-in-local>/root.crt -outform PEM -out <cp4a-db-crt-file-in-local>/root.pem >/dev/null 2>&1
  openssl pkcs8 -topk8 -inform PEM -in <cp4a-db-crt-file-in-local>/client_key.pem -outform DER -nocrypt -out <cp4a-db-crt-file-in-local>/tls_key.pk8
  kubectl delete secret generic "bts-datastore-edb-secret" -n ${bai_services_namespace} >/dev/null 2>&1
  kubectl create secret generic "bts-datastore-edb-secret" --from-file=ca.crt="<cp4a-db-crt-file-in-local>/root.pem"\
  --from-file=tls.crt="<cp4a-db-crt-file-in-local>/client.pem"\
  --from-file=tls.key="<cp4a-db-crt-file-in-local>/tls_key.pk8" -n ${bai_services_namespace}
else
  echo -e "\x1B[1;31m[FAILED]:\x1B[0m Please copy \"root.crt\" \"client.crt\" \"client.key\" into \"<cp4a-db-crt-file-in-local>\" first."
  exit 1
fi
EOF
  success "Created bts-datastore-edb-secret secret YAML template for BTS metastore external Postgres DB\n"
  chmod 755 ${BTS_SSL_SECRET_FILE}

  wait_msg "Creating bts-datastore-edb-user secret YAML template for BTS metastore external Postgres DB"
  mkdir -p $BTS_SECRET_FOLDER >/dev/null 2>&1

cat << EOF > ${BTS_SECRET_FILE}
# YAML template for bts-datastore-edb-user secret
---
kind: Secret
apiVersion: v1
type: Opaque
metadata:
  name: bts-datastore-edb-user
  namespace: ${bai_services_namespace}
stringData:
  username: "<USERNAME>"
  password: '<PASSWORD>'
EOF

  success "Created bts-datastore-edb-user secret YAML template for BTS metastore external Postgres DB\n"

}

function create_bts_external_db_configmap_template(){
  wait_msg "Creating ibm-bts-config-extension configMap YAML template for BTS metastore external Postgres DB"
  mkdir -p $BTS_SECRET_FOLDER >/dev/null 2>&1
cat << EOF > ${BTS_CONFIGMAP_FILE}
# YAML template for ibm-bts-config-extension configMap
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ibm-bts-config-extension
  namespace: ${bai_services_namespace}
data:
  serverName: "<DatabaseHostName>"
  portNumber: "<DatabasePort>"
  databaseName: <DatabaseName>
  ssl: "true"
  sslMode: verify-ca
  sslSecretName: bts-datastore-edb-secret
  userSecretName: bts-datastore-edb-user
  customPropertyName1: sslKey
  customPropertyValue1: "/opt/ibm/wlp/usr/shared/resources/security/db/tls.key"
EOF
  success "Created bts-datastore-edb-cm configMap YAML template for BTS metastore external Postgres DB\n"
}
