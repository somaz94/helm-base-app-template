{{/*
Expand the name of the chart.
*/}}
{{- define "base-aws.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "base-aws.fullname" -}}
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
{{- define "base-aws.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "base-aws.labels" -}}
helm.sh/chart: {{ include "base-aws.chart" . }}
{{ include "base-aws.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "base-aws.selectorLabels" -}}
app.kubernetes.io/name: {{ include "base-aws.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "base-aws.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "base-aws.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Pod template (metadata + spec) shared by deployment.yaml and rollout.yaml so the two
never drift. Rendered verbatim under `spec.template:` with the original 4-space indent.
*/}}
{{- define "base-aws.podTemplate" }}
    metadata:
      annotations:
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        image-tag: {{ required "image.tag must be set per service (no appVersion fallback)" .Values.image.tag | quote }}
        {{- if and .Values.initContainers (and .Values.initContainers.enabled .Values.initContainers.items) }}
        init-containers-checksum: {{ .Values.initContainers | toJson | sha256sum }}
        {{- end }}
      labels:
        {{- include "base-aws.selectorLabels" . | nindent 8 }}
        {{- if .Values.version }}
        version: {{ .Values.version | toString | quote }}
        {{- end }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "base-aws.serviceAccountName" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ . }}
      {{- end }}
      {{- if and .Values.initContainers (and .Values.initContainers.enabled .Values.initContainers.items) }}
      initContainers:
        {{- range $initContainer := .Values.initContainers.items }}
        - name: {{ $initContainer.name }}
          image: {{ $initContainer.image }}
          {{- if $initContainer.imagePullPolicy }}
          imagePullPolicy: {{ $initContainer.imagePullPolicy }}
          {{- end }}
          {{- if $initContainer.command }}
          command:
            {{- toYaml $initContainer.command | nindent 12 }}
          {{- end }}
          {{- if $initContainer.args }}
          args:
            {{- toYaml $initContainer.args | nindent 12 }}
          {{- end }}
          {{- if $initContainer.env }}
          env:
            {{- if $.Values.environment }}
            - name: ENVIRONMENT
              value: {{ $.Values.environment | quote }}
            {{- end }}
            {{- toYaml $initContainer.env | nindent 12 }}
          {{- else if $.Values.environment }}
          env:
            - name: ENVIRONMENT
              value: {{ $.Values.environment | quote }}
          {{- end }}
          {{- if $initContainer.envFrom }}
          envFrom:
            {{- toYaml $initContainer.envFrom | nindent 12 }}
          {{- end }}
          {{- if $initContainer.volumeMounts }}
          volumeMounts:
            {{- toYaml $initContainer.volumeMounts | nindent 12 }}
          {{- end }}
          {{- if $initContainer.resources }}
          resources:
            {{- toYaml $initContainer.resources | nindent 12 }}
          {{- end }}
          {{- if $initContainer.securityContext }}
          securityContext:
            {{- toYaml $initContainer.securityContext | nindent 12 }}
          {{- end }}
        {{- end }}
      {{- end }}
      containers:
        - name: {{ include "base-aws.fullname" . }}
          {{- with .Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          image: "{{ .Values.image.repository }}:{{ required "image.tag must be set per service (no appVersion fallback)" .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          {{- if or (.Values.environment) (gt (len .Values.envConfig) 0) }}
          env:
          {{- if .Values.environment }}
            - name: ENVIRONMENT
              value: {{ .Values.environment | quote }}
          {{- end }}
          {{- range $key, $value := .Values.envConfig }}
            - name: {{ $key }}
              value: {{ $value | quote }}
          {{- end }}
          {{- end }}
          {{- $hasConfigs := and .Values.configs (and .Values.configs.enabled .Values.configs.items) }}
          {{- $hasExternalSecrets := and .Values.externalSecrets .Values.externalSecrets.enabled }}
          {{- if or $hasConfigs $hasExternalSecrets }}
          envFrom:
          {{- if $hasConfigs }}
          {{- range $config := .Values.configs.items }}
            - configMapRef:
                name: {{ $config.name }}
          {{- end }}
          {{- end }}
          {{- if $hasExternalSecrets }}
            # secretRef comes AFTER configMapRef so the ExternalSecret-backed keys win on
            # any collision (later envFrom entries take precedence). The Secret is created by
            # templates/externalsecret.yaml; name matches "<fullname>-secret".
            - secretRef:
                name: {{ include "base-aws.fullname" . }}-secret
          {{- end }}
          {{- end }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          {{- with .Values.startupProbe }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.lifecycle }}
          lifecycle:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if .Values.efs.persistentVolumeClaims.enabled }}
          volumeMounts:
            {{- with .Values.volumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
            {{- range .Values.efs.persistentVolumeClaims.items }}
            - name: {{ .name | replace "-pvc" "" }}
              mountPath: {{ .mountPath }}
              {{- if .readOnly }}
              readOnly: {{ .readOnly }}
              {{- end }}
            {{- end }}
          {{- else }}
          {{- with .Values.volumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- end }}
      {{- if .Values.efs.persistentVolumeClaims.enabled }}
      volumes:
        {{- with .Values.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- range .Values.efs.persistentVolumeClaims.items }}
        - name: {{ .name | replace "-pvc" "" }}
          persistentVolumeClaim:
            claimName: {{ .name }}
        {{- end }}
      {{- else }}
      {{- with .Values.volumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
