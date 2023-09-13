#!/bin/bash
###################################################################
#                           USAGE                                 #
# This script is used to delete/recreate the notify k8s services. #
#                                                                 #
#   Ensure you are in the correct environment before applying.    #
#   Pass the target environment as an argument ex: scratch        #
#   This must reflect the name of the folder that the kustomize   #
#   overrides/patches exist.                                      #
###################################################################

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

echo "This script will delete and re-create the notify services in Kubernetes."
echo -e "${YELLOW}The target environment is: ${BYELLOW} $ENV"
echo -e "${YELLOW}Your current kubernetes context is ${BYELLOW} $CONTEXT"
echo  -e "${RED}****RUNNING THIS SCRIPT WILL CAUSE DOWNTIME!****"
echo "****VERIFY YOUR CONTEXT IS THE TARGET ENVIRONMENT!****"
echo -e "${COLOR_OFF}"
echo "Are you sure you want to proceed? Only "yes" will be accepted"
read RESPONSE

if [ "$RESPONSE" == "yes" ]; then
    echo "BEGIN: Deleting services..."

    runCommand "kubectl delete service documentation -n notification-canada-ca"
    runCommand "kubectl delete service api -n notification-canada-ca"
    runCommand "kubectl delete service admin -n notification-canada-ca"
    runCommand "kubectl delete service document-download-api -n notification-canada-ca"

    echo "DONE: Deleting Services."
    echo "BEGIN: Kustomize apply..."

    pushd ../env/$ENV
    runCommand "kubectl apply -k ."
    popd

    echo "DONE: Kustomize apply."
    exit 0
else
    echo "USER REQUESTED CANCELLATION"
    exit 0
fi

