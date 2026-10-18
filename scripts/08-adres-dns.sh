#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
DNS_IP=$(microk8s kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')
printf 'DNS klastra: %s\n' "$DNS_IP"
