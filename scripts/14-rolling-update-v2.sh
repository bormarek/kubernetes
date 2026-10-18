#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
require_node_ip
cp backend.yaml backend-v1.yaml
sed -i 's/Wersja strony: v1/Wersja strony: v2/' backend.yaml
k apply -f backend.yaml
k annotate deployment/nginx kubernetes.io/change-cause="Strona v2 + rollout restart" --overwrite
k rollout restart deployment/nginx
k rollout status deployment/nginx --timeout=240s
curl -fsS "http://${NODE_IP}:32452/"
k get replicasets -l app=nginx
k rollout history deployment/nginx
