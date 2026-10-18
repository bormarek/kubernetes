#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
require_node_ip
k get pods -l app=nginx
k get replicasets -l app=nginx
k get events --sort-by=.metadata.creationTimestamp
curl -fsS "http://${NODE_IP}:32452/"
