#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
require_node_ip
k apply -f backend-v1.yaml
k annotate deployment/nginx kubernetes.io/change-cause="Przywrócenie danych strony v1" --overwrite
k rollout restart deployment/nginx
k rollout status deployment/nginx --timeout=240s
curl -fsS "http://${NODE_IP}:32452/"
cp backend-v1.yaml backend.yaml
