#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
require_node_ip
POD=$(k get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
k delete pod "$POD"
k rollout status deployment/nginx --timeout=240s
k get pods -l app=nginx -o wide
k get endpointslices -l kubernetes.io/service-name=nginx-headless -o wide
for i in $(seq 1 30); do
  curl --max-time 3 -sS -D - "http://${NODE_IP}:32452/" | sed -n '/X-Upstream-Addr/Ip; /<p>Pod:/p'
  sleep 1
done
