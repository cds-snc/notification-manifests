#!/bin/bash
# This script will create a VPN configuration file for the specified environment
# Usage: ./createVPNConfig.sh <environment>
# Example: ./createVPNConfig.sh staging
export ENVIRONMENT=$1
if [ "$ENVIRONMENT" == "production" ]; then
  VAULT=ppnxsriom3alsxj4ogikyjxlzi
else
  VAULT=4eyyuwddp6w4vxlabrr2i2duxm
fi
#git clone https://github.com/cds-snc/notification-terraform.git /var/tmp/notification-terraform
#op read op://$VAULT/"TERRAFORM_SECRETS_$ENVIRONMENT"/notesPlain > /var/tmp/notification-terraform/aws/$ENVIRONMENT.tfvars   
#cd /var/tmp/notification-terraform/env/$ENVIRONMENT/eks
cd ~/projects/notification-terraform/env/$ENVIRONMENT/eks
#export INFRASTRUCTURE_VERSION=$(cat ../../../.github/workflows/infrastructure_version.txt)
ENDPOINT_ID=$(terragrunt output --raw gha_vpn_id)
CERT=$(terragrunt output --raw gha_vpn_certificate)
KEY=$(terragrunt output --raw gha_vpn_key)
aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id $ENDPOINT_ID --output text > ~/projects/temp/$ENVIRONMENT.ovpn
echo "<cert>
$CERT
</cert>" >> ~/projects/temp/$ENVIRONMENT.ovpn
echo "<key>
$KEY
</key>" >> ~/projects/temp/$ENVIRONMENT.ovpn