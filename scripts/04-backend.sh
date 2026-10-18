#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
cat > backend.yaml <<'EOF_YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-page
  namespace: nginx-lab
data:
  index.html.template: |
    <!doctype html>
    <html lang="pl"><meta charset="utf-8">
    <title>Laboratorium NGINX</title>
    <h1>Kubernetes / MicroK8s</h1>
    <p>Wersja strony: v1</p>
    <p>Pod: ${POD_NAME}</p>
    <p>Adres IP: ${POD_IP}</p>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: nginx-lab
  annotations:
    kubernetes.io/change-cause: "Start laboratorium: strona v1"
spec:
  replicas: 8
  revisionHistoryLimit: 10
  minReadySeconds: 5
  progressDeadlineSeconds: 180
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.28
          ports:
            - name: http
              containerPort: 80
          env:
            - name: NGINX_ENVSUBST_OUTPUT_DIR
              value: /usr/share/nginx/html
            - name: NGINX_ENVSUBST_FILTER
              value: '^(POD_NAME|POD_IP)$'
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 2
            timeoutSeconds: 2
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            timeoutSeconds: 2
            periodSeconds: 10
            failureThreshold: 3
          resources:
            requests:
              cpu: 25m
              memory: 32Mi
            limits:
              cpu: 250m
              memory: 128Mi
          volumeMounts:
            - name: nginx-html
              mountPath: /etc/nginx/templates/index.html.template
              subPath: index.html.template
              readOnly: true
      volumes:
        - name: nginx-html
          configMap:
            name: nginx-page
EOF_YAML
k apply -f backend.yaml
k rollout status deployment/nginx --timeout=240s
k get deployment nginx
k get pods -l app=nginx -o wide
