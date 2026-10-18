#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
cat > services.yaml <<'EOF_YAML'
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: nginx-lab
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 32451
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-headless
  namespace: nginx-lab
spec:
  clusterIP: None
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: http
EOF_YAML
k apply -f services.yaml
k get services
microk8s kubectl get nodes -o wide
