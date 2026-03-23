{{/*
Nome completo do chart
*/}}
{{- define "apisix-poc.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "apisix-poc.fullname" -}}
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

{{- define "apisix-poc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels comuns
*/}}
{{- define "apisix-poc.labels" -}}
helm.sh/chart: {{ include "apisix-poc.chart" . }}
{{ include "apisix-poc.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "apisix-poc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apisix-poc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Nome do servico etcd (headless)
*/}}
{{- define "apisix-poc.etcd.fullname" -}}
{{- if .Values.etcd.fullnameOverride }}
{{- .Values.etcd.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-etcd" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
FQDN do etcd para uso no config do APISIX
Retorna lista de endpoints para todos os membros do cluster
*/}}
{{- define "apisix-poc.etcd.endpoints" -}}
{{- $etcdName := include "apisix-poc.etcd.fullname" . }}
{{- $ns := .Release.Namespace }}
{{- $port := .Values.etcd.clientPort | int }}
{{- $replicas := .Values.etcd.replicaCount | int }}
{{- $endpoints := list }}
{{- range $i, $e := until $replicas }}
{{- $endpoints = append $endpoints (printf "http://%s-%d.%s.%s.svc.cluster.local:%d" $etcdName $i $etcdName $ns $port) }}
{{- end }}
{{- $endpoints | toJson }}
{{- end }}

{{/*
Nome do servico Keycloak
*/}}
{{- define "apisix-poc.keycloak.fullname" -}}
{{- if .Values.keycloak.fullnameOverride }}
{{- .Values.keycloak.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-keycloak" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Nome do servico Postgres do Keycloak
*/}}
{{- define "apisix-poc.postgres.fullname" -}}
{{- printf "%s-keycloak-postgres" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
