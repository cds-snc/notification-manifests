#!/bin/bash
#####################################################################
#                           USAGE                                   #
# This script is used to create the secondary Services/TargetGroups #
#                                                                   #
#   Ensure you are in the correct environment before applying.      #
#   Pass the target environment as an argument ex: scratch          #
#   This must reflect the name of the folder that the kustomize     #
#   overrides/patches exist.                                        #
#####################################################################

# Reset
COLOR_OFF='\033[0m'       # Text Reset

# Regular Colors
RED='\033[0;31m'          # Red
YELLOW='\033[0;33m'       # Yellow
BYELLOW='\033[1;33m'      # Bold Yellow

ENV=$1

CONTEXT=$(kubectl config current-context)

runCommand()
{
    CMD=$1
    eval "$CMD"
    if [ $? != 0 ]; then
        echo -e "{${RED} ERROR: Command: \"$CMD\" Failed. Halting."
        exit 1
    fi
}

echo "This script will DELETE secondary services for Admin, API, DocDownload, and Documentation."
echo -e "${YELLOW}The target environment is: ${BYELLOW} $ENV"
echo -e "${YELLOW}Your current kubernetes context is ${BYELLOW} $CONTEXT"
echo "****VERIFY YOUR CONTEXT IS THE TARGET ENVIRONMENT!****"
echo -e "${COLOR_OFF}"
echo "Are you sure you want to proceed? Only "yes" will be accepted"
read RESPONSE

if [ "$RESPONSE" == "yes" ]; then
    pushd ./secondaryServices/$ENV
    echo "Deleting Secondary TargetGroups..."
    runCommand "kubectl delete -f targetGroups.yaml"
    echo "Done."
    echo "Deleting Secondary TargetGroup Bindings"
    runCommand "kubectl delete -f services.yaml"
    echo "Done."
    popd
    exit 0
else
    echo "USER REQUESTED CANCELLATION"
    exit 0
fi

