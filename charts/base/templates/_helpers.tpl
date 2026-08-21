{{/*
Expand the name of the chart.
*/}}
{{- define "base.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "base.fullname" -}}
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
{{- define "base.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "base.labels" -}}
helm.sh/chart: {{ include "base.chart" . }}
{{ include "base.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "base.selectorLabels" -}}
app.kubernetes.io/name: {{ include "base.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "base.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "base.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the imagePullSecret
*/}}
{{- define "base.imagePullSecret" }}
{{- with .Values.imageCredentials }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password (printf "%s:%s" .username .password | b64enc) | b64enc }}
{{- end }}
{{- end }}

{{/*
Pod template (metadata + spec). Extracted from deployment.yaml so the pod spec lives in one
place (mirrors base-aws.podTemplate). Rendered verbatim under `spec.template:` with the original
4-space indent. Called with the root context (`.`), so `$.Values` inside the init-container loop
still resolves to the chart root.
*/}}
{{- define "base.podTemplate" }}
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
        {{- include "base.selectorLabels" . | nindent 8 }}
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
      serviceAccountName: {{ include "base.serviceAccountName" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ . }}
      {{- end }}
      volumes:
        {{- if and .Values.persistentVolumeClaims (and .Values.persistentVolumeClaims.enabled .Values.persistentVolumeClaims.items) }}
        {{- range $persistentVolumeClaim := .Values.persistentVolumeClaims.items }}
        - name: {{ $persistentVolumeClaim.name }}
          persistentVolumeClaim:
            claimName: {{ $persistentVolumeClaim.name }}
        {{- end }}
        {{- end }}
        {{- if and .Values.emptyDirVolumes (and .Values.emptyDirVolumes.enabled .Values.emptyDirVolumes.items) }}
        {{- range $emptyDir := .Values.emptyDirVolumes.items }}
        - name: {{ $emptyDir.name }}
          emptyDir:
            {{- if $emptyDir.sizeLimit }}
            sizeLimit: {{ $emptyDir.sizeLimit }}
            {{- end }}
            {{- if $emptyDir.medium }}
            medium: {{ $emptyDir.medium }}
            {{- end }}
        {{- end }}
        {{- end }}
        {{- with .Values.extraVolumes }}
        {{- toYaml . | nindent 8 }}
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
        - name: {{ include "base.fullname" . }}
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
          {{- if and .Values.configs (and .Values.configs.enabled .Values.configs.items) }}
          envFrom:
          {{- range $config := .Values.configs.items }}
            - configMapRef:
                name: {{ $config.name }}
          {{- end }}
          {{- end }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          volumeMounts:
            {{- if and .Values.persistentVolumeClaims (and .Values.persistentVolumeClaims.enabled .Values.persistentVolumeClaims.items) }}
            {{- range $persistentVolumeClaim := .Values.persistentVolumeClaims.items }}
            - name: {{ $persistentVolumeClaim.name }}
              mountPath: {{ $persistentVolumeClaim.mountPath }}
            {{- end }}
            {{- end }}
            {{- if and .Values.emptyDirVolumes (and .Values.emptyDirVolumes.enabled .Values.emptyDirVolumes.items) }}
            {{- range $emptyDir := .Values.emptyDirVolumes.items }}
            - name: {{ $emptyDir.name }}
              mountPath: {{ $emptyDir.mountPath }}
              {{- if $emptyDir.readOnly }}
              readOnly: {{ $emptyDir.readOnly }}
              {{- end }}
            {{- end }}
            {{- end }}
            {{- with .Values.extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
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
{{- end }}