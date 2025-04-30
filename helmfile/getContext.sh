#!/bin/bash
###################################################################################################
# This script is used to load the necessary environment variables to run helmfile                 #
# Pass the argument -g to signify that this is being run as a github action                       #
# Pass the argument -i to load the image versions from the text file (for production)             #
# If running locally, no arguments are required. Simply run:                                      #
#                                                                                                 #
# source ./getContext.sh                                                                          #
#                                                                                                 #
###################################################################################################

while getopts 'gih' opt; do
  case "$opt" in
    g)
      echo "Starting from Github Action"
      GITHUB=true
      ;;

    i)
      echo "Loading Image Versions"
      LOAD_IMAGE_VERSIONS=true
      ;;
 
    ?|h)
      echo "Usage: $(basename $0) [-g] [-i]"
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

AWS_REGION="${AWS_REGION:=ca-central-1}"

getValue()
{
    VALUE=$1
    if [ -z $GITHUB ];
    then
      echo "Fetching Secret $VALUE"
      export $VALUE=$(aws secretsmanager get-secret-value --secret-id $VALUE --query SecretString --output text --region $AWS_REGION)      
    else
      echo "$VALUE=$(aws secretsmanager get-secret-value --secret-id $VALUE --query SecretString --output text --region $AWS_REGION)" >> "$GITHUB_ENV"
    fi
}

loadImageVersions()
{
  export ADMIN_DOCKER_TAG=$(cat image_versions.json | jq -r .admin)
  export API_DOCKER_TAG=$(cat image_versions.json | jq -r .api)
  export BLAZER_DOCKER_TAG=$(cat image_versions.json | jq -r .blazer)
  export CERT_MANAGER_DOCKER_TAG=$(cat image_versions.json | jq -r .cert_manager)
  export CLOUDWATCH_AGENT_DOCKER_TAG=$(cat image_versions.json | jq -r .cloudwatch_agent)
  export DOCUMENT_DOWNLOAD_DOCKER_TAG=$(cat image_versions.json | jq -r .document_download)
  export DOCUMENTATION_DOCKER_TAG=$(cat image_versions.json | jq -r .documentation)
  export FLUENTBIT_DOCKER_TAG=$(cat image_versions.json | jq -r .fluentbit)
  export IPV4_DOCKER_TAG=$(cat image_versions.json | jq -r .ipv4)
  export K8S_EVENT_LOGGER_DOCKER_TAG=$(cat image_versions.json | jq -r .k8s_event_logger)
  export KARPENTER_DOCKER_TAG=$(cat image_versions.json | jq -r .karpenter)
  export NGINX_DOCKER_TAG=$(cat image_versions.json | jq -r .nginx)
  
}

getValue "AWS_ACCOUNT_ID"
getValue "NGINX_TARGET_GROUP_ARN"
getValue "INTERNAL_DNS_FQDN"
getValue "ADMIN_TARGET_GROUP_ARN"
getValue "DOCUMENTATION_TARGET_GROUP_ARN"
getValue "DOCUMENT_DOWNLOAD_API_TARGET_GROUP_ARN"
getValue "API_TARGET_GROUP_ARN"
getValue "AWS_REGION"
getValue "BASE_DOMAIN"
getValue "PINPOINT_DEFAULT_POOL_ID"
getValue "PINPOINT_SHORT_CODE_POOL_ID"
getValue "MANIFEST_DOCKER_HUB_PAT"
getValue "MANIFEST_DOCKER_HUB_USERNAME"
getValue "EKS_KARPENTER_AMI_ID"

if [ "$LOAD_IMAGE_VERSIONS" = true ];
then
    loadImageVersions
fi