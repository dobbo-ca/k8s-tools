{{/*
Expand the name of the chart.
*/}}
{{- define "k8s-tools.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "k8s-tools.fullname" -}}
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
Common labels
*/}}
{{- define "k8s-tools.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "k8s-tools.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "k8s-tools.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8s-tools.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "k8s-tools.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "k8s-tools.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve image tag from variant + postgres version
*/}}
{{- define "k8s-tools.imageTag" -}}
{{- if .Values.image.tag }}
{{- .Values.image.tag }}
{{- else if eq .Values.variant "postgres" }}
{{- printf "postgres-pg%s-latest" .Values.postgres.version }}
{{- else }}
{{- printf "full-latest" }}
{{- end }}
{{- end }}
