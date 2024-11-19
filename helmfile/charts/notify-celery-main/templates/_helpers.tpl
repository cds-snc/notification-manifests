{{/*
Expand the name of the chart.
*/}}
{{- define "celery-main.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "celery-main.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "celery-main.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "celery-main.labels" -}}
helm.sh/chart: {{ include "celery-main.chart" . }}
{{ include "celery-main.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "celery-main.selectorLabels" -}}
app.kubernetes.io/name: {{ include "celery-main.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "celery-main.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "celery-main.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "envVars" -}}
- name: ADMIN_BASE_URL
  value: {{ .Values.celeryCommon.adminBaseUrl }}
- name: ALLOW_HTML_SERVICE_IDS
  value: {{ .Values.celeryCommon.allowHtmlServiceIds }}
- name: API_HOST_NAME
  value: {{ .Values.celeryCommon.apiHostName }}
- name: ASSET_UPLOAD_BUCKET_NAME
  value: {{ .Values.celeryCommon.assetUploadBucketName }}
- name: AWS_PINPOINT_REGION
  value: {{ .Values.celeryCommon.awsPinpointRegion }}
- name: AWS_REGION
  value: {{ .Values.celeryCommon.awsRegion }}
- name: BULK_SEND_TEST_SERVICE_ID
  value: {{ .Values.celeryCommon.bulkSendTestServiceId }}
- name: CSV_UPLOAD_BUCKET_NAME
  value: {{ .Values.celeryCommon.csvUploadBucketName }}
- name: DOCUMENT_DOWNLOAD_API_HOST
  value: {{ .Values.celeryCommon.documentDownloadApiHost }}
- name: FIDO2_DOMAIN
  value: {{ .Values.celeryCommon.fido2Domain }}
- name: HC_EN_SERVICE_ID
  value: {{ .Values.celeryCommon.hcEnServiceId }}
- name: HC_FR_SERVICE_ID
  value: {{ .Values.celeryCommon.hcFrServiceId }}
- name: NOTIFY_EMAIL_DOMAIN
  value: {{ .Values.celeryCommon.notifyEmailDomain }}
- name: NOTIFY_ENVIRONMENT
  value: {{ .Values.celeryCommon.notifyEnvironment }}
- name: NOTIFICATION_QUEUE_PREFIX
  value: {{ .Values.celeryCommon.notificationQueuePrefix }}
- name: REDIS_ENABLED
  value: {{ .Values.celeryCommon.redisEnabled }}
- name: AWS_US_TOLL_FREE_NUMBER
  value: {{ .Values.celeryCommon.awsUsTollFreeNumber }}
- name: SENTRY_URL
  value: {{ .Values.celeryCommon.sentryUrl }}
- name: NEW_RELIC_DISTRIBUTED_TRACING_ENABLED
  value: {{ .Values.celeryCommon.newRelicDistributedTracingEnabled }}
- name: NEW_RELIC_MONITOR_MODE
  value: {{ .Values.celeryCommon.newRelicMonitorMode }}
- name: AWS_XRAY_CONTEXT_MISSING
  value: {{ .Values.celeryCommon.awsXrayContextMissing }}
- name: AWS_XRAY_DAEMON_ADDRESS
  value: {{ .Values.celeryCommon.awsXrayDaemonAddress }}
- name: AWS_XRAY_SDK_ENABLED
  value: {{ .Values.celeryCommon.awsXraySdkEnabled }}
- name: NEW_RELIC_MONITOR_MODE
  value: {{ .Values.celeryCommon.newRelicMonitorMode }}
- name: ASSET_DOMAIN
  value: {{ .Values.celeryCommon.assetDomain }}
- name: BATCH_INSERTION_CHUNK_SIZE
  value: {{ .Values.celeryCommon.batchInsertionChunkSize }}
- name: CELERY_CONCURRENCY
  value: {{ .Values.celeryCommon.celeryConcurrency }}
- name: FF_CLOUDWATCH_METRICS_ENABLED
  value: {{ .Values.celeryCommon.ffCloudwatchMetricsEnabled }}
- name: FF_ANNUAL_LIMIT
  value: {{ .Values.celeryCommon.ffAnnualLimit }}
{{- end -}}
{{- define "envSecrets" -}}
- name: ADMIN_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: ADMIN_CLIENT_SECRET
- name: DANGEROUS_SALT
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: DANGEROUS_SALT
- name: SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: SECRET_KEY
- name: SENDGRID_API_KEY
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: SENDGRID_API_KEY
- name: SQLALCHEMY_DATABASE_URI
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: SQLALCHEMY_DATABASE_URI
- name: SQLALCHEMY_DATABASE_READER_URI
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: SQLALCHEMY_DATABASE_READER_URI
- name: NEW_RELIC_LICENSE_KEY
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: NEW_RELIC_LICENSE_KEY
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: REDIS_URL
- name: REDIS_PUBLISH_URL
  valueFrom:
    secretKeyRef:
      name: notify-celery-main
      key: REDIS_PUBLISH_URL
{{- end -}}