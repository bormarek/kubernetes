#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
POD=$(cat "$LAB_DIR/probe-pod.txt")
k describe pod "$POD"
k logs "$POD" --previous
k get endpointslices -l kubernetes.io/service-name=nginx-headless -o yaml
