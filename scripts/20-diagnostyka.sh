#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
k get deploy,rs,pods,svc,cm
k describe deployment nginx
k logs deployment/nginx --tail=50
k logs deployment/nginx-lb --tail=50
k exec deployment/nginx -- cat /usr/share/nginx/html/index.html
k exec deployment/nginx-lb -- cat /etc/resolv.conf
microk8s kubectl -n kube-system get pods -l k8s-app=kube-dns
