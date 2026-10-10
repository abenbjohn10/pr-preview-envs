{{/* Require the values every resource depends on. */}}
{{- define "preview-app.pr" -}}
{{- required "prNumber is required (--set prNumber=N)" .Values.prNumber | toString -}}
{{- end -}}

{{- define "preview-app.image" -}}
{{- printf "%s/%s:%s" .root.Values.imageRegistry .img.repository (.img.tag | toString) -}}
{{- end -}}

{{/* Labels common to every resource. */}}
{{- define "preview-app.labels" -}}
app.kubernetes.io/name: preview-app
app.kubernetes.io/instance: {{ .Release.Name }}
{{ include "preview-app.extraLabels" . }}
{{- end -}}

{{/* Labels that never overlap selector labels; pod templates pair this with preview-app.selector. */}}
{{- define "preview-app.extraLabels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
preview.pr: {{ include "preview-app.pr" . | quote }}
{{- end -}}

{{/* Selector labels for one component: call with (dict "root" . "component" "backend"). */}}
{{- define "preview-app.selector" -}}
app.kubernetes.io/name: preview-app
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "preview-app.postgresName" -}}
{{ .Release.Name }}-postgres
{{- end -}}

{{/* Env vars that build DATABASE_URL; POSTGRES_PASSWORD must precede its use. */}}
{{- define "preview-app.dbEnv" -}}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "preview-app.postgresName" . }}
      key: password
- name: DATABASE_URL
  value: "postgresql+psycopg://{{ .Values.postgres.user }}:$(POSTGRES_PASSWORD)@{{ include "preview-app.postgresName" . }}:5432/{{ .Values.postgres.database }}"
- name: PR_NUMBER
  value: {{ include "preview-app.pr" . | quote }}
- name: GIT_SHA
  value: {{ .Values.gitSha | quote }}
{{- end -}}
