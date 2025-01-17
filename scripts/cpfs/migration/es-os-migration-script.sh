#!/bin/bash
# Script Name: elastic_opensearch_migration.sh
# Author: Tamilanban Rajendran <tamilanban.rajendran@ibm.com>
# Co-Author: Infant Sabin <infant.sabin.a@ibm.com>
# Description: The following script retrieves all indices, mappings and aliases from Elasticsearch, restores them in OpenSearch and validates the document count of the OpenSearch index against Elasticsearch to ensure the successful migration of data

# Elasticsearch and OpenSearch credentials
export ELASTICSEARCH_URL
export OPENSEARCH_URL
export ELASTIC_USERNAME
export ELASTIC_PASSWORD
export OPENSEARCH_USERNAME
export OPENSEARCH_PASSWORD

# Function to check if required environment variables are set
check_env_vars() {
    local vars=("ELASTICSEARCH_URL" "OPENSEARCH_URL" "ELASTIC_USERNAME" "ELASTIC_PASSWORD" "OPENSEARCH_USERNAME" "OPENSEARCH_PASSWORD")
    for var in "${vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Error: $var should not be empty."
            usage
        fi
    done
}

check_env_vars

# Function to print usage
usage() {
    echo "Usage: $0 [-dryrun] [-include=<comma separated indices>] [-exclude=<comma separated indices>] [-include_regex=<regex pattern>] [-exclude_regex=<regex pattern>] [-starttime=<start time>] [-endtime=<end time>] [logfile] [--help]"
    echo "Options:"
    echo "  -dryrun                                   List of indices of elastic and displaying dry run steps"
    echo "  -include=<comma separated indices>        List of indices to include"
    echo "  -exclude=<comma separated indices>        List of indices to exclude"
    echo "  -include_regex=<regex pattern>            Regex pattern to include indices"
    echo "  -exclude_regex=<regex pattern>            Regex pattern to exclude indices"
    echo "  -starttime=<start time>                   Start time for data migration (format: 'YYYY-MM-DDTHH:MM:SS')"
    echo "  -endtime=<end time>                       End time for data migration (format: 'YYYY-MM-DDTHH:MM:SS')"
    echo "  logfile                                   Optional: Log file to save migration summary"
    echo "  --help                                    Display usage details"
    exit 1
}


# Parse command line arguments
logfile=""
dryrun=false
include_indices=""
exclude_indices=""
include_regex=""
exclude_regex=""
# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -dryrun)
            dryrun=true
            ;;
        -include=*)
            include_indices=$(echo "${1#*=}" | tr ',' '\n')
            ;;
        -exclude=*)
            exclude_indices=$(echo "${1#*=}" | tr ',' '\n')
            ;;
        -include_regex=*)
            include_regex="${1#*=}"
            ;;
        -exclude_regex=*)
            exclude_regex="${1#*=}"
            ;;
        -starttime=*)
            START_TIME="${1#*=}"
            ;;
        -endtime=*)
            END_TIME="${1#*=}"
            ;;
        --help)
            usage
            ;;
        -*) ;;
        *)
            logfile=$1
            shift
            ;;
    esac
    shift
done

# Start time for total migration
total_start=$(date +%s)

# Arrays to store index migration status and reasons
migration_indices=()
migration_status=()
migration_reason=()


# Function to check if the migration was successful for an index
check_migration_status() {
  index="$1"
  response=$(curl -s -X GET -u "$OPENSEARCH_USERNAME:$OPENSEARCH_PASSWORD" --insecure "$OPENSEARCH_URL/${index}/_count")
  count=$(echo "$response" | jq -r '.count')

  if [ "$count" != "null" ]; then
    if [ "$count" -gt 0 ]; then
     echo "Migration of index $index successful with count $count."
     migration_status+=("Success with $count document")
    else
      echo "Migration of index $index successful with count $count."
      migration_status+=("Success with $count document")
    fi
  else
  echo "Migration of index $index failed."
  migration_status+=("Failed")
  fi
}

# Function to migrate aliases for an index from Elasticsearch to OpenSearch
migrate_aliases() {
  source_index="$1"
  dest_index="$2"

  if $dryrun; then
        echo "Processing alias:"
        local action="{
                \"actions\": [
                {
                    \"add\": {
                    \"index\": \"${dest_index}\",
                    \"alias\": \"${alias_name}\"
                    }
                }
                ]
            }"
       echo "curl -X POST -u OPENSEARCH_USERNAME:OPENSEARCH_PASSWORD --insecure OPENSEARCH_URL/_aliases -H 'Content-Type: application/json' -d '${action}'"
       return 0 
   fi
  # Migrate aliases from Elasticsearch to OpenSearch
  aliases=$(curl -s -X GET -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" --insecure "$ELASTICSEARCH_URL/${source_index}")

  # Extract and migrate aliases using jq
  alias_names=$(echo "$aliases" | jq -r '.[].aliases | keys[]')


  for alias_name in $alias_names; do
    echo "Processing alias: $alias_name"
    curl -X POST -u "$OPENSEARCH_USERNAME:$OPENSEARCH_PASSWORD" --insecure "$OPENSEARCH_URL/_aliases" -H 'Content-Type: application/json' -d "
        {
            \"actions\": [
            {
                \"add\": {
                \"index\": \"${dest_index}\",
                \"alias\": \"${alias_name}\"
                }
            }
            ]
        }"
  done
}

# Function to perform bulk reindexing with retry and capture index summary
bulk_reindex_with_retry() {
  reindex_request="$1"
  index="$2"
  retries=3
  retry_delay=5
  response=""

  for ((attempt = 1; attempt <= retries; attempt++)); do
    if $dryrun; then
        echo "curl -s -X POST -u OPENSEARCH_USERNAME:OPENSEARCH_PASSWORD --insecure OPENSEARCH_URL/_reindex -H 'Content-Type: application/json' -d ${reindex_request}"
        return 0
    else
        response=$(curl -s -X POST -u "$OPENSEARCH_USERNAME:$OPENSEARCH_PASSWORD" --insecure "$OPENSEARCH_URL/_reindex" -H 'Content-Type: application/json' -d "$reindex_request")
        # Check if reindexing request was successful
        if [ $? -eq 0 ]; then
            # Check if the response contains any error message
            error=$(echo "$response" | jq -r '.error')
            if [ "$error" != "null" ]; then
                echo "Reindexing attempt $attempt failed for index $index: $error. Retrying in $retry_delay seconds..."
                sleep $retry_delay
            else
                return 0
            fi
        else
            echo "Reindexing attempt $attempt failed for index $index. Retrying in $retry_delay seconds..."
            sleep $retry_delay
        fi
    fi
  done

  # All retry attempts failed
  echo "Maximum number of retries exceeded for index $index. Reindexing failed."
  migration_reason+=("Maximum number of retries exceeded")
  return 1
}

# Function to include indices based on regex pattern
include_indices_regex() {
    local regex="$1"
    local indices_array=("${!2}")
    local included_indices=()

    # Iterate through each index in the indices array
    for index in "${indices_array[@]}"; do
        # Check if the index matches the regex pattern
        if [[ $index =~ $regex ]]; then
            included_indices+=("$index")
        fi
    done

    # Return the array of included indices
    echo "${included_indices[@]}"
}

# Fetch all indices from Elasticsearch
all_indices=$(curl -s -X GET -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" --insecure "$ELASTICSEARCH_URL/_cat/indices" | awk '{print $3}' | tr '\n' ',' | sed 's/,$//')

# Convert comma-separated indices to an array
IFS=',' read -ra SOURCE_INDICES <<< "$all_indices"

echo "All indices fetched from Elasticsearch:"
echo "$all_indices"
# echo "$SOURCE_INDICES"

# Check if -include_indices is provided
if [[ ! -z $include_indices ]]; then
    # Convert comma-separated include_indices to an array
    include_indices_array=($(echo "$include_indices" | tr ',' '\n'))
    
    # Initialize an empty array to store valid included indices
    valid_included_indices=()
    
    # Iterate through each index specified with -include_indices
    for include_index in "${include_indices_array[@]}"; do
        # Check if the include_index exists in the list of all indices
        if [[ " ${SOURCE_INDICES[@]} " =~ " $include_index " ]]; then
            # If the include_index exists, add it to the list of valid included indices
            valid_included_indices+=("$include_index")
        else
            # If the include_index does not exist, print a warning message
            echo "Warning: Index '$include_index' specified with -include_indices does not exist in Elasticsearch."
        fi
    done
    
    # Set SOURCE_INDICES to valid_included_indices
    SOURCE_INDICES=("${valid_included_indices[@]}")
fi


# Check if -include_regex is provided
if [[ ! -z $include_regex ]]; then
    filtered_indices_array=($(include_indices_regex "$include_regex" SOURCE_INDICES[@]))
    # Set SOURCE_INDICES to valid_included_indices
    SOURCE_INDICES=("${filtered_indices_array[@]}")
fi

# Check if -exclude_indices is provided
if [[ ! -z $exclude_indices ]]; then
    # Convert comma-separated exclude_indices to an array
    exclude_indices_array=($(echo "$exclude_indices" | tr ',' '\n'))

    # Initialize an empty array to store valid excluded indices
    valid_excluded_indices=()

    # Iterate through each index specified with -exclude_indices
    for exclude_index in "${exclude_indices_array[@]}"; do
        # Check if the exclude_index exists in the list of all indices
        if [[ " ${SOURCE_INDICES[@]} " =~ " $exclude_index " ]]; then
            # If the exclude_index exists, remove it from the list of SOURCE_INDICES
            SOURCE_INDICES=("${SOURCE_INDICES[@]/$exclude_index}")
        else
            # If the exclude_index does not exist, print a warning message
            echo "Warning: Index '$exclude_index' specified with -exclude_indices does not exist in Elasticsearch."
        fi
    done
fi

# Check if -exclude_regex is provided
if [[ ! -z $exclude_regex ]]; then
    # Iterate through each index in the list of all indices
    for index in "${SOURCE_INDICES[@]}"; do
        # Check if the index matches the regex pattern
        if [[ $index =~ $exclude_regex ]]; then
            # If the index matches, remove it from the list of SOURCE_INDICES
            SOURCE_INDICES=("${SOURCE_INDICES[@]/$index}")
        fi
    done
fi

# Remove empty values from the SOURCE_INDICES array
filtered_indices=()
for index in "${SOURCE_INDICES[@]}"; do
    if [[ -n "$index" ]]; then
        filtered_indices+=("$index")
    fi
done

# Assign the filtered indices back to SOURCE_INDICES
SOURCE_INDICES=("${filtered_indices[@]}")


# Print the list of indices
printf "\nIndices to include:\n"
printf '%s\n' "${SOURCE_INDICES[@]}"

# Create destination indices with prefix "<cloudpak>-eos-"
DEST_INDICES=()
for source_index in "${SOURCE_INDICES[@]}"; do
  # Get mappings from Elasticsearch
  mappings=$(curl -s -X GET -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" --insecure "$ELASTICSEARCH_URL/$source_index/_mappings")
  
  #Normalized mapping object to avoid parsing exception
  normalized_mapping=$(echo "$mappings" | jq '.[] | { mappings: .mappings }')

  dest_index="${source_index}"
  printf "\nCreating an index :: ${dest_index} in OpenSearch with mappings based on Elasticsearch:${source_index}\n"
  # Create index in OpenSearch with mappings
  if $dryrun; then
    echo "curl -X PUT -u OPENSEARCH_USERNAME:OPENSEARCH_PASSWORD -H 'Content-Type: application/json' --insecure OPENSEARCH_URL/dest_index -d normalized_mapping"
  else
    curl -X PUT -u "$OPENSEARCH_USERNAME:$OPENSEARCH_PASSWORD" -H 'Content-Type: application/json' --insecure "$OPENSEARCH_URL/$dest_index" -d "$normalized_mapping"
  fi

  DEST_INDICES+=("$dest_index")
done

# Start time for reindexing
reindex_start=$(date +%s)

# Perform bulk reindex for each index present in Elasticsearch
for ((i=0; i<${#SOURCE_INDICES[@]}; i++)); do
  # Print index information for debugging
  printf "\nProcessing index: ${SOURCE_INDICES[i]} -> ${DEST_INDICES[i]}"
  # Construct reindexing request
  if [[ ! -z $START_TIME && ! -z $END_TIME ]]; then
    # Reindexing request with time range
    if $dryrun; then
        reindex_request="{
        \"source\": {
            \"remote\": {
            \"host\": \"ELASTICSEARCH_URL\",
            \"username\": \"ELASTIC_USERNAME\",
            \"password\": \"ELASTIC_PASSWORD\"
            },
            \"index\": \"${SOURCE_INDICES[i]}\",
            \"query\": {
            \"range\": {
                \"timestamp\": {
                \"gte\": \"$START_TIME\",
                \"lte\": \"$END_TIME\"
                }
            }
            }
        },
        \"dest\": {
            \"index\": \"${DEST_INDICES[i]}\"
        }
        }"
    else
        reindex_request="{
        \"source\": {
            \"remote\": {
            \"host\": \"$ELASTICSEARCH_URL\",
            \"username\": \"$ELASTIC_USERNAME\",
            \"password\": \"$ELASTIC_PASSWORD\"
            },
            \"index\": \"${SOURCE_INDICES[i]}\",
            \"query\": {
            \"range\": {
                \"timestamp\": {
                \"gte\": \"$START_TIME\",
                \"lte\": \"$END_TIME\"
                }
            }
            }
        },
        \"dest\": {
            \"index\": \"${DEST_INDICES[i]}\"
        }
        }"
    fi
  else
    if $dryrun; then
        reindex_request="{
        \"source\": {
            \"remote\": {
            \"host\": \"ELASTICSEARCH_URL\",
            \"username\": \"ELASTIC_USERNAME\",
            \"password\": \"ELASTIC_PASSWORD\"
            },
            \"index\": \"${SOURCE_INDICES[i]}\"
        },
        \"dest\": {
            \"index\": \"${DEST_INDICES[i]}\"
        }
        }"
    else
        # Regular reindexing request without time range
        reindex_request="{
        \"source\": {
            \"remote\": {
            \"host\": \"$ELASTICSEARCH_URL\",
            \"username\": \"$ELASTIC_USERNAME\",
            \"password\": \"$ELASTIC_PASSWORD\"
            },
            \"index\": \"${SOURCE_INDICES[i]}\"
        },
        \"dest\": {
            \"index\": \"${DEST_INDICES[i]}\"
        }
        }"
    fi
  fi

  # Execute bulk reindexing with retry
  bulk_reindex_with_retry "$reindex_request" "${DEST_INDICES[i]}"
  migration_indices+=("${DEST_INDICES[i]}")
done

if $dryrun; then
    printf "\nIt will check the migration status and update it in summary.\n"
fi
# End time for reindexing
reindex_end=$(date +%s)
reindex_time=$((reindex_end - reindex_start))

# Migrate aliases for each index
for ((i=0; i<${#SOURCE_INDICES[@]}; i++)); do
  # Print index information for debugging
  printf "\nMigrating aliases for Elasticsearch index to OpenSearch: ${SOURCE_INDICES[i]} -> ${DEST_INDICES[i]}"
  migrate_aliases "${SOURCE_INDICES[i]}" "${DEST_INDICES[i]}"
done
 
if $dryrun; then
    printf "\nIt will validate docs.count of migrated indices against same indices presented in Elasticsearch."
    printf "\nAt the end of script, it will print summary."
else
    # End time for total migration
    total_end=$(date +%s)
    total_time=$((total_end - total_start))


    # Function to get list of indices from Elasticsearch
    get_es_indices() {
        indices=$(curl -s -XGET  -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" --insecure "$ELASTICSEARCH_URL/_cat/indices" | awk '{print $3}')
        echo "$indices"
    }

    # Function to get document count from Elasticsearch index
    get_es_doc_count() {
        index="$1"
        es_doc_count=$(curl -s -XGET  -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" --insecure "$ELASTICSEARCH_URL/$index/_count" | jq -r '.count')
        echo "$es_doc_count"
    }

    # Function to get document count from OpenSearch index
    get_os_doc_count() {
        index="$1"
        os_doc_count=$(curl -s -XGET -u "$OPENSEARCH_USERNAME:$OPENSEARCH_PASSWORD" --insecure "$OPENSEARCH_URL/$index/_count" | jq -r '.count')
        echo "$os_doc_count"
    }

    echo "Index document count validation for opensearch in progress....."

    # Get the list of indices from Elastic
    #indices_to_check=$(get_es_indices)
    indices_to_check=("${SOURCE_INDICES[@]}")
    # Associative array to track the previous document count for each index
    declare prev_doc_count=()

    # Associative array to track consecutive iterations with the same document count for each index
    declare consecutive_same_count=()

    # Maximum number of consecutive iterations with the same document count before considering it an issue
    MAX_CONSECUTIVE_SAME_COUNT=5

    # Continuously check and print Elasticsearch and OpenSearch document counts at regular intervals
    while [[ -n "${indices_to_check// /}" ]]; do
        indices_to_check=$(echo "$indices_to_check" | tr -s ' ')
        echo "Indices to check: $indices_to_check"
        for index in $indices_to_check; do
            es_doc_count=$(get_es_doc_count "$index")
            os_doc_count=$(get_os_doc_count "$index")

            echo "Index: $index"
            echo "Elasticsearch document count: $es_doc_count"
            echo "OpenSearch document count: $os_doc_count"
        
            if [ "$es_doc_count" -eq "$os_doc_count" ]; then
                echo "Document counts match for index: $index"
                indices_to_check=$(echo "$indices_to_check" | grep -v -w "$index")
            else
                echo "Document counts do not match for index: $index"
                echo "prev_doc_count: $prev_doc_count["$index"]"
                echo "consecutive_same_count:  $consecutive_same_count["$index"]"
                if [[ -n "${prev_doc_count["$index"]}" && "${prev_doc_count["$index"]}" =~ ^[0-9]+$ ]]; then
                    if [ "${prev_doc_count["$index"]}" -eq "$os_doc_count" ]; then
                        # Increment consecutive same count for this index
                        consecutive_same_count["$index"]=$(( ${consecutive_same_count["$index"]} + 1 ))
                        # Check if consecutive same count exceeds the threshold
                        if [ ${consecutive_same_count["$index"]} -ge $MAX_CONSECUTIVE_SAME_COUNT ]; then
                            echo "Document count for index '$index' has remained unchanged for $MAX_CONSECUTIVE_SAME_COUNT consecutive iterations. Removing from the list."
                            indices_to_check=$(echo "$indices_to_check" | grep -v -w "$index")
                        fi
                    else
                        # Reset consecutive same count and update previous document count for this index
                        consecutive_same_count["$index"]=0
                        prev_doc_count["$index"]=$os_doc_count
                    fi
                else
                    echo "Warning: Previous document count for index $index is either empty or not a valid number."
                    os_doc_count=$(get_os_doc_count "$index")
                    echo "Initializing the prev_doc_count value of the respective index for validation of consecutive identical document counts of that index: $os_doc_count"
                    prev_doc_count["$index"]=$os_doc_count
                    consecutive_same_count["$index"]=0
                fi
            fi
        done
    
        indices_to_check=$(echo "$indices_to_check" | tr -s ' ')
        echo "Number of indices left to check: $(echo "$indices_to_check" | tr -d '[:space:]' | wc -w)"
        
        if [[ -z "${indices_to_check// /}" ]]; then
            echo "Exiting While loop. All document counts match executed."
            break
        fi
    
        sleep 3  # Interval in seconds
    done

    echo "Index document count validation done for Opensearch"
    # Check migration status for each destination index
    for dest_index in "${migration_indices[@]}"; do
        check_migration_status "$dest_index"
    done
    # End time for total migration
    total_data_mig=$(date +%s)
    total_data_mig_time=$((total_data_mig - total_start))

    # Print migration summary to console and log file if provided
    print_migration_summary() {
    local -r padding="    "
    local -r separator="|"
    local -r line="---------------------------------------------------------"

    printf "\nMigration Summary:\n"
    printf "==================\n\n"
    printf "Index Name${padding}Migration Status${padding}Reason for Failure\n"
    printf "%s\n" "$line"

    for ((i=0; i<${#migration_indices[@]}; i++)); do
        printf "%s%s%s%s%s\n" \
        "${migration_indices[i]}" \
        "$padding" \
        "${migration_status[i]}" \
        "$padding" \
        "${migration_reason[i]}"
    done

    printf "\nReindexing Time: ${reindex_time} seconds\n"
    printf "Total Script Execution Time: ${total_time} seconds\n"
    printf "Total Data Migration Time: ${total_data_mig_time} seconds\n"
    }

    print_migration_summary
    # Check if logfile is provided, redirect console output to both console and file
    if [[ ! -z "$logfile" ]]; then
        exec > >(tee -a "$logfile") 2>&1
        print_migration_summary
    fi
fi