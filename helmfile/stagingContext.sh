#!/bin/bash
echo "NGINX_TARGET_GROUP_ARN=$(aws secretsmanager get-secret-value --secret-id NGINX_TARGET_GROUP_ARN --query SecretString --output text)" >> "$GITHUB_ENV"