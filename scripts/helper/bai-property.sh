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

# VARIABLES FOR LDAP PROPERTY FILE.
LDAP_COMMON_PROPERTY=("LDAP_TYPE"
                      "LDAP_SERVER"
                      "LDAP_PORT"
                      "LDAP_BASE_DN"
                      "LDAP_BIND_DN"
                      "LDAP_BIND_DN_PASSWORD"
                      "LDAP_SSL_ENABLED"
                      "LDAP_SSL_SECRET_NAME"
                      "LDAP_SSL_CERT_FILE_FOLDER"
                      "LDAP_USER_NAME_ATTRIBUTE"
                      "LDAP_USER_DISPLAY_NAME_ATTR"
                      "LDAP_GROUP_BASE_DN"
                      "LDAP_GROUP_NAME_ATTRIBUTE"
                      "LDAP_GROUP_DISPLAY_NAME_ATTR"
                      "LDAP_GROUP_MEMBERSHIP_SEARCH_FILTER"
                      "LDAP_GROUP_MEMBER_ID_MAP")

LDAP_COMMON_CR_MAPPING=("spec.ldap_configuration.lc_selected_ldap_type"
                        "spec.ldap_configuration.lc_ldap_server"
                        "spec.ldap_configuration.lc_ldap_port"
                        "spec.ldap_configuration.lc_ldap_base_dn"
                        "null"
                        "null"
                        "spec.ldap_configuration.lc_ldap_ssl_enabled"
                        "spec.ldap_configuration.lc_ldap_ssl_secret_name"
                        "null"
                        "spec.ldap_configuration.lc_ldap_user_name_attribute"
                        "spec.ldap_configuration.lc_ldap_user_display_name_attr"
                        "spec.ldap_configuration.lc_ldap_group_base_dn"
                        "spec.ldap_configuration.lc_ldap_group_name_attribute"
                        "spec.ldap_configuration.lc_ldap_group_display_name_attr"
                        "spec.ldap_configuration.lc_ldap_group_membership_search_filter"
                        "spec.ldap_configuration.lc_ldap_group_member_id_map")

COMMENTS_LDAP_PROPERTY=("## The possible values are: \"IBM Security Directory Server\" or \"Microsoft Active Directory\""
                        "## The name of the LDAP server to connect"
                        "## The port of the LDAP server to connect.  Some possible values are: 389, 636, etc."
                        "## The LDAP base DN.  For example, \"dc=example,dc=com\", \"dc=abc,dc=com\", etc"
                        "## The LDAP bind DN. For example, \"uid=user1,dc=example,dc=com\", \"uid=user1,dc=abc,dc=com\", etc."
                        "## The password (if password has special characters then Base64 encoded with {Base64} prefix, otherwise use plain text) for LDAP bind DN."
                        "## Enable SSL/TLS for LDAP communication. Refer to Knowledge Center for more info."
                        "## The name of the secret that contains the LDAP SSL/TLS certificate."
                        "## If enabled LDAP SSL, you need copy the SSL certificate file (named ldap-cert.crt) into this directory. Default value is <LDAP_SSL_CERT_FOLDER>"
                        "## The LDAP user name attribute. Semicolon-separated list that must include the first RDN user distinguished names. One possible value is \"*:uid\" for TDS and \"user:sAMAccountName\" for AD. Refer to Knowledge Center for more info."
                        "## The LDAP user display name attribute. One possible value is \"cn\" for TDS and \"sAMAccountName\" for AD. Refer to Knowledge Center for more info."
                        "## The LDAP group base DN.  For example, \"dc=example,dc=com\", \"dc=abc,dc=com\", etc"
                        "## The LDAP group name attribute.  One possible value is \"*:cn\" for TDS and \"*:cn\" for AD. Refer to Knowledge Center for more info."
                        "## The LDAP group display name attribute.  One possible value for both TDS and AD is \"cn\". Refer to Knowledge Center for more info."
                        "## The LDAP group membership search filter string.  One possible value is \"(|(&(objectclass=groupofnames)(member={0}))(&(objectclass=groupofuniquenames)(uniquemember={0})))\" for TDS, and \"(&(cn=%v)(objectcategory=group))\" for AD."
                        "## The LDAP group membership ID map.  One possible value is \"groupofnames:member\" for TDS and \"memberOf:member\" for AD."
                       )

AD_LDAP_PROPERTY=("LC_AD_GC_HOST"
                  "LC_AD_GC_PORT"
                  "LC_USER_FILTER"
                  "LC_GROUP_FILTER")

AD_LDAP_CR_MAPPING=("spec.ldap_configuration.ad.lc_ad_gc_host"
                    "spec.ldap_configuration.ad.lc_ad_gc_port"
                    "spec.ldap_configuration.ad.lc_user_filter"
                    "spec.ldap_configuration.ad.lc_group_filter")

COMMENTS_AD_LDAP_PROPERTY=("## This is the Global Catalog host for the LDAP"
                           "## This is the Global Catalog port for the LDAP"
                           "## One possible value is \"(&(sAMAccountName=%v)(objectcategory=user))\""
                           "## One possible value is \"(&(cn=%v)(objectcategory=group))\"")

TDS_LDAP_PROPERTY=("LC_USER_FILTER"
                  "LC_GROUP_FILTER")

TDS_LDAP_CR_MAPPING=("spec.ldap_configuration.tds.lc_user_filter"
                     "spec.ldap_configuration.tds.lc_group_filter")

COMMENTS_TDS_LDAP_PROPERTY=("## One possible value is \"(&(cn=%v)(objectclass=person))\""
                            "## One possible value is \"(&(cn=%v)(|(objectclass=groupofnames)(objectclass=groupofuniquenames)(objectclass=groupofurls)))\"")

CUSTOM_LDAP_PROPERTY=("LC_USER_FILTER"
                  "LC_GROUP_FILTER")

CUSTOM_LDAP_CR_MAPPING=("spec.ldap_configuration.custom.lc_user_filter"
                     "spec.ldap_configuration.custom.lc_group_filter")

COMMENTS_CUSTOM_LDAP_PROPERTY=("## One possible value is \"(&(objectClass=person)(cn=%v))\""
                            "## One possible value is \"(&(objectClass=group)(cn=%v))\"")