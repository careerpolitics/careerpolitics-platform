{{- define "careerpolitics.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "careerpolitics.labels" -}}
app.kubernetes.io/name: {{ include "careerpolitics.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: Helm
{{- end -}}

{{- define "careerpolitics.name" -}}
{{ .Chart.Name }}
{{- end -}}
