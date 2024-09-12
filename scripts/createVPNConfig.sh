#!/bin/bash
# This script will create a VPN configuration file for the specified environment
# Usage: ./createVPNConfig.sh <environment>
# Example: ./createVPNConfig.sh staging
ENVIRONMENT=$1
git clone https://github.com/cds-snc/notification-terraform.git /var/tmp/notification-terraform
cd /var/tmp/notification-terraform/env/$ENVIRONMENT/eks
export INFRASTRUCTURE_VERSION=$(cat ../../../.github/workflows/infrastructure_version.txt)
ENDPOINT_ID=$(terragrunt output --raw gha_vpn_id)
CERT=$(terragrunt output --raw gha_vpn_certificate)
KEY=$(terragrunt output --raw gha_vpn_key)
aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id $ENDPOINT_ID --output text > /var/tmp/$ENVIRONMENT.ovpn
echo "<cert>
$CERT
</cert>" >> /var/tmp/$ENVIRONMENT.ovpn
echo "<key>
$KEY
</key>" >> /var/tmp/$ENVIRONMENT.ovpn