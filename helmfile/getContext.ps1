<#
.SYNOPSIS
This script is used to load the necessary environment variables to run helmfile.
Pass the argument -g to signify that this is being run as a github action.
Pass the argument -i to load the image versions from the text file (for production).
If running locally, no arguments are required. Simply run:
. .\getContext.ps1
#>

param(
    [switch]$g,
    [switch]$i
)

if ($g) {
    Write-Host "Starting from Github Action"
    $GITHUB = $true
}

if ($i) {
    Write-Host "Loading Image Versions"
    $LOAD_IMAGE_VERSIONS = $true
}

if (!$env:AWS_REGION) {
    $env:AWS_REGION = "ca-central-1"
}

function GetValue {
    param(
        [string]$VALUE
    )
    if (!$GITHUB) {
        Write-Host "Fetching Secret $VALUE"
        $secretValue = aws secretsmanager get-secret-value --secret-id $VALUE --query SecretString --output text --region $env:AWS_REGION
        [Environment]::SetEnvironmentVariable($VALUE, $secretValue, "Process")
    } else {
        Add-Content -Path $env:GITHUB_ENV -Value "$VALUE=$(aws secretsmanager get-secret-value --secret-id $VALUE --query SecretString --output text --region $env:AWS_REGION)"
    }
}

function LoadImageVersions {
    $json = Get-Content -Path image_versions.json | ConvertFrom-Json
    $env:ADMIN_DOCKER_TAG = $json.admin
    $env:API_DOCKER_TAG = $json.api
    $env:BLAZER_DOCKER_TAG = $json.blazer
    $env:CERT_MANAGER_DOCKER_TAG = $json.cert_manager
    $env:CLOUDWATCH_AGENT_DOCKER_TAG = $json.cloudwatch_agent
    $env:DOCUMENT_DOWNLOAD_DOCKER_TAG = $json.document_download
    $env:DOCUMENTATION_DOCKER_TAG = $json.documentation
    $env:FLUENTBIT_DOCKER_TAG = $json.fluentbit
    $env:IPV4_DOCKER_TAG = $json.ipv4
    $env:K8S_EVENT_LOGGER_DOCKER_TAG = $json.k8s_event_logger
    $env:KARPENTER_DOCKER_TAG = $json.karpenter
    $env:NGINX_DOCKER_TAG = $json.nginx
}

GetValue "AWS_ACCOUNT_ID"
GetValue "NGINX_TARGET_GROUP_ARN"
GetValue "INTERNAL_DNS_FQDN"
GetValue "ADMIN_TARGET_GROUP_ARN"
GetValue "DOCUMENTATION_TARGET_GROUP_ARN"
GetValue "DOCUMENT_DOWNLOAD_API_TARGET_GROUP_ARN"
GetValue "API_TARGET_GROUP_ARN"
GetValue "AWS_REGION"
GetValue "BASE_DOMAIN"
GetValue "PINPOINT_DEFAULT_POOL_ID"
GetValue "PINPOINT_SHORT_CODE_POOL_ID"
GetValue "MANIFEST_DOCKER_HUB_PAT"
GetValue "MANIFEST_DOCKER_HUB_USERNAME"

if ($LOAD_IMAGE_VERSIONS) {
    LoadImageVersions
}
