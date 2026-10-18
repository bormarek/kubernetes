#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
require_node_ip
GOOD_REV=$(cat "$LAB_DIR/good-revision.txt")
[[ "$GOOD_REV" =~ ^[0-9]+$ ]] || { echo "Nieprawidłowa rewizja" >&2; exit 1; }
k rollout undo deployment/nginx --to-revision="$GOOD_REV"
k rollout status deployment/nginx --timeout=240s
k get deployment nginx
k rollout history deployment/nginx
curl -fsS "http://${NODE_IP}:32452/"
