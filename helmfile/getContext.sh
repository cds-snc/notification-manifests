#!/bin/bash
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

getValue "NGINX_TARGET_GROUP_ARN"
