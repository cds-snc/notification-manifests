#!/bin/bash
###################################################################################################
# This script is used to load the necessary environment variables to run helmfile                 #
# Pass the argument -g to signify that this is being run as a github action                       #
# Pass teh argument -i to load the image versions from the text file (for production)             #
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


getValue()
{
    VALUE=$1
    if [ -z $GITHUB ];
    then
      export $VALUE=$(aws secretsmanager get-secret-value --secret-id $VALUE --query SecretString --output text)      
    else
      echo "$VALUE=$(aws secretsmanager get-secret-value --secret-id $VALUE --query SecretString --output text)" >> "$GITHUB_ENV"
    fi
    if [ $? != 0 ]; then
        echo -e "ERROR: Get Secret Failed. Halting."
        exit 1
    fi
}

loadImageVersions()
{
  export ARC_DOCKER_TAG=$(cat image_versions.json | jq -r .github_arc)
}

getValue "AWS_ACCOUNT_ID"
getValue "NGINX_TARGET_GROUP_ARN"
getValue "INTERNAL_DNS_FQDN"
getValue "GITHUB_ARC_RUNNER_REPOSITORY_URL"

if [ -z $GITHUB ];
then
    loadImageVersions
fi