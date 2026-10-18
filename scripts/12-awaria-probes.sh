#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
POD=$(k get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
printf '%s\n' "$POD" > "$LAB_DIR/probe-pod.txt"
k exec "$POD" -- rm /usr/share/nginx/html/index.html
k get pod "$POD" --watch
