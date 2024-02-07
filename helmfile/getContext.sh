#!/bin/bash
###################################################################################################
# This script is used to load the necessary environment variables to run helmfile                 #
# The single argument passed is to identify that this is being run from github as an action.      #
# The argument can be literally anything, as the script just checks that it exists                #
#                                                                                                 #
# If running locally, no arguments are required. Simply run:                                      #
#                                                                                                 #
# source ./getContext.sh                                                                          #
#                                                                                                 #
###################################################################################################


GITHUB=$1
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

getValue "AWS_ACCOUNT_ID"
getValue "NGINX_TARGET_GROUP_ARN"
