#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
require_node_ip
DNS_IP=$(microk8s kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')
cat > default.conf.template <<'EOF_CONF'
resolver ${DNS_IP} valid=5s ipv6=off;
resolver_timeout 2s;
upstream nginx_backends {
    zone nginx_backends 64k;
    server nginx-headless.nginx-lab.svc.cluster.local:80 resolve;
}
server {
    listen 80;
    location = /healthz {
        access_log off;
        return 200 "ok\n";
    }
    location / {
        proxy_pass http://nginx_backends;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 2s;
        proxy_read_timeout 5s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        add_header X-Upstream-Addr $upstream_addr always;
    }
}
EOF_CONF
k create configmap nginx-lb-conf --from-file=default.conf.template \
  --dry-run=client -o yaml > lb-configmap.yaml
k apply -f lb-configmap.yaml
cat > lb.yaml <<'EOF_YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-lb
  namespace: nginx-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-lb
  template:
    metadata:
      labels:
        app: nginx-lb
    spec:
      containers:
        - name: nginx-lb
          image: nginx:1.28
          ports:
            - name: http
              containerPort: 80
          env:
            - name: DNS_IP
              value: REPLACE_DNS_IP
            - name: NGINX_ENVSUBST_FILTER
              value: '^DNS_IP$'
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              cpu: 25m
              memory: 32Mi
            limits:
              cpu: 250m
              memory: 128Mi
          volumeMounts:
            - name: config
              mountPath: /etc/nginx/templates/default.conf.template
              subPath: default.conf.template
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: nginx-lb-conf
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
  namespace: nginx-lab
spec:
  type: NodePort
  selector:
    app: nginx-lb
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 32452
EOF_YAML
sed -i "s/REPLACE_DNS_IP/${DNS_IP}/" lb.yaml
k apply -f lb.yaml
k rollout status deployment/nginx-lb --timeout=180s
k exec deployment/nginx-lb -- nginx -t
k exec deployment/nginx-lb -- nginx -T
curl -fsS -D - "http://${NODE_IP}:32452/"
